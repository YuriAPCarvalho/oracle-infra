# Backup

O backup operacional e gerado por `scripts/backup.sh`.

## Conteudo

- `compose/`
- `configs/`
- `bootstrap/`
- `scripts/`
- `docs/`
- `/opt/docker`

## Executar

```bash
cd /opt/infra
make backup
```

Ou diretamente:

```bash
bash scripts/backup.sh
```

O arquivo sera salvo em:

```text
backups/backup-YYYYMMDD-HHMMSS.tar.gz
```

## Consistencia

O script avisa quando existem containers ativos e continua. Isso evita indisponibilidade automatica, mas dados gravados durante o backup podem ficar inconsistentes. Para backups mais rigorosos, agende uma janela de manutencao e pare os servicos antes de executar o backup.
