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
- `templates/`: modelos reutilizaveis para futuros servicos
- `services/`: levantamento documental de aplicacoes futuras
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
make validate
make validate-ci
make validate-workflows
```

Os scripts tambem podem ser executados diretamente com `bash scripts/<script>.sh`.

## CI/CD (base reutilizavel)

Este repositorio expoe workflows reutilizaveis de build (GHCR) e deploy (SSH + healthcheck + rollback), notificacoes Discord e templates para futuros repositorios de aplicacao.

Nao realiza deploy de bots automaticamente. Painéis seguem acessíveis apenas por tunel SSH.

- [CI/CD](docs/CI_CD.md)
- [Discord Notifications](docs/DISCORD_NOTIFICATIONS.md)
- [Rollback](docs/ROLLBACK.md)
- [GitHub Secrets](docs/GITHUB_SECRETS.md)
- [templates/github-actions](templates/github-actions/README.md)

## Roadmap

### Fase 1 - Fundacao

Concluida:

- hardening;
- Docker;
- Traefik;
- Portainer;
- Dozzle;
- Uptime Kuma;
- camada operacional;
- CI;
- backup;
- restore seguro.

### Fase 2 - Observabilidade

Em andamento com ScriptGold:

- Uptime Kuma monitors HTTP para `gold-api` / `gold-admin`;
- Dozzle / Portainer para logs e ops;
- `/health` nos apps.

### Fase 3 - DNS e HTTPS

Em andamento:

- Traefik ACME Let's Encrypt (HTTP-01);
- dominios publicos ScriptGold (`scriptgold.com.br`, `adm.scriptgold.com.br`);
- Cloudflare proxy + Full (strict).

### Fase 4 - Deploy

Base **experimental** disponivel:

- workflows reutilizaveis (`@v1`);
- GHCR + tags imutaveis;
- deploy SSH com host key pinada;
- rollback de imagem + estado em `/opt/docker/deploy-state`;
- notificacoes Discord;
- templates e documentacao.

### Fase 5 - Servicos

- bot de ponto ([Discovery](services/bot-ponto/DISCOVERY.md));
- bot do Discord;
- **ScriptGold** (`gold-api` + `gold-admin`) — migracao Railway → Oracle.

## Documentacao

- [Deploy](docs/DEPLOY.md)
- [Backup](docs/BACKUP.md)
- [Restore](docs/RESTORE.md)
- [Operations](docs/OPERATIONS.md)
- [Uptime Kuma](docs/UPTIME_KUMA.md)
- [Gestor Agro](docs/GESTOR_AGRO.md)
- [Application Deployment](docs/APPLICATION_DEPLOYMENT.md)
- [CI/CD](docs/CI_CD.md)
- [Discord Notifications](docs/DISCORD_NOTIFICATIONS.md)
- [Rollback](docs/ROLLBACK.md)
- [GitHub Secrets](docs/GITHUB_SECRETS.md)
- [Service Onboarding Checklist](docs/SERVICE_ONBOARDING_CHECKLIST.md)
- [Bot de ponto — Discovery](services/bot-ponto/DISCOVERY.md)
- [Bot de ponto — README](services/bot-ponto/README.md)

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
