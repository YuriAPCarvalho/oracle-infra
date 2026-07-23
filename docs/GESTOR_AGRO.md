# Gestor Agro (produção — Hostinger)

API Nest + APP Next + Postgres compartilhado + MinIO na VPS `179.197.238.11`.

Produto: **Gestor Agro** (org [Marca7-Tech](https://github.com/Marca7-Tech)).

## Domínios (`marca7.tech`)

| Serviço | Host | Cloudflare Access |
|---------|------|-------------------|
| APP | `gestoragro.marca7.tech` | Não |
| API | `gestoragro-api.marca7.tech` | Não |
| MinIO S3 | `s3.marca7.tech` | Não |
| MinIO Console | `minio.marca7.tech` | Sim |

> **Nota SSL:** Cloudflare Universal SSL cobre `*.marca7.tech`, mas **não** hostnames com dois níveis (`api.gestoragro.marca7.tech`). Por isso a API usa `gestoragro-api.marca7.tech`. Para usar o hostname aninhado, habilite Total TLS / Advanced Certificate na zona.

DNS (Cloudflare): registros A proxied → `179.197.238.11`. SSL/TLS **Full (strict)**. HTTPS via Traefik ACME (Let's Encrypt HTTP-01).

Ver também [MARCA7_TECH_DNS_ACCESS.md](MARCA7_TECH_DNS_ACCESS.md).

## Compose

| Path | Função |
|------|--------|
| `compose/postgres/` | DB compartilhado |
| `compose/minio/` | Object storage (S3 + console) |
| `compose/marca7-api/` | Nest API (Gestor Agro) |
| `compose/marca7-app/` | Next APP (Gestor Agro) |

## Bootstrap VPS

```bash
cd /opt/infra
# Postgres
cp compose/postgres/.env.example compose/postgres/.env   # editar senha
docker compose -f compose/postgres/compose.yml up -d
bash scripts/postgres-create-db.sh --name marca7 --password '<secret>'

# MinIO
cp compose/minio/.env.example compose/minio/.env         # editar root password
docker compose -f compose/minio/compose.yml up -d
bash scripts/minio-create-bucket.sh --bucket marca7-estoque

# API env
cp compose/marca7-api/.env.example compose/marca7-api/.env
# DATABASE_URL=postgresql://marca7:<secret>@postgres:5432/marca7
# MINIO_ACCESS_KEY / MINIO_SECRET_KEY = mesmos do MinIO root (ou user dedicado)
# FRONTEND_URL=https://gestoragro.marca7.tech
# MINIO_PUBLIC_URL=https://s3.marca7.tech
chmod 600 compose/marca7-api/.env compose/minio/.env compose/postgres/.env

# Imagens: via GitHub Actions (push main) ou pull manual GHCR
```

Seed de cadastro (admin, catálogos, produtos, fazendas) roda no entrypoint da API (`prisma migrate deploy` + `db seed`). **Não** popula entrada/saída/inventário/nota/remessa.

Admin seed: CPF `00000000000` / senha `admin123` — **trocar após o primeiro login**.

## CI/CD

Repos `Marca7-Tech/marca7-gestor-agro-api` e `marca7-gestor-agro-app`: workflow `build-and-deploy.yml` em push `main` (linux/amd64, GHCR, deploy SSH via `oracle-infra@v1`).

Secrets: ver [GITHUB_SECRETS.md](GITHUB_SECRETS.md).

### GHCR (pull na VPS)

Pacotes em `ghcr.io/marca7-tech/*`. O deploy SSH faz `docker login` efêmero com `GITHUB_TOKEN` (`packages: read`) antes do pull e `docker logout` depois. Com repos públicos, packages costumam ficar puxáveis sem login manual.

## Monitoramento

```bash
bash scripts/uptime-kuma-seed-monitors.sh   # inclui marca7-api / marca7-app (containers Gestor Agro)
```

Monitores HTTP públicos: `https://gestoragro-api.marca7.tech/health` e `https://gestoragro.marca7.tech/` (após DNS). Até lá, health local: `http://127.0.0.1:4000/health` e `http://127.0.0.1:3000/`.
