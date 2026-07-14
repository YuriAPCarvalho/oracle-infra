# Postgres compartilhado

Instância única PostgreSQL 16 para todos os serviços da VPS.

## Layout

| Item | Valor |
|------|--------|
| Compose | `compose/postgres/` |
| Imagem | `postgres:18-alpine` (alinha com dumps Railway atuais) |
| Dados | `/opt/docker/postgres/data` |
| Rede | `internal` + bind `127.0.0.1:5432` (só localhost) |
| Portas publicadas | `127.0.0.1:5432` — acesso via **túnel SSH**, nunca na internet |
| Traefik | não |
| Hostname Docker | `postgres` |

## Segredos

Copiar `compose/postgres/.env.example` → `/opt/infra/compose/postgres/.env` na VPS (`POSTGRES_PASSWORD` forte). Nunca commitado.

## Criar DB por aplicação

```bash
cd /opt/infra
bash scripts/postgres-create-db.sh --name dailybot --password '...'
```

URL interna tipica:

```text
postgresql://dailybot:SENHA@postgres:5432/dailybot
```

O serviço consumidor deve estar na rede `internal` (além da bridge de egress, se precisar).

## Deploy

```bash
sudo mkdir -p /opt/docker/postgres/data
cd /opt/infra
docker compose -f compose/postgres/compose.yml up -d
docker compose -f compose/postgres/compose.yml ps
```

## Backup

Coberto pelo backup de `/opt/docker` (`make backup`). Dump lógico pontual:

```bash
docker exec postgres pg_dump -U postgres -Fc dailybot > dailybot.dump
```
