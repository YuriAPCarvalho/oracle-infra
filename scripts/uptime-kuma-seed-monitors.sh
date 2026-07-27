#!/usr/bin/env bash
# Seed HTTP monitors for Traefik, Portainer and Dozzle in Uptime Kuma.
# Safe to re-run: skips monitors that already exist by name.
#
# Usage (on the VPS):
#   bash scripts/uptime-kuma-seed-monitors.sh
#
# Requires: docker, sqlite3 (host or inside the uptime-kuma container).

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DATA_DIR="${DATA_ROOT}/uptime-kuma/data"
DB_FILE="${DATA_DIR}/kuma.db"
COMPOSE_FILE="$(service_compose_file uptime-kuma)"

require_command docker

if [[ ! -f "${DB_FILE}" ]]; then
  die "Uptime Kuma database not found: ${DB_FILE} (start the service first)"
fi

sqlite_exec() {
  local sql="$1"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "${DB_FILE}" "${sql}"
  else
    # Use the same image as the service (ships sqlite3); volume must not be locked.
    docker run --rm \
      -v "${DATA_DIR}:/data" \
      --entrypoint sqlite3 \
      louislam/uptime-kuma:1 \
      /data/kuma.db "${sql}"
  fi
}

monitor_exists() {
  local name="$1"
  local count
  count="$(sqlite_exec "SELECT COUNT(*) FROM monitor WHERE name = '${name}';")"
  [[ "${count}" -gt 0 ]]
}

insert_http_monitor() {
  local name="$1"
  local url="$2"
  local ignore_tls="$3"

  if monitor_exists "${name}"; then
    ok "monitor already exists: ${name}"
    return 0
  fi

  sqlite_exec "INSERT INTO monitor (
      name, active, user_id, interval, url, type, weight,
      ignore_tls, upside_down, maxretries, maxredirects,
      accepted_statuscodes_json, retry_interval, method, timeout
    ) VALUES (
      '${name}', 1, 1, 60, '${url}', 'http', 2000,
      ${ignore_tls}, 0, 2, 10,
      '[\"200-299\"]', 60, 'GET', 0
    );"
  ok "created monitor: ${name} -> ${url}"
}

section "Uptime Kuma — seed infra monitors"

info "Stopping uptime-kuma for safe DB write"
docker compose -f "${COMPOSE_FILE}" stop

# Flush WAL into main DB if present
if command -v sqlite3 >/dev/null 2>&1; then
  sqlite3 "${DB_FILE}" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
fi

USER_COUNT="$(sqlite_exec "SELECT COUNT(*) FROM user;")"
if [[ "${USER_COUNT}" -lt 1 ]]; then
  docker compose -f "${COMPOSE_FILE}" start
  die "No Uptime Kuma user found. Create the admin in the UI first, then re-run."
fi

insert_http_monitor "traefik" "http://traefik:8080/api/overview" 0
insert_http_monitor "portainer" "https://portainer:9443/api/status" 1
insert_http_monitor "dozzle" "http://dozzle:8080" 0
# ScriptGold (Oracle VPS) — public HTTPS endpoints
insert_http_monitor "gold-api" "https://scriptgold.com.br/health" 0
insert_http_monitor "gold-admin" "https://adm.scriptgold.com.br/health" 0

info "Starting uptime-kuma"
docker compose -f "${COMPOSE_FILE}" start

sleep 2
docker compose -f "${COMPOSE_FILE}" ps

section "Monitors"
sqlite_exec "SELECT id, name, type, url, ignore_tls FROM monitor ORDER BY id;"

ok "Done. Open Uptime Kuma UI (http://127.0.0.1:8082 via SSH tunnel) to confirm."
