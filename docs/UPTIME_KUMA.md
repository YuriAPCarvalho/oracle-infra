# Uptime Kuma

Monitoramento HTTP da stack de infra na **VPS Oracle**.

Gestor Agro (Marca7) roda em outro servidor — não incluir monitores `marca7-*` nesta instância. Ver [GESTOR_AGRO.md](GESTOR_AGRO.md) / [MARCA7_TECH_DNS_ACCESS.md](MARCA7_TECH_DNS_ACCESS.md).

## Acesso

Bind localhost: `127.0.0.1:8082` → container `:3001`.

```bash
ssh -i <key> -L 8082:127.0.0.1:8082 ubuntu@<VPS_IP>
```

UI: `http://127.0.0.1:8082`

## Monitores da infra (Oracle)

Após criar o usuário admin na UI, rode:

```bash
cd /opt/infra
bash scripts/uptime-kuma-seed-monitors.sh
```

Monitores criados pelo seed (rede Docker `proxy` + URLs públicas ScriptGold):

| Nome | URL | Notas |
|------|-----|--------|
| `traefik` | `http://traefik:8080/api/overview` | API do dashboard |
| `portainer` | `https://portainer:9443/api/status` | TLS self-signed (`ignore_tls`) |
| `dozzle` | `http://dozzle:8080` | UI de logs |
| `gold-api` | `https://scriptgold.com.br/health` | ScriptGold API |
| `gold-admin` | `https://adm.scriptgold.com.br/health` | ScriptGold Admin |

Monitores **Push** (bots) são criados na UI ou pelo app (`KUMA_PUSH_URL` em `dailybot` / `bot-ponto`).

Se os nomes na UI forem diferentes (ex.: `Traefik HTTP`, `ScriptGold API`), use `KUMA_MONITOR_NAMES` ao rodar o seed Discord (ver abaixo).

O script é idempotente: não duplica monitores com o mesmo nome.

## Discord (DOWN / UP)

Alertas só quando um monitor **cai** ou **volta** — não a cada heartbeat OK.

1. Copie o example e preencha o webhook **somente na VPS** (nunca no Git):

```bash
cp compose/uptime-kuma/.env.example compose/uptime-kuma/.env
chmod 600 compose/uptime-kuma/.env
# edite: KUMA_DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

2. Rode o seed (monitores com nomes customizados na UI):

```bash
# opcional, se os nomes na UI não forem traefik/portainer/dozzle/gold-api/gold-admin:
export KUMA_MONITOR_NAMES="Traefik HTTP,Portainer,Dozzle,ScriptGold API,ScriptGold Admin,Bot Ponto,Daily Bot Discord"

bash scripts/uptime-kuma-seed-discord.sh
```

Isso cria/atualiza a notificação `discord-infra` e associa aos monitores listados.

**Não** reutilize o webhook de CI/CD (`DISCORD_WEBHOOK_URL` do GitHub Actions). Se uma URL de webhook vazou em chat/log, rotacione no Discord e atualize só o `.env` da VPS.

Ver também [NOTIFICATIONS.md](NOTIFICATIONS.md).

## Verificação (somente leitura)

```bash
bash scripts/uptime-kuma-verify-notifications.sh
```

## Porta

Host publicado: **8082** (não 3001). Compose: [`compose/uptime-kuma/compose.yml`](../compose/uptime-kuma/compose.yml).
