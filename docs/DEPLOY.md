# Deploy

Este projeto versiona a infraestrutura Docker Compose da VPS Oracle Cloud ARM64.

## Estrutura da VPS

- Codigo: `/opt/infra`
- Dados persistentes: `/opt/docker` (hierarquia canônica; alvo Block Volume — [STORAGE_ARCHITECTURE.md](STORAGE_ARCHITECTURE.md))
- Servicos Docker Compose: `compose/<servico>/compose.yml`
- Backups locais: `/opt/docker/backups/full/` (fallback: `/opt/infra/backups`)

## Pre-requisitos

- Ubuntu 22.04+
- Docker Engine
- Docker Compose Plugin
- Usuario com acesso ao Docker ou uso de `sudo`
- Redes Docker `proxy`, `internal` e `monitoring`

## Primeiro deploy

```bash
cd /opt/infra
bash bootstrap/02-docker.sh
bash bootstrap/bootstrap.sh
```

O bootstrap cria as redes necessarias, valida os compose files, baixa imagens e sobe Traefik, Portainer, Dozzle, Uptime Kuma, Node Exporter, cAdvisor, Prometheus e Grafana.

Antes do passo Grafana: criar `compose/grafana/.env` a partir do `.env.example`.

Métricas: [METRICS.md](METRICS.md). Grafana só via túnel SSH (`127.0.0.1:3000`).

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

## Aplicacoes futuras

Aplicacoes novas devem seguir `docs/APPLICATION_DEPLOYMENT.md`, `docs/CI_CD.md` e o checklist em `docs/SERVICE_ONBOARDING_CHECKLIST.md`.

Fluxo de imagem e deploy:

1. Build/push no GHCR via workflow reutilizavel (`reusable-docker-build.yml`).
2. Deploy SSH controlado (`reusable-vps-deploy.yml` + `scripts/ci-deploy-service.sh`).
3. Healthcheck + rollback de imagem + notificacao Discord.

Templates de caller (nao ativos neste repo): `templates/github-actions/`.

Secrets e chave SSH de deploy: `docs/GITHUB_SECRETS.md`.

Use `templates/docker-service/` como base estrutural. Nao crie Compose definitivo sem requisitos reais do projeto, imagem validada em ARM64, segredos mapeados e rollback documentado.

## Infra CI (este repositorio)

```bash
make validate
make validate-ci
make validate-workflows
```

O workflow `.github/workflows/infra.yml` valida scripts, Compose, templates e workflows. Ele **nao** faz deploy remoto nem envia notificacoes reais.
