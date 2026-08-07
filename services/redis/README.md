# Redis compartilhado

Instância Redis 7 (AOF) para filas/cache (ex.: ChamaEu / BullMQ).

## Layout

| Item | Valor |
|------|--------|
| Compose | `compose/redis/` |
| Imagem | `redis:7-alpine` |
| Dados | `/opt/docker/databases/redis/data` |
| Backups | `/opt/docker/backups/redis/` |
| Rede | `internal` |
| Hostname Docker | `redis` |

Nunca colocar dados Redis sob `object-storage/` ou misturar com MinIO.

## Deploy

```bash
bash scripts/storage-prepare-dirs.sh
docker compose -f compose/redis/compose.yml up -d
```

## Backup independente

Com AOF habilitado, cópia quieta:

```bash
docker exec redis redis-cli BGSAVE
# após save, copiar dump/AOF
sudo cp -a /opt/docker/databases/redis/data/. /opt/docker/backups/redis/redis-$(date +%Y%m%d-%H%M%S)/
```

Também entra no tar de `make backup` (live).

## Restore independente

1. `docker compose -f compose/redis/compose.yml stop`
2. Restaurar arquivos em `/opt/docker/databases/redis/data`
3. `docker compose -f compose/redis/compose.yml up -d`

## Monitoramento

- `redis-exporter` → dashboard **Data layer**
- Disco: `infra_storage_dir_bytes{path="databases/redis"}`

Fila é frequentemente efêmera — priorize Postgres/MinIO no disaster recovery.
