# Nginx Proxy Manager (edge TLS)

Terminates HTTPS with Let’s Encrypt and reverse-proxies to the ConstruWX appliance. No manual certificate PEM files.

## Prerequisites

```bash
docker network create construwx_edge
```

## Start

```bash
cd /opt/infrastructure/compose/nginx-proxy-manager
docker compose up -d
```

Admin UI: `http://YOUR_VPS_IP:81`

Default first login (change immediately):

- Email: `admin@example.com`
- Password: `changeme`

Prefer accessing port `81` over an SSH tunnel rather than opening it publicly:

```bash
ssh -L 81:127.0.0.1:81 USER@YOUR_VPS_IP
```

## Proxy the appliance

1. Hosts → Proxy Hosts → Add  
2. Domain Names: your `WP_DOMAIN` (e.g. `mydev.construwx.in`)  
3. Scheme: `http`  
4. Forward Hostname / IP: `construwx-appliance`  
5. Forward Port: `80`  
6. Enable Websockets Support (recommended)  
7. SSL → Request a new Let’s Encrypt certificate → Force SSL → Save  

The appliance must be on the `construwx_edge` network (see appliance compose).

## Existing NPM on this host

If an older `nginx-proxy-manager` container already binds `80`/`443`, do not start this compose until that container is stopped or migrated. On a fresh VPS, use this project only.
