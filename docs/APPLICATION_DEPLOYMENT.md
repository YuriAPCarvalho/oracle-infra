# Application Deployment

Fluxo oficial para futuras aplicacoes.

```text
desenvolvimento local
-> testes
-> commit
-> push
-> GitHub Actions
-> build da imagem
-> publicacao da imagem (GHCR)
-> atualizacao controlada na VPS
-> health check
-> validacao
-> rollback se necessario
-> notificacao Discord
```

A base reutilizavel vive neste repositorio e e **experimental** ate o primeiro deploy controlado de um servico real. Detalhes: [CI_CD.md](CI_CD.md), [ROLLBACK.md](ROLLBACK.md), [DISCORD_NOTIFICATIONS.md](DISCORD_NOTIFICATIONS.md), [GITHUB_SECRETS.md](GITHUB_SECRETS.md).

Callers devem pinar `YuriAPCarvalho/oracle-infra` com tag versionada (`@v1`), nao `@main`. Testes ficam no workflow do **caller**; o reusable de build nao executa shell arbitrario.

## Principios

- A VPS nao e ambiente de desenvolvimento.
- Arquivos nao devem ser editados manualmente em `/opt/infra`.
- Alteracoes entram por Git.
- Dados persistentes ficam sob `/opt/docker/` (ver [STORAGE_ARCHITECTURE.md](STORAGE_ARCHITECTURE.md); apps em `applications/<service>`).
- Segredos nao entram no Git.
- `.env` permanece apenas na VPS ou em gerenciador de segredos.
- Cada servico tera seu proprio Compose.
- Banco nao deve ser criado sem requisito real.
- Portas nao serao expostas sem necessidade.
- Bots sem interface HTTP e **sem necessidade de egress** podem ficar apenas na rede `internal`.
- Bots/workers que precisam de HTTPS de saída (portais externos, webhooks) devem usar uma **bridge própria com outbound**, sem portas publicadas e sem Traefik.
- Traefik sera usado apenas quando houver endpoint HTTP real.
- Cada aplicacao devera ter rollback documentado.
- Producao prefere tag imutavel `sha-<commit>` no GHCR.
- Notificacoes de pipeline via Discord webhook (nao Telegram). Webhooks de **pipeline** e de **bot funcional** devem ser distintos.

## Rede para workers com outbound

Excecao documentada ao padrao `internal`:

- Servicos **sem** egress: rede `internal`.
- Servicos **com** egress necessario (portais HTTPS, webhooks): bridge propria do projeto, sem portas e sem Traefik.

## Padrao de Compose

Use `templates/docker-service/` como ponto de partida. O template nao e uma aplicacao de producao; ele existe para manter consistencia de seguranca, redes, persistencia e healthcheck.

O deploy CI exporta `SERVICE_IMAGE=<repo>:<tag>` compatível com `${SERVICE_IMAGE}` do template.

## Deploy Controlado

1. Testar no workflow do repositorio da aplicacao.
2. Publicar imagem versionada no GHCR (`reusable-docker-build.yml` com `push: true`).
3. Atualizar o Compose pelo Git neste repositorio de infra (manifesto relativo `compose/<svc>`).
4. Executar `make validate` neste repositorio.
5. Deploy via `reusable-vps-deploy.yml@v1` (preferir `dry_run` primeiro).
6. Conferir logs, health check e `/opt/docker/deploy-state/<svc>/`.
7. Registrar/acompanhar rollback automatico se habilitado.
8. Conferir Discord e summary do job.

## Rollback

Ver [ROLLBACK.md](ROLLBACK.md).

Todo servico deve documentar:

- versao anterior da imagem;
- comando de retorno;
- impacto em dados persistentes;
- validacao pos-rollback;
- criterio para abortar deploy.

## Observabilidade

Para bots sem HTTP:

- container running;
- restart count;
- verificacao de processo;
- logs recentes;
- heartbeat quando suportado;
- alerta por ausencia de heartbeat;
- monitoramento de dependencias externas.

Para bots com HTTP:

- endpoint `/health`;
- codigo HTTP esperado;
- tempo de resposta;
- validade do certificado, se publico;
- monitoramento pelo Uptime Kuma.

Notificacoes de **pipeline** (sucesso/falha/rollback) usam Discord. Alertas de disponibilidade do Uptime Kuma sao assunto separado.
