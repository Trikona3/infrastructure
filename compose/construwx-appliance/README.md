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
```

`wp-config.php` inside the wordpress backup must use `DB_HOST` `127.0.0.1` (or `localhost`) for this appliance — not a remote Compose service name.

---

## Architecture

```text
construwx-appliance:0.1
  ├── Nginx          → host :8099 → container :80
  ├── PHP-FPM 8.3
  ├── MariaDB 11     → datadir /data/mariadb
  ├── Redis          → /data/redis (disposable)
  ├── WP-CLI
  └── Supervisor

Volumes (external, fixed names):
  construwx_appliance_wordpress  → /data/wordpress
  construwx_appliance_mariadb    → /data/mariadb
  construwx_appliance_redis      → /data/redis
```

On every start the entrypoint syncs WordPress **core** (`wp-admin`, `wp-includes`, root PHP) from the image into `/data/wordpress`. It does **not** overwrite `wp-content/`, `wp-config.php`, or `wp-salt.php`. That keeps core complete even if a backup tree was missing files such as `admin-ajax.php`.

Default host port is **8099**. Change `ports` in `docker-compose.yml` if needed.

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

### 2. Get the compose project and image

**Option A — clone and build**

```bash
git clone <this-repo-url> /opt/infrastructure
cd /opt/infrastructure/compose/construwx-appliance
docker compose build
```

**Option B — load a saved image**

```bash
# place compose files under /opt/infrastructure/compose/construwx-appliance
gunzip -c /path/to/construwx-appliance-0.1.tar.gz | docker load
# image name must be: construwx-appliance:0.1
```

### 3. Create volumes

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

### 4. Restore backups into volumes

Set `BACKUP` to wherever you keep the archive set:

```bash
BACKUP=/path/to/your/backup-root   # your responsibility — any durable location

docker run --rm \
  -v construwx_appliance_wordpress:/data \
  -v "$BACKUP":/backup:ro \
  alpine sh -c 'cd /data && tar xzf /backup/wordpress.tgz'

# If you have a MariaDB datadir archive:
docker run --rm \
  -v construwx_appliance_mariadb:/data \
  -v "$BACKUP":/backup:ro \
  alpine sh -c 'cd /data && tar xzf /backup/mariadb.tgz'

# Optional Redis
# docker run --rm \
#   -v construwx_appliance_redis:/data \
#   -v "$BACKUP":/backup:ro \
#   alpine sh -c 'cd /data && tar xzf /backup/redis.tgz'
```

If you restore **SQL instead of** `mariadb.tgz`, leave the MariaDB volume empty, copy the dump for the container to read, then import after first start (step 6).

```bash
mkdir -p import
cp "$BACKUP/construwx.sql.gz" import/construwx.sql.gz
```

### 5. Install `.env`

```bash
cp "$BACKUP/env.backup" .env
chmod 600 .env
```

### 6. Start

```bash
cd /opt/infrastructure/compose/construwx-appliance
docker compose up -d
docker logs -f construwx-appliance
```

You should see:

```text
Ensuring WordPress core in /data/wordpress from /usr/src/wordpress...
WordPress core OK (admin-ajax.php present).
Starting ConstruWX appliance...
```

**SQL-only restore** (empty MariaDB volume + `import/construwx.sql.gz`):

```bash
docker exec construwx-appliance construwx-import-db
```

### 7. Verify

```bash
curl -sI http://localhost:8099/
docker exec -w /data/wordpress construwx-appliance \
  wp --allow-root --url=http://localhost:8099/ core version
```

Open `http://YOUR_VPS_IP:8099/` only if the restored site’s domain/`siteurl` match that host. If the backup was taken for `http://localhost:8099`, use an SSH tunnel from your laptop:

```bash
ssh -L 8099:127.0.0.1:8099 USER@YOUR_VPS_IP
```

Then browse `http://localhost:8099/`. Update domain URLs with WP-CLI if you want a public hostname.

---

## Day-to-day commands

```bash
cd /opt/infrastructure/compose/construwx-appliance

docker compose up -d
docker compose down          # volumes are kept
docker compose logs -f
docker exec -it construwx-appliance bash

docker exec -w /data/wordpress construwx-appliance \
  wp --allow-root --url=http://localhost:8099/ plugin list
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
| Redirects to wrong domain | Restored `siteurl` / `home` / multisite domain — fix with WP-CLI |
| DB access denied | `.env` does not match restored datadir or `wp-config.php` |
| Empty site | Wordpress or MariaDB volume not restored / wrong tar layout |

```bash
docker logs construwx-appliance --tail 100
docker exec construwx-appliance ls -la /data/wordpress/wp-admin/admin-ajax.php
curl -sI http://localhost:8099/
```

---

## Summary

| Piece | Who provides it |
|-------|-----------------|
| Docker + Compose | You, on the new VPS |
| Image `construwx-appliance:0.1` | Build from this repo or `docker load` your saved image |
| Volumes + `.env` | **Your backups** (required; store them yourself) |
| Redis | Optional / empty |

**Image + wordpress volume + mariadb volume (or SQL) + `.env` = full site recovery.**
