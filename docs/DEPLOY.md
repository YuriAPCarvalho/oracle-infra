# Deploy

Este projeto versiona a infraestrutura Docker Compose da VPS Oracle Cloud ARM64.

## Estrutura da VPS

- Codigo: `/opt/infra`
- Dados persistentes: `/opt/docker`
- Servicos Docker Compose: `compose/<servico>/compose.yml`
- Backups locais: `/opt/infra/backups`

## Pre-requisitos

- Ubuntu 22.04+
- Docker Engine
- Docker Compose Plugin
- Usuario com acesso ao Docker ou uso de `sudo`
- Redes Docker `proxy` e `internal`

## Primeiro deploy

```bash
cd /opt/infra
bash bootstrap/02-docker.sh
bash bootstrap/bootstrap.sh
```

O bootstrap cria as redes necessarias, valida os compose files, baixa imagens e sobe Traefik, Portainer, Dozzle e Uptime Kuma.

## Subir um servico manualmente

```bash
docker compose -f compose/traefik/compose.yml config --quiet
docker compose -f compose/traefik/compose.yml pull
docker compose -f compose/traefik/compose.yml up -d
```

Use o mesmo padrao para `portainer`, `dozzle` e `uptime-kuma`.

## Atualizacao operacional

```bash
make update
```

O comando executa `git pull --ff-only`, valida todos os compose files, baixa imagens e aplica `docker compose up -d`. Ele nao remove containers, volumes nem executa prune.
