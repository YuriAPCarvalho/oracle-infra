# ScriptGold — gold-admin

Next.js admin UI. Migrado da Railway.

## Endpoints

- Public: `https://adm.scriptgold.com.br`
- Health: `GET /health`
- API: `NEXT_PUBLIC_API_URL=https://scriptgold.com.br`

## Rede

- `proxy` (Traefik)

## Monitoramento

- Uptime Kuma: HTTP `https://adm.scriptgold.com.br/health`
- Dozzle: container `gold-admin`
