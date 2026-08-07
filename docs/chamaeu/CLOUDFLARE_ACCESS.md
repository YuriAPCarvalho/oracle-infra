# chamaeu.app — painéis + Cloudflare Access

Padrão igual [MARCA7_TECH_DNS_ACCESS.md](../MARCA7_TECH_DNS_ACCESS.md): **DNS proxied → Traefik → origin**, com **Cloudflare Zero Trust Access** (login por e-mail / PIN) na frente dos painéis.

## URLs (após configurar)

| Ferramenta | URL | Access |
|------------|-----|--------|
| Uptime Kuma | https://uptimekuma.chamaeu.app | Sim |
| Dozzle | https://dozzle.chamaeu.app | Sim |
| Portainer | https://portainer.chamaeu.app | Sim |
| Traefik | https://traefik.chamaeu.app | Sim |
| Grafana | https://grafana.chamaeu.app | Sim |
| MinIO Console | https://minio.chamaeu.app | Sim |

**Sem Access** (público / auth própria): `chamaeu.app`, `api.chamaeu.app`, `adm.chamaeu.app`, `s3.chamaeu.app` (MinIO S3 API).

## 1. Cloudflare (API)

Na máquina local, com token que tenha **DNS Edit** + **Access**:

```bash
cd oracle-infra
export CLOUDFLARE_API_TOKEN=...
export ALLOWED_EMAILS=yuri.apcarvalho@gmail.com   # vírgula para vários
node scripts/configure-chamaeu-cloudflare-access.mjs
```

**Pré-requisito:** na conta onde está a zona `chamaeu.app`, abra [Zero Trust](https://one.dash.cloudflare.com/) e clique **Enable Access** (ou crie o time). Sem isso a API retorna `access.api.error.not_enabled`.

**Token:** em [API Tokens](https://dash.cloudflare.com/profile/api-tokens), use o template **Edit Cloudflare Zero Trust** (ou custom com *Account → Access: Apps and Policies → Edit* e *Zone → DNS → Edit* na zona `chamaeu.app`). O token só de DNS (ex.: cutover) falha em `GET .../access/identity_providers` com *Authentication error* — DNS pode ter sido aplicado mesmo assim; Access precisa de um segundo token ou do dashboard.

**Manual (Zero Trust):** [Access → Applications](https://one.dash.cloudflare.com/) → Add application → Self-hosted, um app por domínio abaixo, policy **Allow** → *Include* → *Emails* (ops). IdPs: Cloudflare + One-time PIN (como em [MARCA7_TECH_DNS_ACCESS.md](../MARCA7_TECH_DNS_ACCESS.md)).

| Application | Domain |
|-------------|--------|
| Uptime Kuma (ChamaEu) | `uptimekuma.chamaeu.app` |
| Dozzle (ChamaEu) | `dozzle.chamaeu.app` |
| Portainer (ChamaEu) | `portainer.chamaeu.app` |
| Traefik (ChamaEu) | `traefik.chamaeu.app` |
| Grafana (ChamaEu) | `grafana.chamaeu.app` |
| MinIO Console (ChamaEu) | `minio.chamaeu.app` |

DNS A proxied também: `s3.chamaeu.app` (**sem** Access).

Cria/atualiza registros **A** proxied e applications Access com IdP **Cloudflare** + **One-time PIN** (quando o token tiver permissão).

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

# compose/grafana/.env (manter admin user/password; só acrescentar host)
SERVICE_HOST=grafana.chamaeu.app

# compose/minio/.env (manter MINIO_ROOT_*; só hosts/URLs)
SERVICE_HOST=s3.chamaeu.app
CONSOLE_HOST=minio.chamaeu.app
MINIO_SERVER_URL=https://s3.chamaeu.app
MINIO_BROWSER_REDIRECT_URL=https://minio.chamaeu.app
```

Recriar stacks:

```bash
cd /opt/infra
bash scripts/apply-chamaeu-panel-hosts.sh
# ou manualmente:
docker compose -f compose/uptime-kuma/compose.yml up -d --force-recreate
docker compose -f compose/dozzle/compose.yml up -d --force-recreate
docker compose -f compose/portainer/compose.yml up -d --force-recreate
docker compose -f compose/traefik/compose.yml up -d --force-recreate
docker compose -f compose/grafana/compose.yml up -d --force-recreate
docker compose -f compose/minio/compose.yml up -d --force-recreate
docker restart traefik   # se labels do dashboard não atualizarem
```

Uptime Kuma e Grafana mantêm bind `127.0.0.1` como fallback SSH; tráfego público entra pela rede `proxy` + Traefik (+ Cloudflare Access).

## 3. Uptime Kuma — monitores ChamaEu

```bash
bash scripts/uptime-kuma-seed-monitors.sh   # infra + ScriptGold + ChamaEu
# ou só ChamaEu:
bash scripts/uptime-kuma-seed-chamaeu-monitors.sh
```

Catálogo completo: [docs/chamaeu/MONITORING.md](../docs/chamaeu/MONITORING.md). Import de referência: [`services/chamaeu/uptime-kuma-monitors.json`](../../services/chamaeu/uptime-kuma-monitors.json).

Discord: `compose/uptime-kuma/.env` + `bash scripts/uptime-kuma-seed-discord.sh`.

## Smoke

1. Abrir `https://portainer.chamaeu.app` → tela **Cloudflare Access** → login e-mail.
2. Depois do login, UI Portainer / Kuma / Dozzle / Grafana / MinIO Console (`https://minio.chamaeu.app`).
3. `https://api.chamaeu.app/health` → **sem** Access, 200 JSON.
4. `https://s3.chamaeu.app/minio/health/live` → **sem** Access, 200 (S3 API).

## 4. WAF / geo BR (opcional — **não aplicado**)

ScriptGold e providers externos precisam de tráfego de fora do BR. Por isso **não** mantemos WAF geo nem `require` país nas policies Access.

O script [`configure-chamaeu-cloudflare-waf.mjs`](../../scripts/configure-chamaeu-cloudflare-waf.mjs) existe se no futuro quiser challenge/block fora do BR nos painéis — **não rode** enquanto ScriptGold depender de IPs internacionais.

Estado atual da zona: Access por e-mail apenas; `security_level=medium`; SSL **Full (strict)**.

## 5. Origin lock Cloudflare-only (opcional — **não aplicado**)

HTTP/HTTPS na VPS estão **Anywhere** (80/443) + SSH `LIMIT`, para não quebrar fluxos que batem no origin ou renovação ACME.

O script [`ufw-cloudflare-only-http.sh`](../../scripts/ufw-cloudflare-only-http.sh) (UFW + `DOCKER-USER`) fica disponível, mas **não** está ativo.

### ACME + Access (Grafana e painéis novos)

Com DNS **proxied** + Access, o HTTP-01 do Let's Encrypt pode falhar (challenge redireciona para login). Para o **primeiro** certificado: DNS A em **DNS only** → recreate Grafana/Traefik → voltar **Proxied**. Renovações futuras dos hosts que já têm cert no `acme.json` costumam seguir sem isso.
