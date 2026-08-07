# Restore

O restore operacional e feito por `scripts/restore.sh`.

## Dry-run

```bash
bash scripts/restore.sh -n backups/backup-YYYYMMDD-HHMMSS.tar.gz
# ou
bash scripts/restore.sh --dry-run backups/backup-YYYYMMDD-HHMMSS.tar.gz
```

Não executa restore real; valida checksum/arquivo e lista o que seria restaurado (incluindo `opt/docker/prometheus` e `opt/docker/grafana` quando presentes).

O script valida o arquivo, extrai em um diretorio temporario, mostra os destinos que serao restaurados e pede confirmacao explicita.

Para continuar, digite:

```text
RESTORE
```

## Comportamento de seguranca

- O restore nunca acontece silenciosamente.
- Caminhos existentes sao avisados antes da confirmacao.
- A restauracao de `/opt/docker` pode exigir `sudo`.
- Depois do restore, valide a infraestrutura com `make health`.

## Fluxo recomendado

```bash
cd /opt/infra
bash scripts/restore.sh backups/backup-YYYYMMDD-HHMMSS.tar.gz
make health
docker ps
```
