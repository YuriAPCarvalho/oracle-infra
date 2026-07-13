# CI/CD

Base **experimental** e reutilizável de CI/CD para futuros serviços na VPS Oracle ARM64.

> Esta base **não** está declarada pronta para produção até ser validada com o primeiro deploy controlado de um serviço real (ex.: bot de ponto). Nenhum bot é migrado somente por existir esta base.

## Principios

- A VPS nao e ambiente de desenvolvimento.
- Imagens no **GitHub Container Registry (GHCR)**.
- Deploy de producao prefere tag imutavel `sha-<commit>`.
- `latest` nao deve ser a unica referencia de producao.
- Notificacoes de pipeline via **Discord webhook**.
- Telegram nao e usado neste fluxo.
- Painéis continuam acessíveis apenas por tunel SSH (sem DNS/HTTPS publico nesta fase).
- Callers em **outros repositórios** pinam workflows com tag versionada (`@v1`), nunca `@main` em produção.

## Arquitetura

```text
repo da aplicacao
  -> job de testes (caller)
  -> reusable-docker-build@v1  (validate OU publish)
  -> Environment production no repo do servico
  -> reusable-vps-deploy@v1
       -> checkout YuriAPCarvalho/oracle-infra@v1 (.ci-infra) para Discord action
       -> scp config KEY=VALUE
       -> ssh comando fixo: ci-deploy-service.sh --config ...
       -> flock (git global + compose por servico)
       -> estado em /opt/docker/deploy-state/<service>/
       -> healthcheck / rollback
       -> Discord (fail-open)
```

Artefatos:

| Artefato | Funcao |
|----------|--------|
| `.github/workflows/reusable-docker-build.yml` | Build validate **ou** publish (jobs separados) |
| `.github/workflows/reusable-vps-deploy.yml` | Deploy SSH reutilizavel |
| `.github/actions/discord-notify/` | Action (via checkout do oracle-infra) |
| `scripts/discord-notify.sh` | Webhook + dry-run |
| `scripts/ci-deploy-service.sh` | Deploy na VPS (+ `--dry-run`) |
| `templates/github-actions/` | Callers de exemplo |

## Versionamento dos reutilizaveis

```yaml
uses: YuriAPCarvalho/oracle-infra/.github/workflows/reusable-docker-build.yml@v1
uses: YuriAPCarvalho/oracle-infra/.github/workflows/reusable-vps-deploy.yml@v1
```

### Criar / atualizar tags

1. Validar CI local e `make validate-ci`.
2. Revisar mudancas breaking nos inputs.
3. Criar tag anotada (exemplo):

```bash
git tag -a v1 -m "reusable CI/CD workflows v1"
git push origin v1
```

4. Para mudancas compativeis, mover `v1` com cuidado ou publicar `v1.1.0` e atualizar callers conscientemente.
5. Atualizar `infra_ref: v1` (e o pin `uses: ...@v1`) nos repositorios de servico apos dry-run.

Compatibilidade: tratar inputs removidos/renomeados como breaking; documentar no release.

## Estrategia de imagens (GHCR)

```text
ghcr.io/<usuario-ou-organizacao>/<servico>:<tag>
```

| Tag | Uso |
|-----|-----|
| `sha-<commit>` | Producao (imutavel) |
| `<branch>` | Rastreio |
| `latest` | Conveniencia; nunca unica referencia de prod |
| `release-<versao>` | Semver |

- Job **validate** (`push=false`): `contents: read` apenas; sem login GHCR; sem `packages: write`.
- Job **publish** (`push=true`): login + `packages: write`.
- Preferir `GITHUB_TOKEN`. `GHCR_*` opcional (cross-org).

## Fluxo de build

1. **Caller** executa testes (sem `test_command` no reusable).
2. Chama `reusable-docker-build` com inputs estruturados.
3. Validate-only ou publish conforme `push`.

## Fluxo de deploy

1. Environment `production` no **repositorio do servico** (aprovacao/secrets la).
2. Caller passa secrets **explicitamente** no `workflow_call` (sem heranca magica entre repos).
3. Checkout tooling `oracle-infra@v1` em `.ci-infra` (Discord action).
4. Validacao rigorosa de inputs (compose relativo `compose/<svc>`).
5. SSH com `StrictHostKeyChecking=yes` + `VPS_SSH_HOST_KEY`.
6. `scp` de arquivo de config; comando remoto **fixo**.
7. Locks: `flock` global Git + por servico Compose.
8. Estado em `/opt/docker/deploy-state/<service>/`.
9. Healthcheck / rollback / Discord / summary.

### Dry-run remoto

```text
inputs.dry_run: true
# ou na VPS:
bash /opt/infra/scripts/ci-deploy-service.sh --config /tmp/deploy.env
# com DRY_RUN=true no config, ou:
bash scripts/ci-deploy-service.sh --dry-run --service ... --compose-dir compose/...
```

Dry-run **nao** faz: pull, git mutate, alteracao de container, gravacao de estado, webhook Discord (workflow tambem omite notify em dry-run).

## Estado fora do Git

```text
/opt/docker/deploy-state/<service>/
├── current.env
├── previous.env
└── last-deploy.json
```

Permissoes: diretorio `700`, arquivos `600`. Incluido no backup via `/opt/docker` (`docs/BACKUP.md`).

## Locks

| Lock | Arquivo | Escopo |
|------|---------|--------|
| Git | `/opt/infra/.locks/git.lock` | Qualquer `git pull` de deploy |
| Compose | `/opt/infra/.locks/compose-<service>.lock` | Update do servico |

Impede dois deploys (mesmo de servicos diferentes) de puxar Git ao mesmo tempo; e impede dois updates Compose do mesmo servico.

## Validacao de inputs

Bloqueados: `..`, caminho absoluto de compose, symlink que escape `/opt/infra/compose`, espacos/metacaracteres, opcoes desconhecidas, chaves de config duplicadas.

## Concorrencia GHA

```text
deploy-<servico>-<ambiente>
cancel-in-progress: false
```

## Ambientes e secrets

Configure `production` no **repositorio do servico** (aprovacao no job `approve` do template). Secrets usados no job `uses:` devem ser passados explicitamente; nao ha heranca magica entre repositorios. Ver `docs/GITHUB_SECRETS.md`.

## Execucao manual na VPS

```bash
umask 077
cat >/tmp/deploy.env <<'EOF'
SERVICE_NAME=example
IMAGE_REPO=ghcr.io/example/example
IMAGE_TAG=sha-deadbeef
COMPOSE_REL=compose/example
CONTAINER_NAME=example
HEALTH_MODE=running
ENABLE_ROLLBACK=true
DRY_RUN=true
EOF
chmod 600 /tmp/deploy.env
bash /opt/infra/scripts/ci-deploy-service.sh --config /tmp/deploy.env
```

## Validacao local (oracle-infra)

```bash
make validate
make validate-ci
make validate-workflows
bash scripts/discord-notify.sh --dry-run --title t --status started --service s
```

## Falhas comuns

| Sintoma | Acao |
|---------|------|
| SSH host key mismatch | Atualizar `VPS_SSH_HOST_KEY` |
| compose_dir rejected | Usar `compose/<svc>` relativo |
| dirty working tree | Nao editar `/opt/infra` na VPS |
| lock timeout | Aguardar outro deploy; investigar processo |
| packages 403 | Garantir job publish com `packages: write` |

## Referencias

- [Discord Notifications](DISCORD_NOTIFICATIONS.md)
- [Rollback](ROLLBACK.md)
- [GitHub Secrets](GITHUB_SECRETS.md)
- [Application Deployment](APPLICATION_DEPLOYMENT.md)
- [templates/github-actions/README.md](../templates/github-actions/README.md)
