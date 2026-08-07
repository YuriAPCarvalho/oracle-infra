# Oracle Cloud — armazenamento Always Free

Referência operacional. **Não executar** alterações na Console a partir deste repositório; apply só após runbook manual na VPS.

Fontes: [Always Free Resources](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) (validado 2026).

## Limites gratuitos (home region)

| Recurso | Limite Always Free | Notas |
|---------|-------------------|--------|
| Boot + Block Volume | **200 GB combinados** | Volume fora da home region = **pago** |
| Volume Backups | **5 no total** (boot + block) | 6º → falha ou recurso pago |
| Object Storage | **20 GB** (Standard + Infrequent Access + Archive) | Conta Always Free-only: 20 GB combinados |
| Object Storage API | 50.000 req/mês | |
| Vault secrets | 150 | |
| Master keys (software) | Ilimitado (software) | Preferir software |
| HSM key versions | 20 | |
| Ampere A1 | 2 OCPU / 12 GB RAM | |
| Egress | 10 TB/mês | |

Boot mínimo por instância: ~47–50 GB. Default típico ~50 GB; esta VPS usa ~**97 GiB** de boot → restam ~**100–103 GiB** para um Block Volume adicional **sem pagar**.

## O que deixa de ser gratuito (não usar / documentar custo)

| Item | Situação |
|------|----------|
| Block/Boot **> 200 GB** total | Cobrado |
| Volume em **região ≠ home** | Cobrado |
| **> 5** Volume Backups | Falha ou pago |
| Object Storage **> 20 GB** (Always Free-only) | Bloqueio; em trial expirado com excesso, objetos podem ser **apagados** |
| **Virtual Private Vault** | **Não incluso** no Always Free — **pago** |
| HSM keys além de 20 versões | Cobrado |
| Misturar Always Free + paid sem quotas | Oracle não recomenda; risco de surpresa de fatura |

## Arquitetura alvo nesta tenancy

```text
Boot Volume (~97 GiB)
├── SO Ubuntu
├── /var/lib/docker
├── /opt/infra
└── /opt/infra/backups/staging   # opcional, staging Camada 3

Block Volume (~100 GiB)  →  montado em /opt/docker
└── databases, minio, monitoring, platform, apps, backups locais

Object Storage (≤20 GiB)
└── dumps + manifests offsite (Camada 3; upload futuro)
```

Fase opcional futura: reduzir boot para ~50 GB e expandir Block para ~150 GB (migração arriscada; ver runbook).

## Block Volume — criar, anexar, montar

Passos manuais (Console ou OCI CLI). AD deve ser o **mesmo** da instância.

### Criar

1. Storage → Block Volumes → Create.
2. Tamanho: ~100 GB (cabe no Always Free).
3. Home region; VPU prefer Balanced (Always Free).
4. Encryption: Oracle-managed keys (evitar Private Vault).

### Anexar

1. Resources → Attached Instances → Attach.
2. Preferir **Paravirtualized** (mais simples que iSCSI).
3. Anotar o device path (ex.: `/dev/sdb` ou `/dev/oracleoci/oraclevdb`).

### Preparar filesystem (Linux)

```bash
# Identificar disco novo (cuidado: NÃO formatar o boot)
lsblk
sudo parted /dev/sdb --script mklabel gpt mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L docker-data /dev/sdb1
sudo blkid /dev/sdb1   # copiar UUID
```

### Montar em `/opt/docker`

Se `/opt/docker` já tem dados no boot, **não** monte por cima sem migrar. Ver [runbooks/MIGRATE_TO_BLOCK_VOLUME.md](runbooks/MIGRATE_TO_BLOCK_VOLUME.md).

```bash
sudo mkdir -p /opt/docker
echo 'UUID=<uuid> /opt/docker ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
sudo mount -a
df -h /opt/docker
```

`nofail` evita boot preso se o volume estiver detached.

## Volume Backup (Camada 2)

- Máximo **5** backups Always Free (boot + block juntos).
- Sugestão inicial: **2** backups do Block Volume + **1** do Boot (sobram 2 slots).
- Criar: Block Volume → Create Backup (ou Backup Policy com retenção que não estoure 5).
- Antes de backup consistente: janela com Postgres/MinIO quietos ou parados (documentado em [BACKUP.md](BACKUP.md)).

### Restaurar Volume Backup

1. Backups → Create Block Volume from backup.
2. Attach à instância.
3. Montar (pode ser path temporário, depois substituir `/opt/docker`).
4. Ajustar fstab; validar `make health`.

## Object Storage (Camada 3)

- Bucket sugerido: `infra-backups` (private).
- Lifecycle para Archive: **ainda conta nos 20 GB** Always Free.
- API S3-compatible disponível; Customer Secret Keys + namespace.
- Monitorar uso: Console → Object Storage → bucket metrics; ou:

```bash
# Requer OCI CLI configurado (não instalado por este repo)
oci os ns get-metadata
# Usage: Console Cost Analysis / Monitoring metrics para ObjectStorage
```

Upload automático: **não implementado**. Hook preparado em `scripts/backup/hooks/post-backup.sh.example`.

## Vault

- Secrets/software keys: OK Always Free.
- **Não** criar Virtual Private Vault.
- Segredos de app continuam em `compose/*/.env` na VPS (fora do git); Vault é opcional futuro.

## Automação futura (preparada no repo)

| Peça | Estado |
|------|--------|
| Backup diário local | Script + `scripts/backup/cron.example` |
| Retenção / limpeza | `BACKUP_RETENTION_DAYS`, `BACKUP_KEEP_LAST` |
| Upload Object Storage | Hook stub apenas |
| Volume Backup OCI | Manual / policy Console |
| Restore | `restore.sh` + runbooks |

## Referências

- [STORAGE_ARCHITECTURE.md](STORAGE_ARCHITECTURE.md)
- [BACKUP.md](BACKUP.md)
- [Always Free Resources (Oracle)](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)
- [Creating a Block Volume](https://docs.oracle.com/iaas/Content/Block/Tasks/creatingavolume.htm)
- [Attaching a Block Volume](https://docs.oracle.com/iaas/Content/Block/Tasks/attachingavolume.htm)
