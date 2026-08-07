# Runbook: migrar `/opt/docker` para Block Volume

**Não executar automaticamente.** Aplicar só em janela de manutenção na VPS, após review.

Pré-requisitos: Block Volume criado e anexado ([OCI_STORAGE.md](../OCI_STORAGE.md)); código deste repo já atualizado com a hierarquia nova **ou** migrar paths flat → hierárquico no mesmo procedimento.

## Objetivo

1. Dados persistentes em Block Volume montado em `/opt/docker`.
2. Boot Volume só com SO, Docker engine e `/opt/infra`.
3. Hierarquia canônica ([STORAGE_ARCHITECTURE.md](../STORAGE_ARCHITECTURE.md)).

## Pré-checagem

```bash
df -h /
df -h /opt/docker || true
lsblk
docker ps
cd /opt/infra && make health
# Backup Camada 1 obrigatório antes
make backup
```

Confirmar espaço livre no volume novo ≥ tamanho usado de `/opt/docker`.

## Procedimento A — volume novo, paths flat ainda no boot

Use se os Compose ainda apontam para paths antigos (`/opt/docker/postgres/data`, etc.) **ou** se já apontam para a hierarquia nova (ajuste `rsync`/`mv` abaixo).

### 1. Parar stacks que escrevem em `/opt/docker`

```bash
cd /opt/infra
# Ajuste a lista conforme serviços ativos
for s in grafana prometheus postgres redis minio waha gold-api uptime-kuma portainer traefik; do
  f="compose/${s}/compose.yml"
  [[ -f "$f" ]] && docker compose -f "$f" stop || true
done
```

### 2. Preparar disco e mount temporário

```bash
# Substituir /dev/sdb1 pelo device real
sudo mkfs.ext4 -L docker-data /dev/sdb1   # só se ainda não formatado
sudo mkdir -p /mnt/docker-new
sudo mount /dev/sdb1 /mnt/docker-new
```

### 3. Copiar dados

```bash
sudo rsync -aHAX --info=progress2 /opt/docker/ /mnt/docker-new/
```

### 4. (Opcional) Reorganizar para hierarquia nova

Se os Compose do repo já usam paths novos e o disco ainda está flat:

```bash
# Exemplos — validar cada mv antes
sudo mkdir -p /mnt/docker-new/{databases/postgres,databases/redis,object-storage/minio,monitoring/prometheus,monitoring/grafana,platform/traefik,platform/portainer,platform/uptime-kuma,applications/gold-api,applications/waha,backups/{postgres,minio,redis,grafana,prometheus,applications,full},logs,screenshots,uploads,deploy-state}

sudo mv /mnt/docker-new/postgres/data /mnt/docker-new/databases/postgres/data
sudo mv /mnt/docker-new/redis/data /mnt/docker-new/databases/redis/data
sudo mv /mnt/docker-new/minio/data /mnt/docker-new/object-storage/minio/data
sudo mkdir -p /mnt/docker-new/object-storage/minio/{config,certs}
sudo mv /mnt/docker-new/prometheus/data /mnt/docker-new/monitoring/prometheus/data
sudo mv /mnt/docker-new/grafana/data /mnt/docker-new/monitoring/grafana/data
sudo mv /mnt/docker-new/traefik /mnt/docker-new/platform/traefik
sudo mv /mnt/docker-new/portainer /mnt/docker-new/platform/portainer
sudo mv /mnt/docker-new/uptime-kuma /mnt/docker-new/platform/uptime-kuma
sudo mv /mnt/docker-new/gold-api /mnt/docker-new/applications/gold-api
sudo mv /mnt/docker-new/waha /mnt/docker-new/applications/waha
```

Aplicar ownership:

```bash
cd /opt/infra
DATA_ROOT=/mnt/docker-new bash scripts/storage-prepare-dirs.sh
# Ajustar UIDs se prepare-dirs criou vazios por cima — preferir chown nos dirs já migrados:
sudo chown -R 65534:65534 /mnt/docker-new/monitoring/prometheus/data
sudo chown -R 472:472 /mnt/docker-new/monitoring/grafana/data
```

### 5. Trocar mount

```bash
sudo mv /opt/docker /opt/docker.boot-backup
sudo mkdir -p /opt/docker
UUID=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "UUID=${UUID} /opt/docker ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo umount /mnt/docker-new
sudo mount /opt/docker
df -h /opt/docker
```

### 6. Subir serviços e validar

```bash
cd /opt/infra
# git pull do commit com novos paths, se ainda não aplicado
bash scripts/storage-prepare-dirs.sh
# subir na ordem: traefik → dados → apps → monitoring
docker compose -f compose/traefik/compose.yml up -d
docker compose -f compose/postgres/compose.yml up -d
docker compose -f compose/redis/compose.yml up -d
docker compose -f compose/minio/compose.yml up -d
# ... demais
make health
docker ps
```

### 7. Limpeza (só após dias estáveis)

```bash
# sudo rm -rf /opt/docker.boot-backup
```

## Procedimento B — só reorganizar hierarquia no mesmo disco

Sem Block Volume ainda: stop → `mv` conforme seção 4 → atualizar Compose → start → `make health`.

## Rollback rápido

1. Stop containers.
2. Comentar linha fstab do Block Volume; `umount /opt/docker`.
3. `sudo mv /opt/docker.boot-backup /opt/docker` (se ainda existir).
4. Start stacks com paths compatíveis com o que estiver no disco.
5. `make health`.

## Checklist pós-migração

- [ ] `findmnt /opt/docker` mostra o Block Volume
- [ ] `make health` OK
- [ ] Traefik certs, Postgres, MinIO, sessões WAHA/gold-api intactos
- [ ] Alertas Prometheus cobrem `mountpoint="/opt/docker"`
- [ ] `make backup` grava em `/opt/docker/backups/full/`
- [ ] Volume Backup OCI do Block Volume criado (Camada 2)
- [ ] Slack/Discord: testar alerta de disco no mount novo
