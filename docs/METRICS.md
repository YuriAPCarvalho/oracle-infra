# Metrics stack (Oracle VPS)

Métricas históricas da VPS e dos containers Docker. Complementa Uptime Kuma (disponibilidade) e Dozzle (logs).

## Responsabilidades

| Ferramenta | Papel |
|------------|--------|
| Uptime Kuma | Serviço/endpoint UP/DOWN |
| Dozzle | Logs em tempo real |
| Node Exporter | Métricas do host |
| cAdvisor | Métricas por container |
| Prometheus | Scrape, retenção, regras |
| Grafana | Dashboards + alertas de recurso → Discord |
| Oracle `unified-monitoring-agent` | Telemetria da cloud Oracle — **não** substitui esta stack |

## Arquitetura

- Rede Docker externa: `monitoring` (exporters ↔ Prometheus ↔ Grafana)
- Grafana também na rede `proxy` (Traefik) → `https://grafana.chamaeu.app` + Cloudflare Access
- Exporters e Prometheus: **sem** portas no host
- Grafana: `127.0.0.1:3000` (fallback SSH) + Traefik público protegido por Access

```text
Windows --SSH -L 3000-- > VPS:3000 (Grafana)
Grafana --> Prometheus:9090
Prometheus --> node-exporter:9100
Prometheus --> cadvisor:8080
Prometheus --> traefik:8082
Prometheus --> postgres-exporter:9187
Prometheus --> redis-exporter:9121
Prometheus --> minio:9000 (/minio/v2/metrics/cluster)
```

## Bootstrap

```bash
cd /opt/infra
# redes (inclui monitoring) se necessário:
# sudo bash bootstrap/02-docker.sh
bash bootstrap/07-node-exporter.sh
bash bootstrap/08-cadvisor.sh
bash bootstrap/09-prometheus.sh
# criar compose/grafana/.env a partir do .env.example
bash bootstrap/10-grafana.sh
bash bootstrap/11-postgres-exporter.sh   # gera DSN a partir do Postgres .env
bash bootstrap/12-redis-exporter.sh
```

Ou `bash bootstrap/bootstrap.sh` (painéis 03–06 + métricas 07–12).

## Imagens (ARM64)

| Serviço | Imagem |
|---------|--------|
| Node Exporter | `prom/node-exporter:v1.9.1` |
| cAdvisor | `ghcr.io/google/cadvisor:0.56.2` |
| Prometheus | `prom/prometheus:v3.2.1` |
| Grafana | `grafana/grafana:11.6.0` |
| Postgres exporter | `quay.io/prometheuscommunity/postgres-exporter:v0.17.1` |
| Redis exporter | `oliver006/redis_exporter:v1.67.0` |

## Persistência

| Path | Conteúdo |
|------|----------|
| `/opt/docker/prometheus/data` | TSDB (UID 65534) |
| `/opt/docker/grafana/data` | DB/config Grafana (UID 472) |

Node Exporter e cAdvisor não precisam de dados persistentes.

## Node Exporter collectors

Habilitados (defaults úteis): cpu, meminfo, diskstats, filesystem, loadavg, netdev, netstat, softnet, pressure, time, uname, etc.

Desabilitados neste host: `wifi`, `hwmon`, `infiniband`, `fibrechannel`, `ipvs`, `btrfs`, `zfs`, `nfs`, `nfsd`, `xfs`.

Mount-points de Docker/containerd excluídos do collector filesystem.

Limites não aplicados de forma rígida no Compose até medição pós-deploy. Orçamento alvo: Node Exporter ≤128 MB, cAdvisor ≤512 MB, Prometheus ≤1.5 GB, Grafana ≤768 MB. Margem para bot Playwright ~1.5 GB em 12 GB.

## Dashboards Grafana

Pasta **Oracle Infra**:

| Dashboard | Conteúdo |
|-----------|----------|
| Host metrics | CPU, load, memória, disco, rede, PSI, FD/sockets, disk util/await |
| Container metrics | CPU/RAM/rede/disco por container, restarts, PSI, idade |
| Data layer | Postgres (conexões, tamanho, locks, txs) + Redis (mem, hit ratio, keys) |
| Edge (Traefik) | req/s, 4xx/5xx, latência p50/p95, bytes |
| MinIO | scrape up, capacidade, objetos, tráfego S3, bucket usage |

Alertas Discord: disco/memória/iowait/conntrack/scrape — ver [GRAFANA_ALERTING.md](GRAFANA_ALERTING.md).

- [PROMETHEUS.md](PROMETHEUS.md)
- [GRAFANA.md](GRAFANA.md)
- [GRAFANA_ALERTING.md](GRAFANA_ALERTING.md)
- [OPERATIONS.md](OPERATIONS.md)
- [BACKUP.md](BACKUP.md) / [RESTORE.md](RESTORE.md)

## Troubleshooting rápido

```bash
docker network inspect monitoring
make logs SERVICE=cadvisor
make logs SERVICE=prometheus
docker run --rm --network monitoring curlimages/curl:8.12.1 -fsS http://prometheus:9090/api/v1/targets
```
