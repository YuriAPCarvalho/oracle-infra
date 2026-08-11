# Backup

Backup operacional em camadas. Scripts: `scripts/backup.sh`, dumps lógicos, hooks.

Arquitetura: [STORAGE_ARCHITECTURE.md](STORAGE_ARCHITECTURE.md) · Oracle: [OCI_STORAGE.md](OCI_STORAGE.md).

## Camadas

| Camada | Mecanismo | Vantagem | Limitação |
|--------|-----------|----------|-----------|
| **1 Local** | `backup.sh` → `/opt/docker/backups/` | Rápido, restore granular | Mesmo disco/volume dos dados |
| **2 Volume Backup OCI** | Snapshot Boot/Block (máx. 5 Always Free) | Sobrevive wipe do FS | Poucos pontos; restore de volume inteiro |
| **3 Cloudflare R2** | Hook `post-backup-r2` → bucket dedicado | Offsite (sobrevive à VM) | Free: **10 GB** storage; soft cap 8 GiB + keep 3 no script |

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

## Hooks (Camada 3 — Cloudflare R2)

Upload automático do `.tar.gz` + `.sha256` + `.meta.json` após sucesso do Layer-1.

Guardrails free-tier (não pagar overage):

| Controle | Default | Efeito |
|----------|---------|--------|
| `R2_KEEP_LAST` | `3` | Mantém só 3 conjuntos remotos (~150 MB com tars ~50 MB) |
| `R2_SOFT_MAX_BYTES` | `8589934592` (8 GiB) | Se o uso projetado passar, **pula** o upload (backup local segue OK) |
| Frequência | cron diário | ~1 list + 3 puts + poucos deletes/dia ≪ 1M Class A |

Ativar na VPS:

```bash
cp compose/backup-r2/.env.example compose/backup-r2/.env
# Preencher R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET
# Token: Cloudflare Dashboard → R2 → Manage R2 API Tokens → Object Read & Write (só este bucket)
# Ativar alerta de billing/budget no Dashboard (mesmo com $0 esperado)

sudo apt-get install -y awscli   # ou awscli v2; requer `aws` + `python3`
cp scripts/backup/hooks/post-backup-r2.sh.example scripts/backup/hooks/post-backup-r2.sh
chmod +x scripts/backup/hooks/post-backup-r2.sh
make backup   # deve logar "R2 upload complete"
# Emite marcadores .last-r2-success + .r2-usage; storage-textfile publica métricas R2.
# Alertas Discord: R2BackupStale / R2BucketNearSoftCap — ver GRAFANA_ALERTING.md
```

Script: [`scripts/backup/r2-upload.sh`](../scripts/backup/r2-upload.sh). Env: [`compose/backup-r2/.env.example`](../compose/backup-r2/.env.example).

Stub OCI antigo: [`scripts/backup/hooks/post-backup.sh.example`](../scripts/backup/hooks/post-backup.sh.example) (não usar junto com R2 no mesmo fluxo).

## Cron (janela 01:00–05:00)

Agendar **manualmente** na VPS a partir de [`scripts/backup/cron.example`](../scripts/backup/cron.example). Não instalar via CI.

Horário alvo: **02:15 America/Sao_Paulo** (meio da janela de menor uso). Use `CRON_TZ` mesmo se o SO estiver em outro fuso (ex.: `America/Campo_Grande`). Defina `PATH` — o cron não herda o PATH do login, e sem `USER` o `backup.sh` antigo abortava (`set -u`).

```cron
CRON_TZ=America/Sao_Paulo
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
15 2 * * * cd /opt/infra && /usr/bin/env bash scripts/backup.sh >>/opt/docker/logs/backup-cron.log 2>&1
*/5 * * * * cd /opt/infra && /usr/bin/env bash scripts/metrics/storage-textfile.sh
```

O hook R2 roda no mesmo job após o Layer-1. Conferir `/opt/docker/logs/backup-cron.log` na manhã seguinte (`Backup created` / `R2 upload complete`).

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
