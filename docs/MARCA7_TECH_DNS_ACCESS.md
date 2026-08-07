# marca7.tech — DNS + Cloudflare Access

Zona Cloudflare `marca7.tech` (conta `20f799331aa75509ff16ec3b68aa2064`).

Gestor Agro (marca7-app / marca7-api) **não** faz parte desta VPS Oracle nem deste repositório; roda em outra VPS.

## DNS (painéis / MinIO)

Registros **A**, **Proxied** (laranja), apontando para a origem apropriada:

| Nome | Uso |
|------|-----|
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

**Sem Access** (auth própria do serviço):

- `s3.marca7.tech`

## Traefik na VPS Oracle

Compose em `/opt/infra/compose/*` com labels Host + Let's Encrypt. Painéis mantêm bind `127.0.0.1` para fallback SSH.

Após DNS + Access:

```bash
cd /opt/infra
docker compose -f compose/traefik/compose.yml up -d
docker compose -f compose/uptime-kuma/compose.yml up -d
docker compose -f compose/dozzle/compose.yml up -d
docker compose -f compose/portainer/compose.yml up -d
docker compose -f compose/minio/compose.yml up -d
```

Smoke:

- `https://portainer.marca7.tech/` (e demais painéis) — challenge Access Cloudflare
- Grafana **não** usa Traefik; acesso só por túnel SSH — ver [GRAFANA.md](GRAFANA.md)
