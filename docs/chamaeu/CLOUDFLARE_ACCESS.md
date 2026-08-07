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

**Sem Access** (público): `chamaeu.app`, `api.chamaeu.app`, `adm.chamaeu.app`.

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

**Manual (Zero Trust):** [Access → Applications](https://one.dash.cloudflare.com/) → Add application → Self-hosted, um app por domínio abaixo, policy **Allow** → *Include* → *Emails* (ops) + *Require* → *Country* → **Brazil**. IdPs: Cloudflare + One-time PIN (como em [MARCA7_TECH_DNS_ACCESS.md](../MARCA7_TECH_DNS_ACCESS.md)).

| Application | Domain |
|-------------|--------|
| Uptime Kuma (ChamaEu) | `uptimekuma.chamaeu.app` |
| Dozzle (ChamaEu) | `dozzle.chamaeu.app` |
| Portainer (ChamaEu) | `portainer.chamaeu.app` |
| Traefik (ChamaEu) | `traefik.chamaeu.app` |
| Grafana (ChamaEu) | `grafana.chamaeu.app` |

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
2. Depois do login, UI Portainer / Kuma / Dozzle / Grafana (`https://grafana.chamaeu.app`).
3. `https://api.chamaeu.app/health` → **sem** Access, 200 JSON.

## 4. WAF / proteção de requests (borda)

Além do Access, a zona usa Custom WAF Rules (script [`configure-chamaeu-cloudflare-waf.mjs`](../../scripts/configure-chamaeu-cloudflare-waf.mjs)):

| Alvo | País ≠ BR | Exceções |
|------|-----------|----------|
| Painéis (`grafana`, `portainer`, `dozzle`, `uptimekuma`, `traefik`) | **Block** | — |
| Apps públicos (`chamaeu.app`, `api`, `adm`) | **Managed Challenge** | `/pagamento/webhook*`, `/health`, `/api/health` |

Também: Security Level **High**, Browser Integrity Check **On**.

```bash
export CLOUDFLARE_API_TOKEN=...
node scripts/configure-chamaeu-cloudflare-waf.mjs
```

**Nota:** webhooks de pagamento costumam vir de fora do BR — por isso não são bloqueados. Se Mercado Pago falhar, confirme o path do webhook na regra.

## 5. Origin lock — só Cloudflare em 80/443

Na VPS, HTTP/HTTPS ficam restritos aos [CIDRs oficiais Cloudflare](https://www.cloudflare.com/ips/). SSH (22) permanece `LIMIT`.

> Docker publica 80/443 do Traefik e **bypassa o UFW**. O script também aplica a chain `DOCKER-USER` (iptables) e um unit systemd para reaplicar após reboot.

```bash
cd /opt/infra
sudo bash scripts/ufw-cloudflare-only-http.sh
```

Tráfego direto ao IP público da VPS nas portas 80/443 deve falhar; sites/painéis continuam via proxy Cloudflare.
