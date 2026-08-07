# Grafana

Dashboards e UI de métricas.

## Acesso

| Modo | URL |
|------|-----|
| Cloudflare Access (recomendado) | `https://grafana.chamaeu.app` |
| Fallback SSH | `127.0.0.1:3000` via túnel |

```powershell
ssh -i "$HOME\.ssh\id_rsa" `
  -L 3000:127.0.0.1:3000 `
  ubuntu@<VPS_HOST>
```

Painel público: mesmo padrão dos outros painéis ChamaEu (DNS proxied → Traefik → origin + Zero Trust Access). Ver [chamaeu/CLOUDFLARE_ACCESS.md](chamaeu/CLOUDFLARE_ACCESS.md).

## Segurança

Configurado via `compose/grafana/.env` (não versionado):

| Variável | Uso |
|----------|-----|
| `SERVICE_HOST` | Host Traefik (`grafana.chamaeu.app`) |
| `GF_SECURITY_ADMIN_USER` | Admin |
| `GF_SECURITY_ADMIN_PASSWORD` | Senha (fora do Git) |
| `GRAFANA_DISCORD_WEBHOOK_URL` | Opcional — ver [GRAFANA_ALERTING.md](GRAFANA_ALERTING.md) |

Também:

- cadastro público desabilitado
- anônimo desabilitado
- analytics/reporting desabilitados
- plugins não assinados não liberados
- cookie secure (HTTPS)
- persistência em `/opt/docker/monitoring/grafana/data` (UID `472`)
- redes `monitoring` (Prometheus) + `proxy` (Traefik)

Copiar de [`compose/grafana/.env.example`](../compose/grafana/.env.example).

## Provisionamento

| Path | Conteúdo |
|------|----------|
| `provisioning/datasources/` | Prometheus (`http://prometheus:9090`) default |
| `provisioning/dashboards/json/` | Host + Containers (versionados) |
| `provisioning/alerting/` | Contact point Discord + regras iniciais |

### Dashboards

- **Host metrics** (`oracle-host-metrics`) — CPU, load, RAM, swap, disco, inodes, rede, uptime, I/O
- **Container metrics** (`oracle-container-metrics`) — CPU/RAM/rede/fs/throttling por container, top consumers

Origem: dashboards enxutos criados neste repositório (sem download dinâmico). Licença: mesmo repositório.

`container_fs_*` depende do cAdvisor; se ausente no overlayfs, o painel de filesystem de container pode ficar vazio — disco do host continua no dashboard Host.

## Bootstrap

```bash
cp compose/grafana/.env.example compose/grafana/.env
# editar usuário/senha
bash bootstrap/10-grafana.sh
```

## Update / rollback

```bash
make update
# ou
make restart SERVICE=grafana
```

Rollback: pin de imagem anterior em `compose/grafana/compose.yml` + `up -d`.
