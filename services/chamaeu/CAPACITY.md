# ChamaEu — gate de capacidade VPS

Host: `oracle-arm-free-218136` (`129.146.161.65`), ARM64, ~11 GiB RAM, ~97 GiB disco.

## Snapshot (2026-03-27)

| Container | RAM aprox. |
|-----------|------------|
| dailybot | 1.33 GiB |
| uptime-kuma | 125 MiB |
| gold-api | 124 MiB |
| gold-admin | 86 MiB |
| postgres | 35 MiB |
| traefik + ops | ~220 MiB |
| **Total em uso** | ~2.1 GiB |
| **Disponível** | ~9.3 GiB |

## Estimativa ChamaEu (+ WAHA + Redis)

| Novo serviço | RAM estimada |
|--------------|--------------|
| rankao-api | 300–500 MiB |
| rankao-web | 150–300 MiB |
| rankao-adm | 150–300 MiB |
| redis | 50–100 MiB |
| waha (GOWS) | ~80–250 MiB |
| **Delta** | ~1–2 GiB |

## Conclusão

**Aprovado para convivência** ScriptGold + bots + ChamaEu + Redis + WAHA na mesma VPS, desde que:

- **Uma única réplica** de `rankao-api` (cron + BullMQ).
- Monitorar RAM via `make health` / Uptime Kuma.
- Se RAM disponível < 15% sustentado, considerar `mem_limit` ou WAHA desligado fora de horário.

## Revalidação

```bash
docker stats --no-stream
free -h
make health
```
