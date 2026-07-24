#!/usr/bin/env bash
# One-time: switch Marca7 app/api to :latest and start Watchtower (pull-based deploy).
# Run on the VPS from /opt/infra (or set INFRA_ROOT).
set -Eeuo pipefail

INFRA_ROOT="${INFRA_ROOT:-/opt/infra}"
cd "${INFRA_ROOT}"

APP_IMAGE_DEFAULT="ghcr.io/marca7-tech/marca7-gestor-agro-app:latest"
API_IMAGE_DEFAULT="ghcr.io/marca7-tech/marca7-gestor-agro-api:latest"

ensure_latest() {
  local env_file="$1"
  local default_image="$2"
  if [[ ! -f "${env_file}" ]]; then
    echo "ERROR: missing ${env_file}" >&2
    exit 1
  fi
  if grep -qE '^SERVICE_IMAGE=.*:sha-' "${env_file}"; then
    echo "Updating ${env_file} SERVICE_IMAGE -> ${default_image}"
    sed -i.bak -E "s|^SERVICE_IMAGE=.*|SERVICE_IMAGE=${default_image}|" "${env_file}"
  elif ! grep -qE '^SERVICE_IMAGE=.+:latest$' "${env_file}"; then
    echo "WARN: ${env_file} SERVICE_IMAGE is not :latest — set manually if needed:"
    grep -E '^SERVICE_IMAGE=' "${env_file}" || true
  else
    echo "OK ${env_file} already uses :latest"
  fi
}

echo "==> Ensuring mutable SERVICE_IMAGE tags"
ensure_latest "compose/marca7-app/.env" "${APP_IMAGE_DEFAULT}"
ensure_latest "compose/marca7-api/.env" "${API_IMAGE_DEFAULT}"

echo "==> Recreating marca7-app / marca7-api (Watchtower labels + :latest)"
docker compose -f compose/marca7-app/compose.yml up -d
docker compose -f compose/marca7-api/compose.yml up -d

echo "==> Starting Watchtower"
docker compose -f compose/watchtower/compose.yml up -d

echo "==> Done. Check: docker logs --tail 50 watchtower"
