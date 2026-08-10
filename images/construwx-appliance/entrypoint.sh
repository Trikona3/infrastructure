#!/usr/bin/env bash
set -e

mkdir -p /data/wordpress /data/mariadb /data/redis /run/php /run/mysqld

# Restore/complete WordPress core from the image without touching wp-content or wp-config
/usr/local/bin/construwx-ensure-wordpress-core

chown -R mysql:mysql /data/mariadb /run/mysqld
chown -R redis:redis /data/redis
chown -R www-data:www-data /data/wordpress || true

echo "Starting ConstruWX appliance..."
/usr/bin/supervisord -c /etc/supervisor/conf.d/construwx.conf &
SUPERVISOR_PID=$!

shutdown() {
  kill -TERM "${SUPERVISOR_PID}" 2>/dev/null || true
  wait "${SUPERVISOR_PID}" 2>/dev/null || true
}
trap shutdown SIGTERM SIGINT

if [[ "${CONSTRUWX_RUN_DOMAIN_CUTOVER:-false}" == "true" ]]; then
  echo "CONSTRUWX_RUN_DOMAIN_CUTOVER=true — waiting for DB then running domain cutover..."
  /usr/local/bin/construwx-wait-for-db
  /usr/local/bin/construwx-set-domain
fi

wait "${SUPERVISOR_PID}"
