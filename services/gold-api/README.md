# ScriptGold — gold-api

NestJS API + landing + Baileys WhatsApp + Telegram. Migrado da Railway.

## Endpoints

- Public: `https://scriptgold.com.br`
- Health: `GET /health`
- Admin UI (separado): `https://adm.scriptgold.com.br`

## Persistencia

- `/opt/docker/gold-api/auth_info` → `/data/auth_info` (sessao Baileys)

## Rede

- `gold-api-net` (egress WhatsApp/Telegram)
- `proxy` (Traefik)

## MongoDB

Externo (`DATABASE_URL`). Nao usa Postgres da VPS.

## Monitoramento

- Uptime Kuma: HTTP `https://scriptgold.com.br/health`
- Dozzle: container `gold-api`
- Docker HEALTHCHECK embutido na imagem
