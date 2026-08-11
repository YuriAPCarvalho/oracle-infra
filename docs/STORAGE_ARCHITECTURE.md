# Arquitetura de armazenamento

Modelo alvo da VPS Oracle Always Free: separar sistema operacional, dados de containers e backups offsite, sem sair dos limites gratuitos.

Detalhes Oracle (limites, Console, custos): [OCI_STORAGE.md](OCI_STORAGE.md).  
Migração Boot → Block Volume: [runbooks/MIGRATE_TO_BLOCK_VOLUME.md](runbooks/MIGRATE_TO_BLOCK_VOLUME.md).  
Backup/restore: [BACKUP.md](BACKUP.md), [RESTORE.md](RESTORE.md).

## Visão geral

| Camada | Onde | Conteúdo |
|--------|------|----------|
| Boot Volume | `/`, `/opt/infra`, `/var/lib/docker` | SO, código versionado, engine Docker, staging opcional de upload |
| Block Volume | `/opt/docker` | Dados persistentes de todos os containers |
| Object Storage R2 | Cloudflare bucket `infra-backups` (ex.) | Camada 3 offsite — free 10 GB; soft cap 8 GiB + keep 3 |

`DATA_ROOT` permanece `/opt/docker` ([`scripts/lib/common.sh`](../scripts/lib/common.sh)) para máxima compatibilidade com CI e scripts.

## Layout canônico (`/opt/docker`)

```text
/opt/docker/
├── databases/
│   ├── postgres/data
│   └── redis/data
├── object-storage/
│   └── minio/
│       ├── data/       # root do MinIO (buckets)
│       ├── config/     # reservado
│       └── certs/      # TLS futuro
├── monitoring/
│   ├── prometheus/data
│   └── grafana/data
├── platform/
│   ├── traefik/{letsencrypt,logs}
│   ├── portainer/data
│   └── uptime-kuma/data
├── applications/
│   ├── gold-api/auth_info
│   ├── waha/sessions
│   └── rankao/         # reservado
├── backups/
│   ├── postgres/
│   ├── minio/
│   ├── redis/
│   ├── grafana/
│   ├── prometheus/
│   ├── applications/
│   └── full/           # tar operacional (Camada 1)
├── logs/
├── screenshots/
├── uploads/
└── deploy-state/
```

**Por que `platform/` separado de `applications/`:** Traefik, Portainer e Uptime Kuma são edge/ops; apps de negócio (ScriptGold, ChamaEu/WAHA) ficam em `applications/`. Facilita restore seletivo e ownership.

**Regra dura:** buckets MinIO nunca compartilham árvore com `databases/`.

Criar a árvore:

```bash
bash scripts/storage-prepare-dirs.sh
```

Lista canônica: [`scripts/lib/storage-layout.sh`](../scripts/lib/storage-layout.sh).

## Fluxo de backup (resumo)

1. **Camada 1 (local):** `make backup` → dumps lógicos + tar em `/opt/docker/backups/`.
2. **Camada 2 (OCI Volume Backup):** snapshots manuais/policy do Boot e/ou Block (máx. 5 Always Free).
3. **Camada 3 (Cloudflare R2):** hook `post-backup-r2` → [`scripts/backup/r2-upload.sh`](../scripts/backup/r2-upload.sh); keep 3 + soft cap 8 GiB (free 10 GB).

## Fluxo de restore (resumo)

1. Preferir restore seletivo (dump Postgres, dados Grafana, etc.).
2. Tar full → `scripts/restore.sh` (confirmação `RESTORE`).
3. Desastre de disco → restaurar Volume Backup OCI e remontar `/opt/docker` (runbook).

## Estratégia de crescimento

Dentro dos **200 GB** Boot+Block Always Free:

1. Prune de `backups/full/` (retenção) e TSDB Prometheus.
2. Reduzir boot (~50 GB) e expandir Block Volume (fase opcional, risco alto).
3. Offload de dumps/archives críticos para R2 (≤10 GB free; script com soft cap 8 GiB).
4. Upgrade pago consciente se media MinIO explodir.

## Segurança

| Path | Ownership típico |
|------|------------------|
| `monitoring/prometheus/data` | UID/GID `65534` |
| `monitoring/grafana/data` | UID/GID `472` |
| `databases/postgres/data` | UID imagem Postgres |
| Demais dirs ops | `ubuntu:ubuntu` (0750) |
| Arquivos de backup | mode `600` |

Riscos: UID mismatch após migração; backup live inconsistente; Camada 1 no mesmo Block Volume que os dados (por isso Camadas 2 e 3 existem).

## Monitoramento

- Node Exporter: uso de `/` e `/opt/docker`.
- Textfile: tamanhos de backups/DBs/MinIO (`scripts/metrics/storage-textfile.sh`).
- MinIO + Postgres exporters já existentes.
- Object Storage offsite: Cloudflare R2 Dashboard (usage) — ver [BACKUP.md](BACKUP.md) Camada 3. OCI Object Storage permanece opção documentada em [OCI_STORAGE.md](OCI_STORAGE.md).

Alertas Discord via Grafana: [GRAFANA_ALERTING.md](GRAFANA_ALERTING.md).

## Compatibilidade

Nada neste modelo altera Traefik/Portainer/Dozzle/Kuma/Prometheus/Grafana/CI por si só. O que quebra é **aplicar Compose novos paths na VPS sem migrar dados**. Sempre seguir o runbook de migração antes do deploy dos novos binds.
