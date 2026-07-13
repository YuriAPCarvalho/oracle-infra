# Oracle Infra

Infraestrutura versionada da VPS Oracle Cloud ARM64.

## Ambiente

- Ubuntu 22.04 LTS
- ARM64 / Ampere A1
- 2 OCPU
- 12 GB RAM
- 100 GB de armazenamento
- Docker e Docker Compose
- Traefik
- Portainer
- Uptime Kuma
- Dozzle
- Backups automatizados

## Estrutura

- `bootstrap/`: preparação e instalação do servidor
- `compose/`: serviços Docker
- `configs/`: configurações versionadas
- `scripts/`: manutenção, backup e diagnóstico
- `docs/`: documentação operacional
- `data/`: dados persistentes não versionados
- `secrets/`: segredos não versionados
- `backups/`: backups locais
- `logs/`: logs operacionais

## Segurança

Nunca versionar:

- arquivos `.env`
- senhas
- tokens
- chaves privadas
- certificados
- backups
- dados persistentes
