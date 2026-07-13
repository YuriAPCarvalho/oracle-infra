# Rollback

Estrategia generica de rollback para deploys de aplicacao via CI/CD.

## Escopo desta fase

Rollback cobertos:

- **imagem Docker** anterior previamente implantada;
- reaplicacao via `docker compose up -d`;
- novo healthcheck;
- notificacao Discord;
- registro no relatorio de deploy.

**Fora de escopo nesta fase:**

- restauracao de volumes `/opt/docker`;
- restore de banco de dados;
- `git reset --hard` como fluxo normal;
- rollback baseado em backup tar (ver `docs/RESTORE.md` — processo separado).

Alteracoes incompatíveis de schema/banco exigem estrategia propria do servico (migracoes versionadas, expand/contract, etc.).

## Registro obrigatorios no deploy

Antes/depois o pipeline registra:

| Campo | Origem |
|-------|--------|
| imagem anterior | `docker inspect` do container |
| imagem nova | input `image:tag` |
| commit | GitHub / infra HEAD |
| horario | UTC ISO |
| resultado do healthcheck | modo configurado |
| rollback realizado | flag no relatorio |

## Fluxo em falha de healthcheck

```text
1. healthcheck falhou
2. se --enable-rollback e existe imagem anterior distinta:
   a. notificar contexto (via workflow)
   b. restaurar SERVICE_IMAGE=<imagem-anterior>
   c. docker compose pull (se necessario) + up -d
   d. aguardar healthcheck
   e. registrar resultado
   f. notificar Discord (rollback concluido ou falhou)
3. se rollback desabilitado ou sem imagem anterior: falha final
```

Estado de deploy (imagem atual/anterior, resultado, rollback) fica em `/opt/docker/deploy-state/<service>/`, fora do Git, e entra no backup de `/opt/docker`.

## Criterios de healthcheck

O deploy generico suporta:

| Modo | Uso |
|------|-----|
| `running` | Container em execucao (padrao seguro) |
| `docker` | `State.Health.Status=healthy` (ou running se sem HEALTHCHECK) |
| `http` | Endpoint HTTP 2xx |
| `exec` | Comando dentro do container |

Parametros: timeout total e numero de retries.

### Bots futuros sem HTTP

Opcoes documentadas (escolher por servico; nao inventar check ficticio):

- `docker inspect` health status;
- processo principal ativo (`exec`);
- heartbeat interno;
- logs recentes (operacional, nao unico criterio de pipeline);
- conexao ativa com dependencia externa.

## Procedimento manual de emergencia

```bash
cd /opt/infra
# Imagem anterior conhecida (tag imutavel):
bash scripts/ci-deploy-service.sh \
  --service <SERVICE> \
  --image ghcr.io/<OWNER>/<SERVICE> \
  --tag <TAG_ANTERIOR> \
  --compose-dir /opt/infra/compose/<SERVICE> \
  --container <SERVICE> \
  --health-mode running \
  --no-rollback
```

Em seguida: `make logs SERVICE=<SERVICE>` e validacao operacional.

## Dados persistentes

Se o deploy novo corromper dados em `/opt/docker/<service>`:

1. Nao espere que o rollback de imagem desfaça os dados.
2. Use `docs/RESTORE.md` + backup anterior.
3. Documente no onboarding do servico o impacto de cada release em persistencia.

## Relacao com Application Deployment

Todo servico deve documentar:

- versao/imagem anterior;
- comando de retorno;
- impacto em dados;
- validacao pos-rollback;
- criterio para abortar deploy.

Ver `docs/APPLICATION_DEPLOYMENT.md` e `docs/SERVICE_ONBOARDING_CHECKLIST.md`.
