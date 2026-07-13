# GitHub Secrets

Secrets e Environment para a base CI/CD. **Nao** armazenar IPs, tokens ou chaves neste repositorio.

## Propagacao entre repositorios

- Secrets de Environment **nao** se propagam automaticamente de `oracle-infra` para o repo do servico (nem o inverso).
- O **caller** deve declarar e passar cada secret no bloco `secrets:` do `workflow_call`.
- Configure o Environment `production` (revisores, branch policy) **preferencialmente no repositorio do servico**.

## Secrets de deploy

| Nome | Obrigatorio | Descricao |
|------|-------------|-------------|
| `VPS_HOST` | sim | Hostname ou IP (somente no secret) |
| `VPS_USER` | sim | Usuario SSH |
| `VPS_SSH_PRIVATE_KEY` | sim | Chave privada exclusiva do Actions |
| `VPS_SSH_HOST_KEY` | sim | Linha(s) `known_hosts` do host (ver abaixo) |
| `VPS_SSH_PORT` | nao | Porta SSH (padrao 22) |
| `DISCORD_WEBHOOK_URL` | recomendado | Webhook Discord |

## VPS_SSH_HOST_KEY

O pipeline usa `StrictHostKeyChecking=yes` (sem `accept-new` / `no`).

Obter a linha known_hosts (na sua estacao, uma vez):

```bash
ssh-keyscan -p 22 <VPS_HOST>
```

Armazene a saida completa (algoritmo + chave) em `VPS_SSH_HOST_KEY`. A linha deve mencionar o mesmo host/IP de `VPS_HOST`.

Rotacione se o host key da VPS mudar (reinstalacao do SO, etc.).

## Chave SSH privada no runner

1. `umask 077` antes de gravar.
2. Arquivo temporario modo `600`.
3. Nunca ecoar o conteudo.
4. Remover em step `always()` (`shred`/`rm`).
5. Nao publicar como artefato.

Geracao (manual; nao versionar):

```bash
ssh-keygen -t ed25519 -f ./gha-oracle-deploy -C "github-actions-oracle-deploy" -N ""
```

Adicionar so a **publica** em `~/.ssh/authorized_keys` (`chmod 700 ~/.ssh`, `chmod 600 authorized_keys`).

## GHCR

| Nome | Obrigatorio? | Quando |
|------|--------------|--------|
| `GITHUB_TOKEN` | automatico | Publish com `packages: write` no job de publicacao |
| `GHCR_USERNAME` / `GHCR_TOKEN` | nao | Cross-org / quando token padrao nao basta |

Nao conceder `packages: write` a jobs de apenas validacao.

Recomendacao: Environment `production` no **repositorio do servico** para aprovacao manual.

Secrets usados no job `uses:` precisam estar acessiveis a esse job. Enquanto o `actionlint` nao aceitar `environment` no mesmo job que `uses`, o template usa:

1. job `approve` com `environment: production` (gate de aprovacao);
2. job `deploy` com `uses:` e `secrets:` explicitos.

Coloque `VPS_*` / `DISCORD_WEBHOOK_URL` como **repository secrets** do servico (ou espelho dos Environment secrets). O reusable tambem recebe `environment: production` como input para concurrency/auditoria; o Environment do callee em oracle-infra nao substitui o do servico.

## O que nao versionar

- IP da VPS em templates
- Chaves SSH / host keys reais
- URL de webhook Discord
- Tokens / `.env` reais

## Referencias

- [CI/CD](CI_CD.md)
- [Discord Notifications](DISCORD_NOTIFICATIONS.md)
- [Rollback](ROLLBACK.md)
