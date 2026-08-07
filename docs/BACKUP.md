# Backup

Backup operacional em camadas. Scripts: `scripts/backup.sh`, dumps lógicos, hooks.

Arquitetura: [STORAGE_ARCHITECTURE.md](STORAGE_ARCHITECTURE.md) · Oracle: [OCI_STORAGE.md](OCI_STORAGE.md).

## Camadas

| Camada | Mecanismo | Vantagem | Limitação |
|--------|-----------|----------|-----------|
| **1 Local** | `backup.sh` → `/opt/docker/backups/` | Rápido, restore granular | Mesmo disco/volume dos dados |
| **2 Volume Backup OCI** | Snapshot Boot/Block (máx. 5 Always Free) | Sobrevive wipe do FS | Poucos pontos; restore de volume inteiro |
| **3 Object Storage** | Upload futuro (hook stub) | Offsite (sobrevive à VM) | 20 GiB Always Free; **não implementado** |

## Conteúdo (Camada 1)

Incluído no tar:

- `compose/`, `configs/`, `bootstrap/`, `scripts/`, `docs/`
- Árvore `$DATA_ROOT` (`/opt/docker`), **exceto**:
  - `backups/full/` (evita backup-dentro-de-backup)
  - `monitoring/prometheus/` por padrão (TSDB rebuildable; use `BACKUP_INCLUDE_PROMETHEUS=1` para incluir)

Dump lógico adicional (quando o container `postgres` está up):

- `/opt/docker/backups/postgres/postgres-all-<ts>.sql.gz`

Artefatos por execução:

```text
/opt/docker/backups/full/backup-YYYYMMDD-HHMMSS.tar.gz
/opt/docker/backups/full/backup-YYYYMMDD-HHMMSS.tar.gz.sha256
/opt/docker/backups/full/backup-YYYYMMDD-HHMMSS.meta.json
/opt/docker/backups/full/.last-success
```

Fallback se `/opt/docker/backups/full` não existir/escrevível: `PROJECT_ROOT/backups/` (legado).

## O que NÃO deve entrar / cuidados

| Item | Motivo |
|------|--------|
| Image layers Docker / named volumes | Não usamos named volumes; layers em `/var/lib/docker` |
| Secrets no Git | Nunca; `.env` na VPS entram no tar de `compose/` — trate o arquivo de backup como secreto |
| Logs voláteis | Preferir exclusão futura; Traefik logs podem mudar durante o tar (exit 1 tolerado) |
| Prometheus TSDB como crítico | Inconsistente sob live backup; rebuildable |
| Arquivos em `backups/full` | Excluídos do tar |

## O que usar Volume Backup OCI (Camada 2)

- Estado “quiet” do Block Volume após janela com Postgres/MinIO parados ou low-write
- Disaster recovery do filesystem `/opt/docker` inteiro
- Boot Volume ocasional (SO + `/opt/infra`) — não exceder 5 backups totais

## O que preferir backup lógico

- Postgres (`pg_dump` / `pg_dumpall`) — restore independente e consistente
- Inventário MinIO / `mc mirror` (preparar; não automatizado ainda)
- Dump pontual de um DB: `bash scripts/backup-rankao-db.sh` (`DB_NAME=...`)

## Executar

```bash
cd /opt/infra
make backup
```

Variáveis úteis:

| Variável | Default | Efeito |
|----------|---------|--------|
| `BACKUP_RETENTION_DAYS` | `7` | Remove archives com mtime > N dias (respeitando keep) |
| `BACKUP_KEEP_LAST` | `5` | Mantém pelo menos N archives full |
| `BACKUP_SKIP_PG_DUMP` | `0` | `1` = não roda `pg_dumpall` |
| `BACKUP_INCLUDE_PROMETHEUS` | `0` | `1` = inclui TSDB no tar |
| `BACKUP_DIR` | auto | Override do diretório de saída |
| `DATA_ROOT` | `/opt/docker` | Raiz persistente |

## Hooks (Camada 3 futura)

```bash
cp scripts/backup/hooks/post-backup.sh.example scripts/backup/hooks/post-backup-oci.sh
chmod +x scripts/backup/hooks/post-backup-oci.sh
# Implementar upload; scripts executáveis em hooks/*.sh rodam após sucesso
```

Cron de exemplo: [`scripts/backup/cron.example`](../scripts/backup/cron.example).

## Permissões

Arquivos finais mode `600`. Não versionar backups (`backups/` no `.gitignore`; dados sob `/opt/docker` fora do git).

Validar:

```bash
BACKUP_FILE="$(ls -t /opt/docker/backups/full/backup-*.tar.gz | head -1)"
tar -tzf "${BACKUP_FILE}" >/dev/null
sha256sum -c "${BACKUP_FILE}.sha256"
```

## Consistência

Com containers ativos o script avisa e continua. Para consistência forte: janela de manutenção, `docker compose stop` nos escritores, depois `make backup` e/ou Volume Backup OCI.
