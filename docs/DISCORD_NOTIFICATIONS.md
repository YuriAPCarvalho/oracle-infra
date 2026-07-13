# Discord Notifications

Notificacoes de pipeline CI/CD via webhook do Discord.

## Escopo

- Eventos de **deploy/rollback** do fluxo reutilizavel.
- Nao substitui monitoramento do Uptime Kuma.
- Telegram **nao** e utilizado neste fluxo.

## Eventos

| Status interno | Titulo tipico |
|----------------|---------------|
| `started` | Deploy iniciado |
| `success` | Deploy concluido |
| `failure` | Deploy falhou |
| `rollback_started` | Rollback iniciado |
| `rollback_success` | Rollback concluido |
| `rollback_failure` | Rollback falhou |

Campos do embed: titulo, servico, ambiente, status, commit, autor, branch, URL da execucao, mensagem, cor por nivel.

## Configuracao

1. No Discord: Canal → Integracoes → Webhooks → Novo webhook.
2. Copie a URL.
3. Armazene **somente** como secret `DISCORD_WEBHOOK_URL` (repositorio ou Environment `production`).
4. Nunca versionar a URL. Nunca colocar valor real em `.env.example`.

## Artefatos

| Caminho | Uso |
|---------|-----|
| `.github/actions/discord-notify/` | Composite action para workflows |
| `scripts/discord-notify.sh` | Script versionado (CI e dry-run local) |

## Seguranca

- A URL vem exclusivamente de `DISCORD_WEBHOOK_URL`.
- O script **nunca** imprime a URL completa (apenas host redacted).
- Nao passar a URL como argumento de linha de comando se o ambiente puder logar argv; use a variavel de ambiente.
- Timeout configuravel (padrao 10s).
- Retries limitados (padrao 2). Sem retry infinito.

## Comportamento em falha

Por padrao (**fail-open**):

1. A falha de notificacao e registrada nos logs.
2. Nao mascara uma falha real de deploy (o exit code do deploy permanece).
3. Nao transforma deploy bem-sucedido em falha.

Para falhar o job se o webhook falhar, use `--fail-on-error` / `fail_on_error: true` explicitamente.

## Dry-run local

Nao exige webhook real:

```bash
bash scripts/discord-notify.sh --dry-run \
  --title "Deploy iniciado" \
  --service exemplo \
  --environment production \
  --status started \
  --commit abcdef \
  --author "dev" \
  --branch main \
  --run-url "https://github.com/example/repo/actions/runs/1" \
  --message "dry-run only"
```

Via Make:

```bash
make validate-ci
```

## Uso na action

```yaml
- uses: ./.github/actions/discord-notify
  with:
    webhook_url: ${{ secrets.DISCORD_WEBHOOK_URL }}
    title: Deploy concluido
    service: my-service
    environment: production
    status: success
    commit: ${{ github.sha }}
    author: ${{ github.actor }}
    branch: ${{ github.ref_name }}
    run_url: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
    fail_on_error: false
```

Quando o workflow reutilizavel e chamado de outro repositorio, o deploy faz **checkout versionado** de `YuriAPCarvalho/oracle-infra@v1` em `.ci-infra` e usa a action a partir desse path. A composite action local do caller **nao** e assumida.
