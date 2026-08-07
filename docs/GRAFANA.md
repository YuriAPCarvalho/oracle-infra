# Grafana

Dashboards e UI de métricas. **Somente localhost + túnel SSH** — sem Traefik, sem domínio, sem HTTPS público.

## Acesso

Bind: `127.0.0.1:3000`

```powershell
ssh -i "$HOME\.ssh\id_rsa" `
  -L 3000:127.0.0.1:3000 `
  ubuntu@<VPS_HOST>
```

Abrir `http://127.0.0.1:3000` no Windows.

## Segurança

Configurado via `compose/grafana/.env` (não versionado):

| Variável | Uso |
|----------|-----|
| `GF_SECURITY_ADMIN_USER` | Admin |
| `GF_SECURITY_ADMIN_PASSWORD` | Senha (fora do Git) |
| `GRAFANA_DISCORD_WEBHOOK_URL` | Opcional — ver [GRAFANA_ALERTING.md](GRAFANA_ALERTING.md) |

Também:

- cadastro público desabilitado
- anônimo desabilitado
- analytics/reporting desabilitados
- plugins não assinados não liberados
- persistência em `/opt/docker/grafana/data` (UID `472`)

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
