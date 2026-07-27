# GitHub Actions templates

Templates de pipeline para **repositórios de aplicação futuros**. Não são workflows ativos deste repositório.

**Status:** experimental até o primeiro deploy controlado de um serviço real.

## Arquivos

| Arquivo | Uso |
|---------|-----|
| `build-and-publish.yml` | Testes no **caller**, depois build/publish GHCR via reusable |
| `deploy-to-vps.yml` | Deploy SSH + health + rollback + Discord |

## Versionamento (`@v1`)

Os templates pinam:

```yaml
uses: YuriAPCarvalho/oracle-infra/.github/workflows/<workflow>@v1
```

Regras:

- Preferir tag versionada (`v1`, `v1.2.0`).
- **Não** usar `@main` em produção.
- Para atualizar callers: publicar nova tag em `oracle-infra`, validar dry-run, então bump do pin nos serviços.
- Criação de release: `git tag -a v1 -m "CI/CD reusable workflows v1" && git push origin v1` (somente após revisão).

O job de deploy também faz checkout explícito de `YuriAPCarvalho/oracle-infra@v1` em `.ci-infra` para a composite action Discord (não existe no workspace do caller).

## Como usar

1. Copie o arquivo para `.github/workflows/` no repositório da aplicação.
2. Substitua placeholders `<...>`.
3. Crie Environment `production` **no repositório do serviço** (secrets + aprovação opcional).
4. Passe secrets **explicitamente** no bloco `secrets:` do `workflow_call` (não há propagação automática).
5. Compose relativo: `compose/<SERVICE_NAME>` sob `/opt/infra` (caminhos absolutos são rejeitados).
6. Publique imagens com `sha-<commit>`.

## Testes

Testes rodam no job `test` do **caller**. O reusable de build **não** aceita `test_command` arbitrário.

## Placeholders

| Placeholder | Significado |
|-------------|-------------|
| `<OWNER_OR_ORG>` | Namespace GHCR |
| `<SERVICE_NAME>` | Nome do serviço |
| `<PRODUCTION_BRANCH>` | Branch de produção |
| `<BUILD_CONTEXT>` | Contexto Docker |
| `<DOCKERFILE_PATH>` | Dockerfile |
| `<TEST_COMMAND>` | Comando de teste **no caller** |
| `<HEALTH_MODE>` | `running`, `docker`, `http` ou `exec` |

## Referências

- `docs/CI_CD.md`
- `docs/GITHUB_SECRETS.md`
- `docs/DISCORD_NOTIFICATIONS.md`
- `docs/ROLLBACK.md`
