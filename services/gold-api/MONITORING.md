# Monitoring — ScriptGold

## Uptime Kuma

Monitors (inserted on VPS):

- ScriptGold API → `https://scriptgold.com.br/health`
- ScriptGold Admin → `https://adm.scriptgold.com.br/health`

UI via SSH tunnel: `ssh -L 8082:127.0.0.1:8082 ubuntu@129.146.161.65`

## Dozzle

Containers `gold-api` and `gold-admin` appear automatically.

## Host health

`make health` / `bash scripts/health.sh` includes both services and `/opt/docker/applications/gold-api/auth_info`.
