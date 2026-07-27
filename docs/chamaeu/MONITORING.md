# ChamaEu — monitoramento

## Uptime Kuma (HTTP)

Criar monitors (Settings → Monitors):

| Nome | URL | Intervalo | Alertas |
|------|-----|-----------|---------|
| chamaeu-api-health | `https://api.chamaeu.app/health` | 60s | JSON keyword `"status":"ok"` ou HTTP 200 |
| chamaeu-web | `https://chamaeu.app` | 120s | HTTP 200 |
| chamaeu-adm | `https://adm.chamaeu.app` | 120s | HTTP 200 |
| chamaeu-api-cert | `https://api.chamaeu.app` | 1d | Cert expiry |
| scriptgold-api | (existente) | — | — |

**Pré-cutover:** use `curl --resolve api.chamaeu.app:443:127.0.0.1 https://api.chamaeu.app/health` na VPS ou `/etc/hosts` local.

### Notificações

- Pipeline deploy: Discord (ver [DISCORD_NOTIFICATIONS.md](../DISCORD_NOTIFICATIONS.md)).
- Uptime Kuma: configurar notification (Discord webhook ou e-mail) — canal a definir pelo operador.

Import opcional: [`services/chamaeu/uptime-kuma-monitors.json`](../../services/chamaeu/uptime-kuma-monitors.json).

## Host e containers

```bash
cd /opt/infra
make health
make status
make logs SERVICE=rankao-api TAIL=200
```

`scripts/lib/common.sh` inclui `redis`, `waha`, `rankao-api`, `rankao-web`, `rankao-adm`.

## Logs (Dozzle)

Túnel SSH → `http://127.0.0.1:8081` — filtrar `rankao-api`, `waha`, `redis`.

## Runbook — `/health` unhealthy

| Campo JSON | Causa provável | Ação |
|------------|----------------|------|
| `database: error` | Postgres down, credencial, pool | `docker logs postgres`, testar `DATABASE_URL` |
| `redis: error` | Redis down | `cd compose/redis && docker compose ps` |
| `redis: not_configured` | `REDIS_URL` ausente | Corrigir `.env` rankao-api |

## Runbook — WhatsApp

1. `docker logs waha --tail 100`
2. Session status: `curl -H "X-Api-Key: $WAHA_API_KEY" http://127.0.0.1:3000/api/sessions` (via SSH + docker exec network)
3. Jobs BullMQ: logs `rankao-api` event `notification.job.failed`

## Backup

Incluir no ciclo `make backup`:

- Postgres DB `rankao` (dump lógico via script dedicado — ver rankao-api migration scripts)
- `/opt/docker/waha/sessions`
- `/opt/docker/redis/data` (opcional — fila efêmera)

## Cron host (opcional)

```cron
# /etc/cron.d/oracle-infra-health
*/15 * * * * ubuntu cd /opt/infra && make health >> /opt/infra/logs/health.log 2>&1
```
