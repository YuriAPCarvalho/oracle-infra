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
```

Os scripts tambem podem ser executados diretamente com `bash scripts/<script>.sh`.

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

Proxima fase:

- configuracao operacional do Uptime Kuma;
- notificacoes via Telegram;
- monitoramento dos servicos existentes;
- monitoramento futuro dos bots;
- politica de alertas.

### Fase 3 - DNS e HTTPS

- dominio administrativo;
- DNS;
- certificados;
- acesso seguro aos paineis;
- nenhuma interface administrativa exposta sem protecao.

### Fase 4 - Deploy

- padrao de deploy;
- GitHub Actions;
- segredos;
- rollback;
- health check;
- documentacao.

### Fase 5 - Primeiros Servicos

Somente:

- bot de ponto;
- bot do Discord.

Outros projetos nao serao migrados inicialmente.

## Documentacao

- [Deploy](docs/DEPLOY.md)
- [Backup](docs/BACKUP.md)
- [Restore](docs/RESTORE.md)
- [Operations](docs/OPERATIONS.md)
- [Application Deployment](docs/APPLICATION_DEPLOYMENT.md)
- [Service Onboarding Checklist](docs/SERVICE_ONBOARDING_CHECKLIST.md)

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
