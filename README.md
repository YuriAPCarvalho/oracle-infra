# Oracle Infra

Infraestrutura versionada da VPS Oracle Cloud ARM64, baseada em Docker Compose.

## Ambiente

- Ubuntu 22.04+
- ARM64 / Ampere A1
- Docker Engine
- Docker Compose Plugin
- Traefik
- Portainer
- Dozzle
- Uptime Kuma

## Estrutura

- `bootstrap/`: preparacao e instalacao inicial do servidor
- `compose/`: compose files por servico
- `configs/`: configuracoes versionadas
- `scripts/`: manutencao, backup, restore e diagnostico
- `docs/`: documentacao operacional
- `data/`: dados locais nao versionados
- `secrets/`: segredos nao versionados
- `backups/`: backups locais
- `logs/`: logs operacionais

Na VPS, o codigo fica em `/opt/infra` e os dados persistentes ficam em `/opt/docker`.

## Comandos operacionais

```bash
make status
make health
make logs SERVICE=traefik
make restart SERVICE=traefik
make shell SERVICE=traefik
make backup
make update
```

Os scripts tambem podem ser executados diretamente com `bash scripts/<script>.sh`.

## Documentacao

- [Deploy](docs/DEPLOY.md)
- [Backup](docs/BACKUP.md)
- [Restore](docs/RESTORE.md)
- [Operations](docs/OPERATIONS.md)

## Seguranca

Nunca versionar:

- arquivos `.env`
- senhas
- tokens
- chaves privadas
- certificados
- backups
- dados persistentes

Backups locais ficam em `backups/`, sao ignorados pelo Git e podem conter banco de dados e chaves do Portainer.
