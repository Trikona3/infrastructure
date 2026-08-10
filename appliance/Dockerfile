FROM mariadb:11

ENV DEBIAN_FRONTEND=noninteractive \
    WORDPRESS_VERSION=7.0.2 \
    WORDPRESS_MD5=3599351e7c455a07da2a1c90836d7235

RUN apt-get update && apt-get install -y \
    nginx \
    redis-server \
    supervisor \
    php8.3-fpm \
    php8.3-cli \
    php8.3-mysql \
    php8.3-xml \
    php8.3-mbstring \
    php8.3-curl \
    php8.3-gd \
    php8.3-intl \
    php8.3-zip \
    php8.3-imagick \
    php8.3-redis \
    curl \
    wget \
    unzip \
    less \
    vim \
    rsync \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
    /data/wordpress \
    /data/mariadb \
    /data/redis \
    /run/php \
    /run/mysqld \
    /var/log/supervisor \
    /usr/local/share/construwx \
    /usr/src/wordpress

# PHP-FPM must match nginx fastcgi_pass 127.0.0.1:9000
RUN sed -i 's|^listen = .*|listen = 127.0.0.1:9000|' /etc/php/8.3/fpm/pool.d/www.conf

# WP-CLI
RUN curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Bake complete WordPress core into the image (volume may have incomplete core)
RUN set -eux; \
    curl -fsSL -o /tmp/wordpress.tar.gz \
      "https://wordpress.org/wordpress-${WORDPRESS_VERSION}.tar.gz"; \
    echo "${WORDPRESS_MD5} /tmp/wordpress.tar.gz" | md5sum -c -; \
    tar -xzf /tmp/wordpress.tar.gz -C /usr/src/; \
    rm /tmp/wordpress.tar.gz; \
    chown -R www-data:www-data /usr/src/wordpress

COPY nginx.conf /etc/nginx/sites-available/default
COPY php-custom.ini /etc/php/8.3/fpm/conf.d/99-construwx.ini
COPY php-custom.ini /etc/php/8.3/cli/conf.d/99-construwx.ini
COPY redis.conf /etc/redis/redis.conf
COPY supervisord.conf /etc/supervisor/conf.d/construwx.conf
COPY entrypoint.sh /usr/local/bin/construwx-entrypoint
COPY scripts/wait-for-db.sh /usr/local/bin/construwx-wait-for-db
COPY scripts/import-db.sh /usr/local/bin/construwx-import-db
COPY scripts/ensure-wordpress-core.sh /usr/local/bin/construwx-ensure-wordpress-core
COPY scripts/set-domain.sh /usr/local/bin/construwx-set-domain

RUN chmod +x \
    /usr/local/bin/construwx-entrypoint \
    /usr/local/bin/construwx-wait-for-db \
    /usr/local/bin/construwx-import-db \
    /usr/local/bin/construwx-ensure-wordpress-core \
    /usr/local/bin/construwx-set-domain

EXPOSE 80

ENTRYPOINT ["construwx-entrypoint"]
