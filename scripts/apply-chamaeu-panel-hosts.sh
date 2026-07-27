#!/usr/bin/env bash
# Aplica SERVICE_HOST chamaeu.app nos painéis e recria containers.
set -Eeuo pipefail
INFRA=/opt/infra
write_env() {
  local dir="$1" host="$2"
  printf 'SERVICE_HOST=%s\n' "$host" > "${INFRA}/compose/${dir}/.env"
  chmod 600 "${INFRA}/compose/${dir}/.env"
}

write_env uptime-kuma uptimekuma.chamaeu.app
write_env dozzle dozzle.chamaeu.app
write_env portainer portainer.chamaeu.app
write_env traefik traefik.chamaeu.app

cd "$INFRA"
for svc in uptime-kuma dozzle portainer traefik; do
  echo "==> $svc"
  docker compose -f "compose/${svc}/compose.yml" up -d --force-recreate
done

echo "OK — aguarde ACME e teste Access nos subdomínios."
