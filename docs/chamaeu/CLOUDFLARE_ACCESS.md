# chamaeu.app — painéis + Cloudflare Access

Padrão igual [MARCA7_TECH_DNS_ACCESS.md](../MARCA7_TECH_DNS_ACCESS.md): **DNS proxied → Traefik → origin**, com **Cloudflare Zero Trust Access** (login por e-mail / PIN) na frente dos painéis.

## URLs (após configurar)

| Ferramenta | URL | Access |
|------------|-----|--------|
| Uptime Kuma | https://uptimekuma.chamaeu.app | Sim |
| Dozzle | https://dozzle.chamaeu.app | Sim |
| Portainer | https://portainer.chamaeu.app | Sim |
| Traefik | https://traefik.chamaeu.app | Sim |

**Sem Access** (público): `chamaeu.app`, `api.chamaeu.app`, `adm.chamaeu.app`.

## 1. Cloudflare (API)

Na máquina local, com token que tenha **DNS Edit** + **Access**:

```bash
cd oracle-infra
export CLOUDFLARE_API_TOKEN=...
export ALLOWED_EMAILS=yuri.apcarvalho@gmail.com   # vírgula para vários
node scripts/configure-chamaeu-cloudflare-access.mjs
```

Cria/atualiza registros **A** proxied e applications Access com IdP **Cloudflare** + **One-time PIN**.

SSL da zona: **Full (strict)** (se o token tiver Zone Settings Write).

## 2. VPS Oracle

Em `/opt/infra/compose/*/.env` (não versionar):

```bash
# compose/uptime-kuma/.env
SERVICE_HOST=uptimekuma.chamaeu.app

# compose/dozzle/.env
SERVICE_HOST=dozzle.chamaeu.app

# compose/portainer/.env
SERVICE_HOST=portainer.chamaeu.app

# compose/traefik/.env
SERVICE_HOST=traefik.chamaeu.app
```

Recriar stacks:

```bash
cd /opt/infra
docker compose -f compose/uptime-kuma/compose.yml up -d --force-recreate
docker compose -f compose/dozzle/compose.yml up -d --force-recreate
docker compose -f compose/portainer/compose.yml up -d --force-recreate
docker compose -f compose/traefik/compose.yml up -d --force-recreate
docker restart traefik   # se labels do dashboard não atualizarem
```

Uptime Kuma mantém bind `127.0.0.1:8082` como fallback SSH; tráfego público entra pela rede `proxy` + Traefik.

## 3. Uptime Kuma — monitores ChamaEu

```bash
bash scripts/uptime-kuma-seed-monitors.sh   # infra
# monitores chamaeu: ver services/chamaeu/uptime-kuma-monitors.json (UI ou import)
```

Discord: `compose/uptime-kuma/.env` + `bash scripts/uptime-kuma-seed-discord.sh`.

## Smoke

1. Abrir `https://portainer.chamaeu.app` → tela **Cloudflare Access** → login e-mail.
2. Depois do login, UI Portainer / Kuma / Dozzle.
3. `https://api.chamaeu.app/health` → **sem** Access, 200 JSON.
