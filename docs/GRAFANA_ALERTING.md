# Grafana Alerting + Discord

## Separação de responsabilidades

| Canal | Responsável | Webhook |
|-------|-------------|---------|
| Serviço/endpoint DOWN/UP | Uptime Kuma | `KUMA_DISCORD_WEBHOOK_URL` |
| Deploy/CI | GitHub Actions | `DISCORD_WEBHOOK_URL` |
| CPU/RAM/disco/scrape | Grafana Alerting | `GRAFANA_DISCORD_WEBHOOK_URL` (pode ser o mesmo do Kuma) |
| Bots (funcional) | por bot | próprio |

Nunca reutilizar o webhook de CI no Grafana.

## Provisionamento

Arquivos em [`compose/grafana/provisioning/alerting/`](../compose/grafana/provisioning/alerting/):

- `contact-points.yml` — Discord `discord-metrics` com `url: $GRAFANA_DISCORD_WEBHOOK_URL`
- `rules.yml` — regras iniciais (disco, memória, target down)

Se a variável não estiver no `.env`, o Compose usa um noop local (`http://127.0.0.1:1/...`) para o Grafana iniciar sem segredo. **Substitua** pela URL real na VPS antes de testar notificações.

## Regras Prometheus

[`compose/prometheus/rules/`](../compose/prometheus/rules/) avalia alertas no Prometheus (`ALERTS` metric). Discord é enviado pelo Grafana Unified Alerting (não há Alertmanager separado).

### Host (Prometheus + espelho Grafana)

- Disco warning 80%/10m · critical 90%/5m
- Memória disponível warning &lt;15%/10m · critical &lt;8%/5m
- Swap warning &gt;25%/15m
- Load (2 OCPU): warning load1&gt;2/10m · critical &gt;4/5m
- Inodes warning &gt;80%/10m
- TargetDown `up==0` por 5m

### Containers

Regras **conservadoras** apenas (memória perto do limit; restarts frequentes). Thresholds de CPU por container após baseline — evitar spam do Chromium.

## Teste controlado (sem spam)

Na VPS:

```bash
cd /opt/infra
bash scripts/grafana-seed-discord.sh --test
```

Isso grava o webhook em `compose/grafana/.env` (reusa o do Kuma se faltar), recria o Grafana e manda um teste no Discord.

Também: UI → Alerting → Contact points → **Test** em `discord-metrics`.

## Adicionar alerta por serviço

1. Preferir regra Prometheus em `rules/*.yml` + espelho Grafana se precisar Discord
2. Ou só regra Grafana em `provisioning/alerting/rules.yml`
3. Validar com `make validate-prometheus`
4. Reiniciar Prometheus/Grafana conforme o arquivo alterado
