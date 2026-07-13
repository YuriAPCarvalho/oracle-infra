# Operations

Comandos operacionais para manutencao diaria da VPS.

## Status

```bash
make status
```

Mostra host, IP, sistema, kernel, arquitetura, CPU, RAM, swap, disco, load average, Docker, Compose, containers, imagens, volumes, networks, servicos gerenciados, UFW e Fail2Ban.

## Health check

```bash
make health
```

Valida Docker, Compose, disco, RAM, swap, CPU, load average, internet, DNS, servicos, redes `proxy` e `internal`, volumes, diretorios persistentes e socket Docker.

## Logs

```bash
make logs SERVICE=traefik
bash scripts/logs.sh portainer --tail 200
bash scripts/logs.sh dozzle --follow
bash scripts/logs.sh all --tail 50
```

`SERVICE` pode ser um servico gerenciado ou o nome de um container existente.

## Restart

```bash
make restart SERVICE=traefik
bash scripts/restart.sh all
```

O script valida a existencia do servico e do container antes de reiniciar.

## Shell em container

```bash
make shell SERVICE=portainer
```

O script detecta automaticamente `bash`, `sh` ou `ash`.

## Update

```bash
make update
```

Executa o fluxo seguro de atualizacao:

1. `git pull --ff-only`
2. validacao dos compose files
3. `docker compose pull`
4. `docker compose up -d`
5. resumo dos servicos

Nao remove containers, volumes e nao executa prune automaticamente.

## Backup e restore

```bash
make backup
bash scripts/restore.sh backups/backup-YYYYMMDD-HHMMSS.tar.gz
```

O backup pode solicitar `sudo` para ler dados protegidos em `/opt/docker`. O arquivo gerado fica em `backups/`, com permissao `600`, acompanhado por `.sha256`.

Consulte `docs/BACKUP.md` e `docs/RESTORE.md` para detalhes.
