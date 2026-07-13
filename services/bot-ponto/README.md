# Bot de Ponto

Estrutura documental para levantamento tecnico antes do deploy. Nenhum container deve ser criado ate que os requisitos reais sejam conhecidos.

## Informacoes Necessarias

- Repositorio.
- Linguagem e runtime.
- Comando de build.
- Comando de start.
- Necessidade de banco.
- Necessidade de armazenamento persistente.
- Existencia de API ou painel HTTP.
- Porta interna, se houver.
- Health endpoint, se houver.
- Agendamentos ou cron.
- Timezone.
- Tokens e segredos.
- Consumo esperado de CPU, RAM e disco.
- Estrategia de backup.
- Estrategia de rollback.
- Origem atual do servico.
- Dependencias externas.

## Decisoes Pendentes

- Se o bot precisa de rede `proxy` ou apenas `internal`.
- Se existe endpoint HTTP real para Uptime Kuma.
- Se dados locais entram no backup de `/opt/docker`.
- Como validar deploy e rollback sem perda de estado.
