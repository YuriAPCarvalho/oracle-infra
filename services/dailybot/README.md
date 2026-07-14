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

## Monitoramento (Uptime Kuma)

O bot **não** expõe HTTP. Use monitor tipo **Push** (não HTTP/TCP):

1. No Kuma, criar monitor Push com heartbeat ~**180s**.
2. Em `compose/dailybot/.env`:
   `KUMA_PUSH_URL=http://uptime-kuma:3001/api/push/<token>`
   (opcional: `KUMA_PUSH_INTERVAL_SECONDS=60`).
3. Rede `proxy` já liga o container ao hostname `uptime-kuma`.
4. Desativar qualquer monitor HTTP/TCP antigo do DailyBot (causa falso “off”).

## Deploy rápido

```bash
sudo mkdir -p /opt/docker/dailybot/storage
# Preencher compose/dailybot/.env (Discord, GLPI, DATABASE_URL, KUMA_PUSH_URL)
cd /opt/infra
docker compose -f compose/dailybot/compose.yml up -d
docker logs -f dailybot
# Uma vez:
docker exec dailybot node /app/apps/bot/dist/deploy-commands.js
```

## Discovery

Ver [DISCOVERY.md](./DISCOVERY.md).
