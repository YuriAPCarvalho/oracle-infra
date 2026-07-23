# marca7.tech — DNS + Cloudflare Access

Zona Cloudflare `marca7.tech` (conta `20f799331aa75509ff16ec3b68aa2064`) → VPS Hostinger `179.197.238.11`.

## DNS

Registros **A**, conteúdo `179.197.238.11`, **Proxied** (laranja):

| Nome | Uso |
|------|-----|
| `gestoragro` | APP Gestor Agro |
| `gestoragro-api` | API Gestor Agro (Universal SSL; evita `api.gestoragro.*`) |
| `s3` | MinIO S3 API |
| `minio` | MinIO Console |
| `uptimekuma` | Uptime Kuma |
| `dozzle` | Dozzle |
| `portainer` | Portainer |
| `traefik` | Traefik dashboard |

**SSL/TLS** da zona: **Full (strict)**.

## Cloudflare Access (Zero Trust)

Team domain: `marca7.cloudflareaccess.com`

IdPs: **Cloudflare** (membros da conta) + **One-time PIN**.

Applications self-hosted (session 24h), policy Allow para:

- `yuri.apcarvalho@gmail.com`
- `monica@marca7.com.br`

| Application | Domain |
|-------------|--------|
| MinIO Console | `minio.marca7.tech` |
| Uptime Kuma | `uptimekuma.marca7.tech` |
| Dozzle | `dozzle.marca7.tech` |
| Portainer | `portainer.marca7.tech` |
| Traefik | `traefik.marca7.tech` |

**Sem Access** (públicos, auth própria):

- `gestoragro.marca7.tech`
- `gestoragro-api.marca7.tech`
- `s3.marca7.tech`

**SSL/TLS:** preferir **Full (strict)** no dashboard (API token atual sem Zone Settings Write). Origin com Let's Encrypt via Traefik.

## Traefik na VPS

Compose em `/opt/infra/compose/*` com labels Host + Let's Encrypt. Painéis mantêm bind `127.0.0.1` para fallback SSH.

Após DNS + Access:

```bash
cd /opt/infra
# atualizar .env dos stacks (SERVICE_HOST / URLs)
docker compose -f compose/traefik/compose.yml up -d
docker compose -f compose/uptime-kuma/compose.yml up -d
docker compose -f compose/dozzle/compose.yml up -d
docker compose -f compose/portainer/compose.yml up -d
docker compose -f compose/minio/compose.yml up -d
docker compose -f compose/marca7-api/compose.yml up -d
docker compose -f compose/marca7-app/compose.yml up -d
```

Smoke:

- `https://gestoragro-api.marca7.tech/health` — 200 sem login Access
- `https://gestoragro.marca7.tech/` — app sem Access
- `https://portainer.marca7.tech/` (e demais painéis) — challenge Access Cloudflare
