# ConstruWX Stack Architecture (V1)

## Containers

- nginx
- wordpress (PHP-FPM 8.3)
- mariadb 11
- redis
- phpmyadmin
- wp-cron

## Shared Network

construwx-net

## Persistent Data

data/
    mariadb/
    wordpress/
    redis/

## Configuration

config/
    nginx/
    php/
    mariadb/
    redis/

## Reverse Proxy

Nginx Proxy Manager (shared infrastructure)

## Cloud

Cloudflare

## SSL

Managed by Nginx Proxy Manager

## Secrets

Stored only in .env

## Philosophy

- Immutable containers
- No manual changes inside running containers
- Infrastructure as Code
- Reproducible deployments
- Everything rebuildable from Git