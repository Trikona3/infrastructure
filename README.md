# infrastructure

| Path | Purpose |
|------|---------|
| [`appliance/`](appliance/) | **Single-image ConstruWX recovery / production** — Dockerfile, compose, NPM edge, scripts, docs |
| [`compose/construwx/`](compose/construwx/) | Multi-container WordPress stack (dev / legacy parallel run) |
| [`compose/portainer/`](compose/portainer/) | Portainer |
| [`docs/`](docs/), [`env/`](env/), [`scripts/`](scripts/) | Shared notes / helpers |

Start here for disaster recovery or fresh VPS single-container deploy:

```bash
cd /opt/infrastructure/appliance
cat README.md
```
