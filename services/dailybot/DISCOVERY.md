# DailyBot — Discovery (migração VPS)

## Resumo

| Item | Valor |
|------|--------|
| Repo | `https://github.com/YuriAPCarvalho/DailyBot.git` |
| Runtime | Node >= 22, Discord.js 14, Prisma 6, Playwright 1.61 |
| HTTP | Não (web dashboard removida) |
| Monitoramento | Uptime Kuma **Push** (`KUMA_PUSH_URL` na rede `proxy`) |
| Banco | Postgres compartilhado (`dailybot`) |
| Egress | Sim — Discord Gateway/API + GLPI HTTPS |
| Traefik | Não |
| Dados | `/opt/docker/dailybot/storage` |
| Imagem | `Dockerfile.bot` → `dailybot:local` / GHCR futuro |

## Decisões

- Remover `@dailybot/web` do monorepo
- Dump Railway → restore VPS (cutover com histórico)
- Postgres único em `internal`; app cria DBs via `postgres-create-db.sh`
- Bot em `dailybot-net` + `internal` (+ `proxy` para Push Kuma)
- Railway desligado após validação

## Critérios de pronto (experimental → estável)

1. Postgres healthy; dump restaurado; `_prisma_migrations` OK
2. Bot healthy/logs: Discord ready; schedulers ok
3. Smoke Playwright ARM64
4. Slash commands registrados
5. (Opcional) ciclo GLPI sem crash de session
6. Kuma Push ok — monitor Push (~180s) + `KUMA_PUSH_URL` + bot enviando heartbeat a cada ~60s enquanto Discord ready (não usar HTTP/TCP)
7. Railway parado
