# Bot de Ponto

Fonte: aplicação `secullum-web-automate` (npm `central-funcionario-bot`).
Levantamento: [DISCOVERY.md](./DISCOVERY.md).

**Status:** experimental — primeiro deploy na VPS com imagem local ARM64; GHCR + CI caller ativos no repo da app. Critérios 31.13 ainda não ficam todos verdes até smoke Chromium + janela real validados.

## Compose

- Path: `compose/bot-ponto/`
- Rede: `bot-ponto-net` (egress) + `proxy` (Push Kuma / DNS interno)
- Dados: `/opt/docker/bot-ponto/{browser-state,state,screenshots}`
- Sem Traefik / sem portas publicadas

## Deploy rápido (VPS)

```bash
sudo mkdir -p /opt/docker/bot-ponto/{browser-state,state,screenshots}
# Preencher compose/bot-ponto/.env (SERVICE_IMAGE, CENTRAL_*, BOT_DISCORD_WEBHOOK, ALLOW_FINAL_CLICK, KUMA_PUSH_URL)
cd /opt/infra
docker compose -f compose/bot-ponto/compose.yml up -d
docker logs -f bot-ponto
```

## Monitoramento

- Docker HEALTHCHECK via `heartbeat.json`
- Uptime Kuma Push (`KUMA_PUSH_URL`) a cada ~5 min
- Discord do bot: `BOT_DISCORD_WEBHOOK` (separado do CI)

## Variáveis

Ver [compose/bot-ponto/.env.example](../../compose/bot-ponto/.env.example). Segredos só na VPS.
