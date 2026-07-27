# ChamaEu on Oracle VPS

Production hosts:

- `https://chamaeu.app` → `rankao-web`
- `https://api.chamaeu.app` → `rankao-api`
- `https://adm.chamaeu.app` → `rankao-adm`

Internal: `redis`, `waha`, Postgres database `rankao`.

Uptime Kuma: `bash scripts/uptime-kuma-seed-chamaeu-monitors.sh` (ou seed completo `uptime-kuma-seed-monitors.sh`). Ver [MONITORING.md](../../docs/chamaeu/MONITORING.md).

## Docs

- [STORAGE.md](STORAGE.md)
- [CAPACITY.md](CAPACITY.md)
- [../../docs/chamaeu/MONITORING.md](../../docs/chamaeu/MONITORING.md)
- [../../docs/chamaeu/DNS_CUTOVER.md](../../docs/chamaeu/DNS_CUTOVER.md)

## Bootstrap order

```bash
cd /opt/infra
bash scripts/postgres-create-db.sh --name rankao --password '***'
sudo mkdir -p /opt/docker/redis/data /opt/docker/waha/sessions
sudo chown -R ubuntu:ubuntu /opt/docker/redis /opt/docker/waha

cd compose/redis && cp .env.example .env && docker compose up -d
cd ../waha && cp .env.example .env && docker compose up -d
# Pair WAHA session (QR) before enabling DISPARAR_NOTIFICACAO_WHATSAPP

cd ../rankao-api && cp .env.example .env && docker compose up -d
cd ../rankao-web && cp .env.example .env && docker compose up -d
cd ../rankao-adm && cp .env.example .env && docker compose up -d
```
