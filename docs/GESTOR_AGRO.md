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
| `compose/watchtower/` | Pull automático de imagens com label Watchtower |

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
# SERVICE_IMAGE=ghcr.io/marca7-tech/marca7-gestor-agro-api:latest
chmod 600 compose/marca7-api/.env compose/minio/.env compose/postgres/.env

# APP env
cp compose/marca7-app/.env.example compose/marca7-app/.env
# SERVICE_IMAGE=ghcr.io/marca7-tech/marca7-gestor-agro-app:latest

# Imagens: GitHub Actions publica no GHCR; Watchtower puxa :latest na VPS
```

Seed de cadastro (admin, catálogos, produtos, fazendas) roda no entrypoint da API (`prisma migrate deploy` + `db seed`). **Não** popula entrada/saída/inventário/nota/remessa.

Admin seed: variáveis `ADMIN_LOCAL_*` no `.env` da API (ver `.env.example`).

## CI/CD (pull-based)

Repos `Marca7-Tech/marca7-gestor-agro-api` e `marca7-gestor-agro-app`: workflow **Build and publish** em push `main` (linux/amd64 → GHCR com tags `latest` + `sha-*`).

**Não há deploy SSH** a partir do GitHub Actions. A VPS atualiza sozinha:

1. CI publica `ghcr.io/marca7-tech/marca7-gestor-agro-{app|api}:latest`
2. Watchtower (poll ~60s) detecta digest novo nos containers com label `com.centurylinklabs.watchtower.enable=true`
3. Recreate de `marca7-app` / `marca7-api`

### GHCR (pull na VPS)

Pacotes `ghcr.io/marca7-tech/marca7-gestor-agro-{app|api}` estão **públicos** — pull e Watchtower funcionam sem `docker login`.

Se no futuro voltarem a ser privados, faça login persistente na VPS:

```bash
echo '<PAT read:packages>' | docker login ghcr.io -u <github-user> --password-stdin
```

### One-time: ativar Watchtower na VPS

Se a VPS ainda rodava `sha-*` / `:local` via deploy antigo, faça uma vez:

```bash
cd /opt/infra
git pull --ff-only

# Login GHCR só se os packages forem privados
# echo '<PAT>' | docker login ghcr.io -u <github-user> --password-stdin

# Ou use o script (força SERVICE_IMAGE=:latest e sobe Watchtower)
bash scripts/enable-marca7-watchtower.sh

docker logs -f watchtower   # deve listar só containers com a label
```

### Rollback manual

```bash
# Ex.: voltar APP para um sha conhecido (ainda publicado no GHCR)
# editar compose/marca7-app/.env:
# SERVICE_IMAGE=ghcr.io/marca7-tech/marca7-gestor-agro-app:sha-<full>
docker compose -f compose/marca7-app/compose.yml up -d
# Depois restaure :latest no .env para o Watchtower voltar a atualizar
```

## Monitoramento

```bash
bash scripts/uptime-kuma-seed-monitors.sh   # inclui marca7-api / marca7-app (containers Gestor Agro)
```

Monitores HTTP públicos: `https://gestoragro-api.marca7.tech/health` e `https://gestoragro.marca7.tech/` (após DNS). Até lá, health local: `http://127.0.0.1:4000/health` e `http://127.0.0.1:3000/`.
