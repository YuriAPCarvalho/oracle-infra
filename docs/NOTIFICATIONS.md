# Plano de notificações — VPS Oracle

Escopo: **129.146.161.65** (Oracle Cloud ARM64). Gestor Agro / Marca7 **não** faz parte desta VPS.

## Canais Discord recomendados

| Canal | Webhook / secret | O quê |
|-------|------------------|--------|
| `#infra-alertas` (ou equivalente) | `KUMA_DISCORD_WEBHOOK_URL` em `compose/uptime-kuma/.env` | Uptime Kuma: DOWN/UP de monitores |
| `#deploys` / `#ci-infra` | GitHub secret `DISCORD_WEBHOOK_URL` | CI/CD: deploy, rollback, falha de healthcheck |
| `#bots` (opcional) | `BOT_DISCORD_WEBHOOK` nos compose dos bots | Eventos funcionais (dailybot) — não substituem Push |

Nunca misturar o webhook de CI com o do Kuma. Ver [DISCORD_NOTIFICATIONS.md](DISCORD_NOTIFICATIONS.md) e [UPTIME_KUMA.md](UPTIME_KUMA.md).

## Camada A — Disponibilidade (Uptime Kuma)

| Prioridade | Monitor | Tipo |
|------------|---------|------|
| P0 | Traefik / edge | HTTP (rede `proxy`) |
| P0 | Portainer, Dozzle | HTTP |
| P0 | ScriptGold API / Admin | HTTP público `/health` |
| P0 | ChamaEu API / Web / Admin | HTTP público + keyword em `/health` — [chamaeu/MONITORING.md](chamaeu/MONITORING.md) |
| P1 | Daily Bot | **Push** (`KUMA_PUSH_URL` no `.env` do serviço) |
| P1 | Rankao / WAHA / outros | HTTP ou Push conforme expõem health |

Regras:

- Só mensagens em **DOWN** e **UP** (não spam de OK).
- Push: heartbeat ~60s no app, timeout ~180s no Kuma.

## Camada B — Pipeline CI/CD

Workflows em [`.github/workflows/reusable-vps-deploy.yml`](../.github/workflows/reusable-vps-deploy.yml). Webhook separado do Kuma.

## Camada C — Opcional

- **Watchtower**: `WATCHTOWER_NOTIFICATION_URL` — só se quiser aviso de imagem atualizada ([`compose/watchtower/.env.example`](../compose/watchtower/.env.example)).

## Camada D — Sem Discord

- Heartbeats OK do Kuma.
- `make health` local — usar Kuma ou logs, não duplicar webhook.

## Checklist pós-configuração

1. `bash scripts/uptime-kuma-verify-notifications.sh` na VPS.
2. Teste **Send Test** na notificação `discord-infra` (UI Kuma).
3. DOWN controlado em monitor não crítico → mensagem no Discord → restaurar → mensagem UP.
