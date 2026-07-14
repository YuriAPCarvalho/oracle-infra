# DailyBot (SETDIG)

Bot Discord: dailies, pendências, aniversários, monitor GLPI (Playwright).
Repo app: `YuriAPCarvalho/DailyBot` (bot-only; web removida).

**Status:** experimental até cutover Railway validado.

## Compose

- Path: `compose/dailybot/`
- Redes: `dailybot-net` (egress Discord/GLPI) + `internal` (Postgres) + `proxy` (Kuma)
- Dados: `/opt/docker/dailybot/storage` (sessão GLPI)
- Sem Traefik / sem portas
- DB: shared `compose/postgres` → `postgresql://dailybot@postgres:5432/dailybot`

## Deploy rápido

```bash
sudo mkdir -p /opt/docker/dailybot/storage
# Preencher compose/dailybot/.env (Discord, GLPI, DATABASE_URL)
cd /opt/infra
docker compose -f compose/dailybot/compose.yml up -d
docker logs -f dailybot
# Uma vez:
docker exec dailybot node /app/apps/bot/dist/deploy-commands.js
```

## Discovery

Ver [DISCOVERY.md](./DISCOVERY.md).
