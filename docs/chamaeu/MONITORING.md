# ChamaEu — monitoramento

## Uptime Kuma — seed automatizado (VPS)

Na VPS, após criar o admin no Kuma:

```bash
cd /opt/infra
bash scripts/uptime-kuma-seed-monitors.sh    # infra + ScriptGold + ChamaEu
bash scripts/uptime-kuma-seed-discord.sh     # requer compose/uptime-kuma/.env
bash scripts/uptime-kuma-verify-notifications.sh
```

Só ChamaEu (idempotente):

```bash
bash scripts/uptime-kuma-seed-chamaeu-monitors.sh
```

WAHA (`chamaeu-waha-server`, `chamaeu-waha-session`): criados se `compose/waha/.env` tiver `WAHA_API_KEY`, ou `KUMA_SEED_WAHA_MONITORS=true`. Ver [`scripts/uptime-kuma-seed-chamaeu-monitors.sh`](../../scripts/uptime-kuma-seed-chamaeu-monitors.sh).

Validação local / smoke:

```bash
bash scripts/chamaeu-monitoring-validate.sh
bash scripts/chamaeu-monitoring-validate.sh --smoke   # curl produção (RESOLVE_IP=off)
```

Referência / import manual: [`services/chamaeu/uptime-kuma-monitors.json`](../../services/chamaeu/uptime-kuma-monitors.json).

## Catálogo de monitores

### P0 — Produto (HTTP público, caminho real do usuário)

| Nome | URL | Intervalo | Critério |
|------|-----|-----------|----------|
| `chamaeu-api-health` | `https://api.chamaeu.app/health` | 60s | 200 + keyword `"status":"ok"` |
| `chamaeu-web` | `https://chamaeu.app/` | 120s | HTTP 200–299 |
| `chamaeu-adm` | `https://adm.chamaeu.app/` | 120s | HTTP 200–299 |
| `traefik` | (seed infra) `http://traefik:8080/api/overview` | 60s | Edge obrigatório para todos os hosts |

`/health` da API também valida **Postgres + Redis** (503 se `database` ou `redis` ≠ ok). Não é necessário monitor TCP em `postgres`/`redis` enquanto o Kuma não estiver na rede `internal`.

### P1 — Origem Docker (rede `proxy`, sem Cloudflare)

| Nome | URL | Intervalo | Critério |
|------|-----|-----------|----------|
| `chamaeu-api-internal` | `http://rankao-api:3000/health` | 60s | keyword `"status":"ok"` |
| `chamaeu-web-internal` | `http://rankao-web:3000/` | 120s | 200–299 |
| `chamaeu-adm-internal` | `http://rankao-adm:3000/` | 120s | 200–299 |
| `chamaeu-waha-server` | `http://waha:3000/api/server/status` | 120s | Header `X-Api-Key`, 200 |
| `chamaeu-waha-session` | `http://waha:3000/api/sessions` | 120s | keyword `WORKING` |
| `chamaeu-api-health-deep` | `http://rankao-api:3000/health/deep` | 120s | keyword `"whatsappReady":true` (header `X-Health-Token` se `HEALTH_DEEP_TOKEN`) |

**Diagnóstico**

| Público | Interno | Interpretação |
|---------|---------|---------------|
| DOWN | UP | Cloudflare, DNS, certificado Traefik, rota |
| DOWN | DOWN | Container, deploy, env, crash |
| UP | DOWN | Raro; checar proxy / múltiplas origens |

### P2 — Opcional

| Nome | URL | Notas |
|------|-----|--------|
| `chamaeu-privacy` | `https://chamaeu.app/privacy` | App mobile (não no seed automático) |
| `chamaeu-terms` | `https://chamaeu.app/terms` | idem |
| ScriptGold / Dozzle / Portainer | ver [UPTIME_KUMA.md](../UPTIME_KUMA.md) | Mesma VPS |

### P3 — Certificado TLS

Monitores dedicados (1×/dia, `expiry_notification` ativo no Kuma):

| Nome | URL |
|------|-----|
| `chamaeu-api-tls` | `https://api.chamaeu.app` |
| `chamaeu-web-tls` | `https://chamaeu.app` |
| `chamaeu-adm-tls` | `https://adm.chamaeu.app` |

Os monitores P0 de uptime têm expiry desligado para não duplicar alertas de certificado a cada 60–120s.

### Não monitorar via HTTP público

| Alvo | Motivo |
|------|--------|
| `https://uptimekuma.chamaeu.app`, Portainer, Dozzle, Traefik (URLs com Access) | Cloudflare Access — usar monitores internos do seed |
| `POST /pagamento/webhook` | Mercado Pago; smoke manual pós-cutover |

Ver [CLOUDFLARE_ACCESS.md](CLOUDFLARE_ACCESS.md).

**Pré-cutover:** `curl --resolve api.chamaeu.app:443:127.0.0.1 https://api.chamaeu.app/health` na VPS.

### Notificações Discord

- **Uptime Kuma:** `KUMA_DISCORD_WEBHOOK_URL` em `compose/uptime-kuma/.env` → canal `#infra-alertas` (só DOWN/UP).
- **Deploy CI:** webhook separado — [DISCORD_NOTIFICATIONS.md](../DISCORD_NOTIFICATIONS.md).
- **Mensageria (API):** `MENSAGERIA_DISCORD_WEBHOOK_URL` em `compose/rankao-api/.env` → canal `#ops-mensageria` (sessão FAILED, backlog de fila, rajada de falhas de envio). Não reutilizar o webhook de deploy.

Monitores ChamaEu já entram no default de `uptime-kuma-seed-discord.sh`. Override: `KUMA_MONITOR_NAMES=...`.

## Camada E — Produto mensageria / WAHA

Complementa Kuma/Grafana com sinais de cobrança WhatsApp (único canal ativo):

| Sinal | Onde | Alerta |
|-------|------|--------|
| Sessão `FAILED` / `STOPPED` / `LOGOUT` | Webhook WAHA `session.status` → API | Sentry + Discord mensageria |
| Fila `notifications-whatsapp` waiting/failed | Cron 5 min + `GET /health/deep` | Discord mensageria |
| Rajada de falhas de envio (≥5 / 10 min) | `NotificacaoService` + Redis | Discord mensageria + Sentry |
| ack `ERROR` | Webhook `message.ack` | Discord mensageria |
| Kill-switch / template cobrança off | `/health/deep` → `whatsappReady:false` | Kuma deep + logs ADM |
| Jobs BullMQ falha definitiva | Processor WhatsApp | Sentry (`canal=whatsapp`, `codigo=…`) |

**`GET /health/deep`** (rede interna / token opcional `HEALTH_DEEP_TOKEN` via `X-Health-Token`):

- Contagens BullMQ WhatsApp (`waiting` / `active` / `failed` / `delayed`)
- Status sessão WAHA
- Flags `DISPARAR_NOTIFICACAO_WHATSAPP` + template `RAQUETEIRA_COBRANCA.ativo`
- HTTP 200 só se `"whatsappReady":true`; senão 503 `degraded`

Exemplo interno:

```bash
curl -sS http://rankao-api:3000/health/deep
# com token: -H "X-Health-Token: $HEALTH_DEEP_TOKEN"
```

### Fase 3 — Prometheus / Grafana de negócio (adiado)

Quando o volume de cobrança WhatsApp justificar, adicionar `prom-client` na API (`whatsapp_enqueued|sent|failed`, `whatsapp_ack`, gauge de fila), scrape no Prometheus do oracle-infra e painel Grafana “ChamaEu Mensageria”. Até lá: ADM Logs + Sentry + Discord mensageria + `/health/deep`.

## Limites do Uptime Kuma (Camada D)

| Risco | Alternativa |
|-------|-------------|
| Cron Nest (torneio, expiração inscrição) | Logs `rankao-api`; `/health/deep` para fila/WAHA |
| BullMQ / `notification.job.failed` | Logs + Sentry + Discord mensageria + runbook abaixo |
| Mercado Pago | Teste manual; logs `mercadopago.webhook.*` |
| RAM/disco host | `make health`, cron opcional abaixo |
| Object storage OCI / MinIO | Fora do Kuma ou URL pública dedicada |

## Host e containers

```bash
cd /opt/infra
make health
make status
make logs SERVICE=rankao-api TAIL=200
```

`scripts/lib/common.sh` inclui `redis`, `waha`, `rankao-api`, `rankao-web`, `rankao-adm`.

## Logs (Dozzle)

Túnel SSH → painel Dozzle — filtrar `rankao-api`, `waha`, `redis`.

## Runbook — `/health` unhealthy

| Campo JSON | Causa provável | Ação |
|------------|----------------|------|
| `database: error` | Postgres down, credencial, pool | `docker logs postgres`, testar `DATABASE_URL` |
| `redis: error` | Redis down | `cd compose/redis && docker compose ps` |
| `redis: not_configured` | `REDIS_URL` ausente | Corrigir `.env` rankao-api |

## Runbook — WhatsApp / sessão

1. Kuma `chamaeu-waha-session` ou Discord mensageria “Sessão WAHA crítica” → ADM **Mensageria → Reiniciar sessão / QR**
2. `docker logs waha --tail 100` e `docker logs rankao-api --tail 200` (eventos `waha.webhook.session_status`, `notification.job.failed`)
3. Session status: `curl -H "X-Api-Key: $WAHA_API_KEY" http://waha:3000/api/sessions` (rede Docker / exec)
4. Saúde profunda: `curl -sS http://rankao-api:3000/health/deep` — checar `queue.waiting` / `waha.status` / `dispararWhatsApp`
5. Confirmar kill-switch `DISPARAR_NOTIFICACAO_WHATSAPP=true` e template `RAQUETEIRA_COBRANCA` ativo no ADM
6. Re-parear QR se status ≠ `WORKING` ([`services/chamaeu/README.md`](../../services/chamaeu/README.md))

## Backup

Incluir no ciclo `make backup`:

- Postgres DB `rankao` (dump lógico via script dedicado — ver rankao-api migration scripts)
- `/opt/docker/applications/waha/sessions`
- `/opt/docker/databases/redis/data` (opcional — fila efêmera)

## Cron host (opcional)

```cron
# /etc/cron.d/oracle-infra-health
*/15 * * * * ubuntu cd /opt/infra && make health >> /opt/infra/logs/health.log 2>&1
```
