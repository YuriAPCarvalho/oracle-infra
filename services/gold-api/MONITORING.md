# Monitoring — ScriptGold

## Uptime Kuma

Monitors (inserted on VPS):

- ScriptGold API → `https://scriptgold.com.br/health`
- ScriptGold Admin → `https://adm.scriptgold.com.br/health`

UI via SSH tunnel: `ssh -L 3001:127.0.0.1:3001 ubuntu@129.146.161.65`

## Dozzle

Containers `gold-api` and `gold-admin` appear automatically.

## Host health

`make health` / `bash scripts/health.sh` includes both services and `/opt/docker/gold-api/auth_info`.
