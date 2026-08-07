# Restore

Restore operacional: `scripts/restore.sh`. Preferir restore seletivo (dump lógico) quando possível.

Ver também: [BACKUP.md](BACKUP.md), [STORAGE_ARCHITECTURE.md](STORAGE_ARCHITECTURE.md), [runbooks/MIGRATE_TO_BLOCK_VOLUME.md](runbooks/MIGRATE_TO_BLOCK_VOLUME.md).

## Dry-run

```bash
bash scripts/restore.sh -n /opt/docker/backups/full/backup-YYYYMMDD-HHMMSS.tar.gz
```

Valida checksum/arquivo, lista destinos (inclui árvore `$DATA_ROOT`, tipicamente `/opt/docker`) e **não** copia nada.

## Confirmação

Restore real exige digitar exatamente:

```text
RESTORE
```

## Comportamento

- Nunca restaura em silêncio.
- Sobrescreve `compose/`, `configs/`, `bootstrap/`, `scripts/`, `docs/` no `$PROJECT_ROOT`.
- Restaura dados persistentes em `$DATA_ROOT` (`DATA_ROOT` env; default `/opt/docker`).
- Archives legados com prefixo `opt/docker/` são aceitos e gravados em `$DATA_ROOT`.
- Pode exigir `sudo` para `/opt/docker`.

## Fluxo recomendado (tar full)

```bash
cd /opt/infra
# Preferir stacks paradas antes de sobrescrever dados
bash scripts/restore.sh /opt/docker/backups/full/backup-YYYYMMDD-HHMMSS.tar.gz
bash scripts/storage-prepare-dirs.sh
make health
docker ps
```

## Restore seletivo — Postgres

```bash
# A partir de dump lógico
gunzip -c /opt/docker/backups/postgres/postgres-all-YYYYMMDD-HHMMSS.sql.gz \
  | docker exec -i postgres psql -U postgres
```

Ou dump de um DB:

```bash
gunzip -c /opt/docker/backups/postgres/rankao-....sql.gz \
  | docker exec -i postgres psql -U postgres -d rankao
```

## Restore seletivo — MinIO / apps

- Parar container → substituir árvore sob `object-storage/minio/data` ou `applications/...` → subir → validar.
- Nunca restaurar buckets por cima de `databases/`.

## Disaster recovery — Volume Backup OCI (Camada 2)

1. Create Block Volume from backup (Console).
2. Attach + mount (ver [OCI_STORAGE.md](OCI_STORAGE.md)).
3. Apontar `/opt/docker` (fstab) para o volume restaurado.
4. `make health`.

## Pós-restore

- [ ] Ownership Prometheus `65534` / Grafana `472`
- [ ] `make health`
- [ ] Traefik ACME, Portainer, Kuma, sessões WAHA/gold-api
- [ ] Novo `make backup` de verificação
