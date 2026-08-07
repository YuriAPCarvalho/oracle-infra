# Postgres compartilhado

Instância única PostgreSQL para serviços da VPS.

## Layout

| Item | Valor |
|------|--------|
| Compose | `compose/postgres/` |
| Imagem | `postgres:18-alpine` |
| Dados | `/opt/docker/databases/postgres/data` |
| Backups lógicos | `/opt/docker/backups/postgres/` |
| Rede | `internal` (apps) + `postgres-host` (bind localhost) |
| Portas | `127.0.0.1:5432` — túnel SSH |
| Hostname Docker | `postgres` |

Arquitetura de storage: [docs/STORAGE_ARCHITECTURE.md](../../docs/STORAGE_ARCHITECTURE.md).

## Segredos

`compose/postgres/.env.example` → `.env` na VPS (`POSTGRES_PASSWORD`). Nunca commitado.

## Criar DB por aplicação

```bash
cd /opt/infra
bash scripts/postgres-create-db.sh --name appdb --password '...'
```

URL interna:

```text
postgresql://appdb:SENHA@postgres:5432/appdb
```

## Deploy

```bash
bash scripts/storage-prepare-dirs.sh
cd /opt/infra
docker compose -f compose/postgres/compose.yml up -d
```

## Backup independente

```bash
# Dump de um DB
DB_NAME=rankao bash scripts/backup-rankao-db.sh

# Dump all (também roda dentro de make backup)
docker exec postgres pg_dumpall -U postgres | gzip > /opt/docker/backups/postgres/manual.sql.gz
```

Filesystem copy: coberto por `make backup` (live — preferir dump lógico para restore limpo).

## Restore independente

```bash
gunzip -c /opt/docker/backups/postgres/rankao-....sql.gz \
  | docker exec -i postgres psql -U postgres -d rankao
```

## Monitoramento

- `postgres-exporter` → dashboard **Data layer**
- Tamanho no disco: `infra_storage_dir_bytes{path="databases/postgres"}` (textfile)
- Tamanho lógico: métricas `pg_database_size_bytes` do exporter (quando disponível)

## Documentação relacionada

- [BACKUP.md](../../docs/BACKUP.md)
- [RESTORE.md](../../docs/RESTORE.md)
