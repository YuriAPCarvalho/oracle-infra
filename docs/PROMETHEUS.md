# Prometheus

Scrape e retenção de métricas na rede `monitoring`.

## Compose

[`compose/prometheus/`](../compose/prometheus/)

- Imagem: `prom/prometheus:v3.2.1`
- Sem porta publicada no host
- Config versionada: `prometheus.yml` + `rules/*.yml`
- Dados: `/opt/docker/monitoring/prometheus/data` (owner `65534:65534`)

## Scrape jobs

| Job | Target |
|-----|--------|
| `prometheus` | `localhost:9090` |
| `node-exporter` | `node-exporter:9100` |
| `cadvisor` | `cadvisor:8080` |

Intervalo: 15s · evaluation: 15s · timeout: 10s.

## Retenção

```text
--storage.tsdb.retention.time=15d
--storage.tsdb.retention.size=5GB
```

Quando qualquer limite é atingido, Prometheus remove blocos antigos. A TSDB **não** deve poder encher o disco inteiro (cap 5 GB).

### Estimativa e medição

Com ~15s de scrape em host + dezenas de séries de containers, 5 GB / 15 dias é conservador nesta VPS (~41 GB livres observados em 2026-08).

```bash
du -sh /opt/docker/monitoring/prometheus/data
docker run --rm --network monitoring curlimages/curl:8.12.1 \
  -fsS 'http://prometheus:9090/api/v1/status/tsdb'
```

Para alterar: editar `compose/prometheus/compose.yml` → `git pull` → `make restart SERVICE=prometheus`.

## Admin API

**Desabilitada** (`--web.enable-admin-api` não é usado). Snapshots administrativos não estão disponíveis.

## Backup

O backup operacional copia `/opt/docker` com containers ativos. A TSDB pode ficar **inconsistente** se o Prometheus estiver escrevendo.

**Estratégia adotada:** métricas históricas são **não críticas** e reconstruíveis após o restore (scrape recomeça do zero útil). Grafana (dashboards/alertas/usuários) é o dado persistente crítico desta stack.

Não habilitar Admin API só para snapshot sem documentar o risco de exposição.

## Diagnóstico

```bash
docker run --rm --network monitoring curlimages/curl:8.12.1 \
  -fsS http://prometheus:9090/-/ready
docker run --rm --network monitoring curlimages/curl:8.12.1 \
  -fsS http://prometheus:9090/api/v1/targets | head
```

## Novos scrape targets

1. Adicionar job em `compose/prometheus/prometheus.yml`
2. Garantir que o alvo está na rede `monitoring`
3. `make restart SERVICE=prometheus`
4. Validar target `UP`

## Validação

```bash
make validate-prometheus
```
