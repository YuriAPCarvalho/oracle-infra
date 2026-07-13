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

## Validacao

```bash
make shellcheck
make validate-compose
make validate-workflows
make validate-ci
make validate
```

`make validate` executa sintaxe Bash, ShellCheck, `git diff --check`, validacao dos Compose existentes, validacao do template de servico, checks basicos contra `.env` real ou segredos obvios, actionlint nos workflows e dry-run do payload Discord (sem envio).

`make validate-ci` foca na base CI/CD (workflows, templates documentais, notify dry-run).

Documentacao CI/CD: `docs/CI_CD.md`, `docs/DISCORD_NOTIFICATIONS.md`, `docs/ROLLBACK.md`, `docs/GITHUB_SECRETS.md`.

Deploy remoto de aplicacoes **nao** e feito por `make update`. Use o fluxo em `docs/CI_CD.md` / `scripts/ci-deploy-service.sh`.

## Integracao de novos servicos

Novos servicos so entram no inventario operacional depois de existir Compose real, container validado e documentacao concluida.

- `status.sh`: passa a exibir o servico quando ele for adicionado em `scripts/lib/common.sh`.
- `health.sh`: deve receber checks especificos e diretorios persistentes reais.
- `logs.sh`: ja aceita container existente, mas o servico gerenciado deve entrar no inventario quando for producao.
- `restart.sh`, `shell.sh` e `update.sh`: dependem do Compose real registrado no helper comum.
- `backup.sh`: inclui `/opt/docker`, mas o servico deve documentar o que precisa de backup.
- `restore.sh`: deve ser testado com `--dry-run` apos o primeiro backup contendo o servico.
- Makefile e GitHub Actions: devem ganhar apenas targets e validacoes que reflitam servicos reais.
- Uptime Kuma: deve monitorar container, heartbeat ou endpoint HTTP conforme o tipo do bot.

Bots sem HTTP devem ficar apenas na rede `internal`. Traefik deve ser usado somente quando houver endpoint HTTP real.
