# ConstruWX Appliance

Single-container ConstruWX stack for side-by-side testing and disaster recovery.

**Image:** `construwx-appliance:0.1`  
**Compose:** [`compose/construwx-appliance`](.)  
**Dockerfile:** [`images/construwx-appliance`](../../images/construwx-appliance)

This runs **beside** the multi-container stack at [`compose/construwx`](../construwx). Do not point both at the same MariaDB/Redis data at the same time.

---

## What it includes

One image runs:

| Component | Role |
|-----------|------|
| Nginx | HTTP on container port `80` (host `8099`) |
| PHP-FPM 8.3 | WordPress runtime |
| MariaDB 11 | Database (`127.0.0.1` inside the container) |
| Redis | Local cache (starts empty; optional) |
| Supervisor | Process manager |
| WP-CLI | `/usr/local/bin/wp` |
| WordPress core 7.0.2 | Baked at `/usr/src/wordpress`; synced into the volume on every start |

On boot, the entrypoint:

1. Ensures WordPress **core** (`wp-admin`, `wp-includes`, root PHP) is complete from the image  
2. Does **not** overwrite `wp-content/`, `wp-config.php`, or `wp-salt.php`  
3. Starts MariaDB, Redis, PHP-FPM, and Nginx under Supervisor  

That fixes incomplete WordPress trees (e.g. missing `wp-admin/admin-ajax.php`) without wiping site content.

---

## Layout

```text
images/construwx-appliance/
  Dockerfile
  entrypoint.sh
  nginx.conf
  php-custom.ini
  redis.conf
  supervisord.conf
  scripts/
    ensure-wordpress-core.sh
    wait-for-db.sh
    import-db.sh

compose/construwx-appliance/
  docker-compose.yml
  .env                 # secrets (not committed)
  .gitignore
  import/              # optional SQL seed (*.sql.gz, not committed)
  README.md
```

### Persistent volumes (Docker named volumes)

| Volume name | Mount | What to keep |
|-------------|-------|--------------|
| `construwx_appliance_wordpress` | `/data/wordpress` | `wp-content/`, `wp-config.php`, `wp-salt.php`, uploads, plugins, themes |
| `construwx_appliance_mariadb` | `/data/mariadb` | MariaDB datadir (required for site content) |
| `construwx_appliance_redis` | `/data/redis` | Redis AOF/RDB (cache only; safe to discard) |

Compose declares these as **external** volumes with fixed names so backups and restores stay predictable.

**Where Docker stores them on Linux (default):**

```text
/var/lib/docker/volumes/construwx_appliance_wordpress/_data
/var/lib/docker/volumes/construwx_appliance_mariadb/_data
/var/lib/docker/volumes/construwx_appliance_redis/_data
```

Prefer `docker` volume commands over editing those paths by hand.

---

## Prerequisites

- Docker Engine + Compose v2  
- Free host port **8099** (8088 is often used by other stacks on this host)  
- `.env` with at least:

```env
DB_NAME=construwx
DB_USER=construwx
DB_PASSWORD=...
DB_ROOT_PASSWORD=...
TZ=America/Denver
```

Copy from the multi-container stack if seeding from it:

```bash
cp /opt/infrastructure/compose/construwx/.env \
   /opt/infrastructure/compose/construwx-appliance/.env
```

---

## Quick start

```bash
cd /opt/infrastructure/compose/construwx-appliance

# Create volumes once
docker volume create construwx_appliance_wordpress
docker volume create construwx_appliance_mariadb
docker volume create construwx_appliance_redis

# Build and run
docker compose build
docker compose up -d

docker logs -f construwx-appliance
curl -sI http://localhost:8099/
```

### First-time seed from the live multi-container stack

Keep the live stack running. Use **copies / SQL**, never the live MariaDB datadir.

**1. WordPress files → volume**

```bash
docker volume create construwx_appliance_wordpress

docker run --rm \
  -v /opt/infrastructure/compose/construwx/data/wordpress:/src:ro \
  -v construwx_appliance_wordpress:/dest \
  alpine sh -c 'apk add --no-cache rsync && rsync -a /src/ /dest/'
```

**2. Point the appliance copy at local DB (do not edit the live `wp-config.php`)**

```bash
docker run --rm -v construwx_appliance_wordpress:/dest alpine \
  sed -i "s/define( 'DB_HOST', 'mariadb' );/define( 'DB_HOST', '127.0.0.1' );/" \
  /dest/wp-config.php
```

For local HTTP testing on port 8099, set domain / URLs to `localhost:8099` (WP-CLI inside the running appliance is preferred):

```bash
docker exec -w /data/wordpress construwx-appliance \
  wp --allow-root --url=http://localhost:8099/ option get siteurl
```

**3. Database → SQL import (not a live datadir copy)**

Stage a dump (example uses the existing gz dump):

```bash
mkdir -p import
cp /opt/infrastructure/compose/construwx/myedt006_mydev.sql.gz \
   import/construwx.sql.gz
```

Start the appliance so MariaDB initializes the empty volume, then:

```bash
docker compose up -d
docker exec construwx-appliance construwx-import-db
```

Or:

```bash
docker exec construwx-appliance bash -lc \
  'zcat /import/construwx.sql.gz | mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"'
```

**4. Redis**

No seed required. Cache only.

---

## Day-to-day usage

```bash
cd /opt/infrastructure/compose/construwx-appliance

docker compose up -d
docker compose down          # stops container; volumes kept
docker compose logs -f
docker exec -it construwx-appliance bash
```

### WP-CLI

```bash
docker exec -w /data/wordpress construwx-appliance \
  wp --allow-root --url=http://localhost:8099/ core version

docker exec -w /data/wordpress construwx-appliance \
  wp --allow-root --url=http://localhost:8099/ plugin list
```

### Browser access

- On the VPS: `http://localhost:8099/`  
- From your laptop (recommended while domain is `localhost:8099`):

```bash
ssh -L 8099:127.0.0.1:8099 USER@YOUR_VPS_IP
```

Then open `http://localhost:8099/`.

Login UI for this site is typically `/trikona-login/` (not `/wp-login.php`).

Nginx Proxy Manager is **not** wired in V1; prove the appliance on `8099` first.

---

## Backup

Back up **wordpress** + **mariadb** volumes. Redis is optional.

### Option A — volume archives (simple DR)

```bash
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT=/opt/infrastructure/backups/construwx-appliance-$TS
mkdir -p "$OUT"

# Prefer a quiet DB: stop appliance briefly, or use mariadb-dump instead of raw files
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

# Optional
docker run --rm \
  -v construwx_appliance_redis:/data:ro \
  -v "$OUT":/backup \
  alpine tar czf /backup/redis.tgz -C /data .
```

Also save the image and env:

```bash
docker save construwx-appliance:0.1 | gzip > "$OUT/construwx-appliance-0.1.tar.gz"
cp .env "$OUT/env.backup"   # keep offline / encrypted
```

### Option B — logical DB dump (portable)

While the appliance is running:

```bash
docker exec construwx-appliance bash -lc \
  'mariadb-dump -u root -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --triggers "$MARIADB_DATABASE"' \
  | gzip > construwx-db-$(date -u +%Y%m%d).sql.gz
```

Pair with an rsync/tarball of the wordpress volume (or at least `wp-content` + `wp-config.php` + `wp-salt.php`).

### Suggested backup location on this host

```text
/opt/infrastructure/backups/construwx-appliance-<timestamp>/
  wordpress.tgz
  mariadb.tgz
  redis.tgz                 # optional
  construwx-appliance-0.1.tar.gz
  env.backup                # secrets — restrict permissions
```

Keep backups off-box (S3, another VPS, etc.) for real DR.

---

## Restore / recreate from image + volumes

You can recreate the **entire site** from:

1. Image `construwx-appliance:0.1` (runtime + WP core)  
2. Volume `construwx_appliance_wordpress` (site files / config / uploads)  
3. Volume `construwx_appliance_mariadb` (database)  
4. Volume `construwx_appliance_redis` (optional; empty is fine)  
5. `.env` with DB credentials matching the datadir / `wp-config.php`

```bash
# Load image if needed
gunzip -c construwx-appliance-0.1.tar.gz | docker load

docker volume create construwx_appliance_wordpress
docker volume create construwx_appliance_mariadb
docker volume create construwx_appliance_redis

# Restore tarballs into volumes
docker run --rm \
  -v construwx_appliance_wordpress:/data \
  -v /path/to/backup:/backup:ro \
  alpine sh -c 'cd /data && tar xzf /backup/wordpress.tgz'

docker run --rm \
  -v construwx_appliance_mariadb:/data \
  -v /path/to/backup:/backup:ro \
  alpine sh -c 'cd /data && tar xzf /backup/mariadb.tgz'

cp /path/to/backup/env.backup /opt/infrastructure/compose/construwx-appliance/.env

cd /opt/infrastructure/compose/construwx-appliance
docker compose up -d
```

Fresh DB from SQL instead of a datadir tarball:

```bash
# empty mariadb volume + import/construwx.sql.gz
docker exec construwx-appliance construwx-import-db
```

---

## Rebuild image

```bash
cd /opt/infrastructure/compose/construwx-appliance
docker compose build --no-cache
docker compose up -d --force-recreate
```

After recreate, logs should show:

```text
Ensuring WordPress core in /data/wordpress from /usr/src/wordpress...
WordPress core OK (admin-ajax.php present).
Starting ConstruWX appliance...
```

---

## Important constraints

- **Do not** mount live `compose/construwx/data/mariadb` (or redis) into the appliance while the multi-container stack is running.  
- Appliance WordPress must use `DB_HOST` `127.0.0.1`, not Compose hostname `mariadb`.  
- Domain in this test setup is often `localhost:8099`; browsing via raw VPS IP will not match that host without SSH tunnel or a domain change.  
- Image alone is not a full backup — **volumes (or SQL + wp-content) hold the site**.

---

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| Login POST `404` / `Primary script unknown` | Incomplete WP core — recreate container so core sync runs, or `wp core download --force --skip-content` |
| Redirect to production domain | `DOMAIN_CURRENT_SITE` / `siteurl` / `home` still old — fix with WP-CLI on the appliance only |
| Redirect loop on `:8099` | Nginx must pass `$http_host` (with port) as `HTTP_HOST` — already in image `nginx.conf` |
| Port bind error on `8099` | Something else listening; change host port in `docker-compose.yml` |

```bash
docker logs construwx-appliance --tail 100
docker exec construwx-appliance ls -la /data/wordpress/wp-admin/admin-ajax.php
curl -sI http://localhost:8099/
curl -sI http://localhost:8099/trikona-login/
```
