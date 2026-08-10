# ConstruWX Appliance

Single-container ConstruWX runtime for running or recovering the site on a fresh host.

**Image:** `construwx-appliance:0.1`  
**Compose project:** this directory  
**Image source:** [`images/construwx-appliance`](../../images/construwx-appliance)

One container provides Nginx, PHP-FPM 8.3, MariaDB 11, Redis, Supervisor, WP-CLI, and a complete WordPress core. Site content and the database live in **external Docker volumes** that you supply from backups.

---

## What you need

On a **new VPS** you need only:

1. Docker Engine + Docker Compose v2  
2. This repository (or the image tarball + this compose folder)  
3. **Your backups** (you own storage and rotation — S3, another disk, USB, etc.)  
4. A `.env` file with database credentials that match the restored site  

Backups are **not** stored in this repo. Keep them somewhere durable; restoring without them cannot recreate posts, media, plugins, or the database.

### Required backup set

| Artifact | Required | Purpose |
|----------|----------|---------|
| `wordpress.tgz` | **Yes** | WordPress volume: `wp-content/`, `wp-config.php`, `wp-salt.php`, uploads, plugins, themes |
| `mariadb.tgz` **or** `construwx.sql.gz` | **Yes** | Database (datadir archive **or** logical SQL dump) |
| `env.backup` / `.env` | **Yes** | `DB_*` passwords and related settings must match the DB / `wp-config.php` |
| `construwx-appliance-0.1.tar.gz` | Recommended | Pre-built image if you cannot build from this repo |
| `redis.tgz` | No | Cache only; omit and start with an empty Redis volume |

### Expected backup layout

Any directory (local path, mounted bucket, etc.):

```text
<backup-root>/
  wordpress.tgz              # tar.gz of volume construwx_appliance_wordpress
  mariadb.tgz                # tar.gz of volume construwx_appliance_mariadb
  # OR, instead of mariadb.tgz:
  construwx.sql.gz           # logical dump of database construwx
  env.backup                 # copy of compose .env (restrict permissions)
  construwx-appliance-0.1.tar.gz   # optional: docker save of the image
  redis.tgz                  # optional
```

**`wordpress.tgz` / `mariadb.tgz` format:** gzip-compressed tar of the volume **root** (contents of `/data`, not an extra top-level folder):

```bash
# how archives are produced
tar czf wordpress.tgz -C /path/to/volume/_data .
tar czf mariadb.tgz   -C /path/to/volume/_data .
```

**`construwx.sql.gz` format:** `mariadb-dump` / `mysqldump` of database `construwx` (gzip), importable with:

```bash
zcat construwx.sql.gz | mariadb -u root -p… construwx
```

**`.env` keys used by compose** (minimum):

```env
DB_NAME=construwx
DB_USER=construwx
DB_PASSWORD=...
DB_ROOT_PASSWORD=...
TZ=America/Denver
WP_DOMAIN=mydev.construwx.in
WP_SCHEME=https
WP_DB_PREFIX=cnet_
CONSTRUWX_RUN_DOMAIN_CUTOVER=false
```

See [`.env.example`](.env.example). `wp-config.php` in the wordpress backup must use `DB_HOST` `127.0.0.1` (or `localhost`) for this appliance.

---

## Architecture

```text
Browser → Cloudflare → Nginx Proxy Manager (:443)
                           ↓ HTTP
                    construwx-appliance:80
                      ├── Nginx / PHP-FPM 8.3
                      ├── MariaDB 11
                      ├── Redis
                      ├── WP-CLI
                      └── Supervisor

Volumes (external, fixed names):
  construwx_appliance_wordpress  → /data/wordpress
  construwx_appliance_mariadb    → /data/mariadb
  construwx_appliance_redis      → /data/redis

Shared Docker network: construwx_edge
```

On every start the entrypoint syncs WordPress **core** from the image into `/data/wordpress` without overwriting `wp-content/`, `wp-config.php`, or `wp-salt.php`.

Host port **8099** maps to appliance HTTP for lab/debug. Production HTTPS is terminated by **Nginx Proxy Manager** (Let’s Encrypt) — no manual certificate PEM files on the appliance.

---

## Fresh VPS setup

### 1. Install Docker

Example on Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
| sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker "$USER"   # re-login after this
docker version
docker compose version
```

### 2. Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
# Prefer SSH tunnel for NPM UI instead of opening 81 publicly
sudo ufw enable
```

### 3. Get the compose project and image

**Option A — clone and build**

```bash
git clone <this-repo-url> /opt/infrastructure
cd /opt/infrastructure/compose/construwx-appliance
docker compose build
```

**Option B — load a saved image**

```bash
gunzip -c /path/to/construwx-appliance-0.1.tar.gz | docker load
# image name must be: construwx-appliance:0.1
```

### 4. Shared edge network + Nginx Proxy Manager

```bash
docker network create construwx_edge

cd /opt/infrastructure/compose/nginx-proxy-manager
docker compose up -d
```

NPM admin UI: `http://127.0.0.1:81` (or SSH tunnel). Default first login `admin@example.com` / `changeme` — change immediately. Details: [`../nginx-proxy-manager/README.md`](../nginx-proxy-manager/README.md).

### 5. Create volumes and restore backups

```bash
docker volume create construwx_appliance_wordpress
docker volume create construwx_appliance_mariadb
docker volume create construwx_appliance_redis
```

Default data dirs on Linux:

```text
/var/lib/docker/volumes/construwx_appliance_wordpress/_data
/var/lib/docker/volumes/construwx_appliance_mariadb/_data
/var/lib/docker/volumes/construwx_appliance_redis/_data
```

```bash
BACKUP=/path/to/your/backup-root   # your responsibility — any durable location

docker run --rm \
  -v construwx_appliance_wordpress:/data \
  -v "$BACKUP":/backup:ro \
  alpine sh -c 'cd /data && tar xzf /backup/wordpress.tgz'

docker run --rm \
  -v construwx_appliance_mariadb:/data \
  -v "$BACKUP":/backup:ro \
  alpine sh -c 'cd /data && tar xzf /backup/mariadb.tgz'
```

SQL-only alternative: leave MariaDB volume empty, copy `$BACKUP/construwx.sql.gz` to `import/construwx.sql.gz`, start appliance, then `docker exec construwx-appliance construwx-import-db`.

### 6. Configure `.env` and start appliance

```bash
cd /opt/infrastructure/compose/construwx-appliance
cp "$BACKUP/env.backup" .env
chmod 600 .env
# Set the public hostname Cloudflare will use:
#   WP_DOMAIN=mydev.construwx.in
#   WP_SCHEME=https
#   WP_DB_PREFIX=cnet_
#   CONSTRUWX_RUN_DOMAIN_CUTOVER=false

docker compose up -d
docker logs -f construwx-appliance
```

You should see core sync + `Starting ConstruWX appliance...`.

### 7. Domain cutover (detect old host from DB)

`construwx-set-domain` reads the **current** `siteurl` / domain from the restored database (no hardcoded old hostname), then runs serialized-safe `wp search-replace` to `https://${WP_DOMAIN}` and updates multisite / `wp-config` constants.

```bash
docker exec construwx-appliance construwx-set-domain
```

Or set `CONSTRUWX_RUN_DOMAIN_CUTOVER=true` in `.env` so it runs automatically after DB is ready on boot.

### 8. Cloudflare DNS

1. DNS → `A` record for `WP_DOMAIN` → VPS IPv4  
2. Proxy: **DNS only (grey)** for the first Let’s Encrypt HTTP-01 attempt if orange-cloud fails; switch to **Proxied (orange)** after the cert is issued  
3. SSL/TLS → **Full**, then **Full (strict)** once NPM has a valid LE certificate  
4. Optional: Always Use HTTPS  

### 9. NPM Proxy Host (TLS — finish setup)

1. Open NPM → Hosts → Proxy Hosts → Add  
2. Domain Names: exact `WP_DOMAIN`  
3. Scheme `http` → Forward Hostname `construwx-appliance` → Port `80`  
4. Enable Websockets (recommended)  
5. SSL tab → Request a new Let’s Encrypt certificate → agree ToS → **Force SSL** → Save  

No manual certificate files. NPM stores/renews LE certs in its volumes.

If LE fails behind orange cloud: grey-cloud → re-request → orange again; or use NPM’s Cloudflare DNS challenge with an API token.

### 10. Verify production

```bash
curl -sI "https://${WP_DOMAIN}"
docker exec -w /data/wordpress construwx-appliance \
  wp --allow-root --url="https://${WP_DOMAIN}/" option get siteurl
```

Browser: `https://YOUR_DOMAIN/` and `/trikona-login/`.

Lab-only check without DNS: `curl -sI http://localhost:8099/` (SSH tunnel if remote).

---

## Day-to-day commands

```bash
cd /opt/infrastructure/compose/construwx-appliance

docker compose up -d
docker compose down          # volumes are kept
docker compose logs -f
docker exec -it construwx-appliance bash

docker exec construwx-appliance construwx-set-domain

docker exec -w /data/wordpress construwx-appliance \
  wp --allow-root --url="https://${WP_DOMAIN}/" plugin list
```

Login for this product is typically `/trikona-login/`.

---

## Creating backups (your job)

Run on a healthy appliance host. Store the output **anywhere you control**.

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT=/path/to/your/backup-root/construwx-appliance-$TS
mkdir -p "$OUT"

cd /opt/infrastructure/compose/construwx-appliance
docker compose stop

docker run --rm \
  -v construwx_appliance_wordpress:/data:ro \
  -v "$OUT":/backup \
  alpine tar czf /backup/wordpress.tgz -C /data .

docker run --rm \
  -v construwx_appliance_mariadb:/data:ro \
  -v "$OUT":/backup \
  alpine tar czf /backup/mariadb.tgz -C /data .

docker compose start

cp .env "$OUT/env.backup"
chmod 600 "$OUT/env.backup"

docker save construwx-appliance:0.1 | gzip > "$OUT/construwx-appliance-0.1.tar.gz"
```

Logical DB dump (optional complement or alternative to `mariadb.tgz`):

```bash
docker exec construwx-appliance bash -lc \
  'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --triggers "$MARIADB_DATABASE"' \
  | gzip > "$OUT/construwx.sql.gz"
```

Also back up NPM volumes if you want LE/proxy config portable (`npm_data`, `npm_letsencrypt` from the NPM compose project).

Copy `$OUT` off the machine. Losing the VPS without an off-box copy loses the site.

---

## Rebuild image from source

```bash
cd /opt/infrastructure/compose/construwx-appliance
docker compose build --no-cache
docker compose up -d --force-recreate
```

---

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| Login AJAX 404 / `Primary script unknown` | Core sync on boot; confirm `wp-admin/admin-ajax.php` exists after recreate |
| Redirects to wrong domain | Run `construwx-set-domain`; confirm `WP_DOMAIN` |
| LE cert fails in NPM | Grey-cloud DNS for HTTP-01, or Cloudflare DNS-01 token |
| 502 from NPM | Appliance on `construwx_edge`; forward host `construwx-appliance` port `80` |
| DB access denied | `.env` does not match restored datadir or `wp-config.php` |
| Port 80/443 busy | Another NPM/proxy already bound — stop it or migrate to this compose |

```bash
docker logs construwx-appliance --tail 100
docker network inspect construwx_edge
docker exec construwx-appliance ls -la /data/wordpress/wp-admin/admin-ajax.php
curl -sI http://localhost:8099/
```

---

## Summary

| Piece | Who provides it |
|-------|-----------------|
| Docker + Compose | You, on the new VPS |
| Image `construwx-appliance:0.1` | Build from this repo or `docker load` |
| Nginx Proxy Manager | [`compose/nginx-proxy-manager`](../nginx-proxy-manager) — Let’s Encrypt via UI |
| Cloudflare DNS | You — point `WP_DOMAIN` at the VPS |
| Volumes + `.env` | **Your backups** (required; store them yourself) |
| Redis | Optional / empty |

**Image + wordpress volume + mariadb volume (or SQL) + `.env` + NPM + Cloudflare = production site.**
