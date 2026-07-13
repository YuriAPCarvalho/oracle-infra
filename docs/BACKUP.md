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

Tambem sera gerado:

```text
backups/backup-YYYYMMDD-HHMMSS.tar.gz.sha256
```

## Permissoes e seguranca

O backup inclui dados sensiveis de `/opt/docker`, como banco e chaves do Portainer. O script usa `sudo` somente para ler dados persistentes protegidos, cria o arquivo primeiro como `.partial`, valida a integridade antes de concluir e remove arquivos parciais em caso de falha.

O arquivo final pertence ao usuario que iniciou o script e recebe permissao `600`. Nao envie backups para o Git; `backups/` permanece ignorado pelo `.gitignore`.

Para validar manualmente:

```bash
BACKUP_FILE="$(ls -t backups/backup-*.tar.gz | head -1)"
tar -tzf "${BACKUP_FILE}" >/dev/null
sha256sum -c "${BACKUP_FILE}.sha256"
```

## Consistencia

O script avisa quando existem containers ativos e continua. Isso evita indisponibilidade automatica, mas dados gravados durante o backup podem ficar inconsistentes. Para backups mais rigorosos, agende uma janela de manutencao e pare os servicos antes de executar o backup.
