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

# Grafana keeps admin secrets in .env — only ensure SERVICE_HOST.
GRAFANA_ENV="${INFRA}/compose/grafana/.env"
if [[ ! -f "${GRAFANA_ENV}" ]]; then
  echo "ERRO: Missing ${GRAFANA_ENV}; create from .env.example first." >&2
  exit 1
fi
if grep -q '^SERVICE_HOST=' "${GRAFANA_ENV}"; then
  sed -i 's|^SERVICE_HOST=.*|SERVICE_HOST=grafana.chamaeu.app|' "${GRAFANA_ENV}"
else
  printf '\nSERVICE_HOST=grafana.chamaeu.app\n' >> "${GRAFANA_ENV}"
fi
chmod 600 "${GRAFANA_ENV}"

cd "$INFRA"
for svc in uptime-kuma dozzle portainer traefik grafana; do
  echo "==> $svc"
  docker compose -f "compose/${svc}/compose.yml" up -d --force-recreate
done

echo "OK — aguarde ACME e teste Access nos subdomínios (incl. grafana.chamaeu.app)."
