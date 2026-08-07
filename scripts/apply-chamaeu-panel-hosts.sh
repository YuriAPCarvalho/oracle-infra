#!/usr/bin/env bash
# Aplica SERVICE_HOST chamaeu.app nos painéis e recria containers.
set -Eeuo pipefail
INFRA=/opt/infra

upsert_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  touch "${file}"
  chmod 600 "${file}"
  tmp="$(mktemp)"
  if grep -qE "^${key}=" "${file}" 2>/dev/null; then
    sed "s|^${key}=.*|${key}=${value}|" "${file}" >"${tmp}"
  else
    cat "${file}" >"${tmp}"
    printf '\n%s=%s\n' "${key}" "${value}" >>"${tmp}"
  fi
  mv "${tmp}" "${file}"
  chmod 600 "${file}"
}

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
upsert_env_var "${GRAFANA_ENV}" "SERVICE_HOST" "grafana.chamaeu.app"

# MinIO keeps root credentials — only upsert hosts/URLs.
MINIO_ENV="${INFRA}/compose/minio/.env"
if [[ ! -f "${MINIO_ENV}" ]]; then
  echo "ERRO: Missing ${MINIO_ENV}; create from .env.example with MINIO_ROOT_* first." >&2
  exit 1
fi
upsert_env_var "${MINIO_ENV}" "SERVICE_HOST" "s3.chamaeu.app"
upsert_env_var "${MINIO_ENV}" "CONSOLE_HOST" "minio.chamaeu.app"
upsert_env_var "${MINIO_ENV}" "MINIO_SERVER_URL" "https://s3.chamaeu.app"
upsert_env_var "${MINIO_ENV}" "MINIO_BROWSER_REDIRECT_URL" "https://minio.chamaeu.app"
upsert_env_var "${MINIO_ENV}" "MINIO_BUCKET" "chamaeu"

cd "$INFRA"
for svc in uptime-kuma dozzle portainer traefik grafana minio; do
  echo "==> $svc"
  docker compose -f "compose/${svc}/compose.yml" up -d --force-recreate
done

echo "OK — aguarde ACME e teste Access (painel minio.chamaeu.app) / S3 (s3.chamaeu.app)."
