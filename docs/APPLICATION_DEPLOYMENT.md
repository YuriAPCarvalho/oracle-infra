# Application Deployment

Fluxo oficial para futuras aplicacoes.

```text
desenvolvimento local
-> testes
-> commit
-> push
-> GitHub Actions
-> build da imagem
-> publicacao da imagem
-> atualizacao controlada na VPS
-> health check
-> validacao
-> rollback se necessario
```

## Principios

- A VPS nao e ambiente de desenvolvimento.
- Arquivos nao devem ser editados manualmente em `/opt/infra`.
- Alteracoes entram por Git.
- Dados persistentes ficam em `/opt/docker/<service>`.
- Segredos nao entram no Git.
- `.env` permanece apenas na VPS ou em gerenciador de segredos.
- Cada servico tera seu proprio Compose.
- Banco nao deve ser criado sem requisito real.
- Portas nao serao expostas sem necessidade.
- Bots sem interface HTTP devem ficar apenas na rede `internal`.
- Traefik sera usado apenas quando houver endpoint HTTP real.
- Cada aplicacao devera ter rollback documentado.

## Padrao de Compose

Use `templates/docker-service/` como ponto de partida. O template nao e uma aplicacao de producao; ele existe para manter consistencia de seguranca, redes, persistencia e healthcheck.

## Deploy Controlado

1. Validar imagem e Compose em ambiente local ou CI.
2. Publicar imagem versionada.
3. Atualizar o Compose pelo Git.
4. Executar `make validate`.
5. Aplicar na VPS com fluxo documentado.
6. Conferir logs e health check.
7. Registrar rollback.

## Rollback

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
