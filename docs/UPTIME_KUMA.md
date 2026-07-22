# Uptime Kuma

Monitoramento HTTP da stack de infra.

## Acesso

Bind localhost: `127.0.0.1:8082` → container `:3001`.

```bash
ssh -i <key> -L 8082:127.0.0.1:8082 ubuntu@<VPS_IP>
```

UI: `http://127.0.0.1:8082`

## Monitores da infra

Após criar o usuário admin na UI, rode:

```bash
cd /opt/infra
bash scripts/uptime-kuma-seed-monitors.sh
```

Monitores criados (rede Docker `proxy`):

| Nome | URL | Notas |
|------|-----|--------|
| `traefik` | `http://traefik:8080/api/overview` | API do dashboard |
| `portainer` | `https://portainer:9443/api/status` | TLS self-signed (`ignore_tls`) |
| `dozzle` | `http://dozzle:8080` | UI de logs |

O script é idempotente: não duplica monitores com o mesmo nome.

## Porta

Host publicado: **8082** (não 3001). Compose: [`compose/uptime-kuma/compose.yml`](../compose/uptime-kuma/compose.yml).
