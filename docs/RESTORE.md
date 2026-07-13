# Restore

O restore operacional e feito por `scripts/restore.sh`.

## Executar

```bash
cd /opt/infra
bash scripts/restore.sh backups/backup-YYYYMMDD-HHMMSS.tar.gz
```

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
