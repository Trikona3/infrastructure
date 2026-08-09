#!/usr/bin/env bash
set -e

mkdir -p /data/wordpress /data/mariadb /data/redis /run/php /run/mysqld

# Restore/complete WordPress core from the image without touching wp-content or wp-config
/usr/local/bin/construwx-ensure-wordpress-core

chown -R mysql:mysql /data/mariadb /run/mysqld
chown -R redis:redis /data/redis
chown -R www-data:www-data /data/wordpress || true

echo "Starting ConstruWX appliance..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/construwx.conf
