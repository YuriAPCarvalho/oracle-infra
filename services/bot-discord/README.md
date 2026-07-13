# Bot do Discord

Estrutura documental para levantamento tecnico antes do deploy. Nenhum container deve ser criado ate que os requisitos reais sejam conhecidos.

## Informacoes Necessarias

- Repositorio.
- Linguagem e runtime.
- Comando de build.
- Comando de start.
- Token do Discord.
- Intents necessarios.
- Application ID.
- Guild IDs, caso existam.
- Comandos slash.
- Banco ou persistencia.
- Arquivos locais.
- Healthcheck.
- Reconexao.
- Rate limits.
- Logs.
- Estrategia de atualizacao.
- Estrategia de rollback.
- Necessidade ou nao de interface HTTP.
- Consumo esperado de CPU, RAM e disco.

## Seguranca

O token do Discord e segredo critico. Se for exposto em log, Git, issue, terminal compartilhado ou backup inseguro, deve ser rotacionado imediatamente.

## Decisoes Pendentes

- Se o bot precisa de rede `proxy` ou apenas `internal`.
- Se existe endpoint HTTP real para Uptime Kuma.
- Como monitorar heartbeat ou ausencia de eventos.
- Como validar deploy e rollback sem derrubar sessoes ativas.
