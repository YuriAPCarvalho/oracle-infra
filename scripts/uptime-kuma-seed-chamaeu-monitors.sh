#!/usr/bin/env bash
# Seed Uptime Kuma HTTP monitors for ChamaEu (public, internal origin, TLS, optional WAHA).
# Idempotent: skips monitors that already exist by name.
#
# Usage (on the VPS, after Kuma admin exists):
#   bash scripts/uptime-kuma-seed-chamaeu-monitors.sh
#
# Called automatically from uptime-kuma-seed-monitors.sh (same DB write window).
#
# WAHA monitors (need X-Api-Key header):
#   KUMA_SEED_WAHA_MONITORS=auto   — default: seed if compose/waha/.env has WAHA_API_KEY
#   KUMA_SEED_WAHA_MONITORS=true   — force
#   KUMA_SEED_WAHA_MONITORS=false  — skip

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DATA_DIR="${DATA_ROOT}/uptime-kuma/data"
DB_FILE="${DATA_DIR}/kuma.db"
COMPOSE_FILE="$(service_compose_file uptime-kuma)"
WAHA_ENV_FILE="${PROJECT_ROOT}/compose/waha/.env"

sql_escape() {
  local s="${1-}"
  s="${s//\'/\'\'}"
  printf '%s' "${s}"
}

json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

load_env_file() {
  local file="$1"
  local line key value

  [[ -f "${file}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    if [[ -z "${!key+x}" ]]; then
      export "${key}=${value}"
    fi
  done < "${file}"
}

sqlite_exec() {
  local sql="$1"
  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "${DB_FILE}" "${sql}"
  else
    docker run --rm \
      -v "${DATA_DIR}:/data" \
      --entrypoint sqlite3 \
      louislam/uptime-kuma:1 \
      /data/kuma.db "${sql}"
  fi
}

monitor_exists() {
  local name_sql
  name_sql="$(sql_escape "$1")"
  local count
  count="$(sqlite_exec "SELECT COUNT(*) FROM monitor WHERE name = '${name_sql}';")"
  [[ "${count}" -gt 0 ]]
}

# insert_http_monitor name url ignore_tls interval maxretries keyword headers timeout expiry_notification
insert_http_monitor() {
  local name="$1"
  local url="$2"
  local ignore_tls="${3:-0}"
  local interval="${4:-60}"
  local maxretries="${5:-3}"
  local keyword="${6:-}"
  local headers="${7:-}"
  local timeout="${8:-15}"
  local expiry_notification="${9:-1}"

  local name_sql url_sql keyword_sql headers_sql
  name_sql="$(sql_escape "${name}")"
  url_sql="$(sql_escape "${url}")"
  keyword_sql="$(sql_escape "${keyword}")"

  if monitor_exists "${name}"; then
    ok "monitor already exists: ${name}"
    return 0
  fi

  if [[ -n "${headers}" ]]; then
    headers_sql="'$(sql_escape "${headers}")'"
  else
    headers_sql="NULL"
  fi

  sqlite_exec "INSERT INTO monitor (
      name, active, user_id, interval, url, type, weight,
      ignore_tls, upside_down, maxretries, maxredirects,
      accepted_statuscodes_json, retry_interval, method, timeout,
      keyword, headers, expiry_notification, invert_keyword
    ) VALUES (
      '${name_sql}', 1, 1, ${interval}, '${url_sql}', 'http', 2000,
      ${ignore_tls}, 0, ${maxretries}, 10,
      '[\"200-299\"]', 60, 'GET', ${timeout},
      '${keyword_sql}', ${headers_sql}, ${expiry_notification}, 0
    );"
  ok "created monitor: ${name} -> ${url}"
}

should_seed_waha_monitors() {
  local mode="${KUMA_SEED_WAHA_MONITORS:-auto}"
  case "${mode}" in
    true | 1 | yes)
      return 0
      ;;
    false | 0 | no)
      return 1
      ;;
    auto | "")
      load_env_file "${WAHA_ENV_FILE}"
      [[ -n "${WAHA_API_KEY:-}" ]]
      ;;
    *)
      warn "unknown KUMA_SEED_WAHA_MONITORS=${mode}, treating as auto"
      load_env_file "${WAHA_ENV_FILE}"
      [[ -n "${WAHA_API_KEY:-}" ]]
      ;;
  esac
}

seed_chamaeu_monitors() {
  section "Uptime Kuma — seed ChamaEu monitors"

  # P0 — public (Cloudflare + Traefik + app)
  insert_http_monitor "chamaeu-api-health" \
    "https://api.chamaeu.app/health" 0 60 3 '"status":"ok"' "" 15 0
  insert_http_monitor "chamaeu-web" "https://chamaeu.app/" 0 120 3 "" "" 15 0
  insert_http_monitor "chamaeu-adm" "https://adm.chamaeu.app/" 0 120 3 "" "" 15 0

  # P3 — TLS expiry (daily check; expiry_notification alerts ~30d default in Kuma)
  insert_http_monitor "chamaeu-api-tls" "https://api.chamaeu.app" 0 86400 1 "" "" 30 1
  insert_http_monitor "chamaeu-web-tls" "https://chamaeu.app" 0 86400 1 "" "" 30 1
  insert_http_monitor "chamaeu-adm-tls" "https://adm.chamaeu.app" 0 86400 1 "" "" 30 1

  # P1 — Docker origin (proxy network)
  insert_http_monitor "chamaeu-api-internal" \
    "http://rankao-api:3000/health" 0 60 3 '"status":"ok"' "" 10 0
  insert_http_monitor "chamaeu-web-internal" "http://rankao-web:3000/" 0 120 3 "" "" 15 0
  insert_http_monitor "chamaeu-adm-internal" "http://rankao-adm:3000/" 0 120 3 "" "" 15 0

  if should_seed_waha_monitors; then
    load_env_file "${WAHA_ENV_FILE}"
    if [[ -z "${WAHA_API_KEY:-}" ]]; then
      warn "KUMA_SEED_WAHA_MONITORS requested but WAHA_API_KEY missing in ${WAHA_ENV_FILE}"
    else
      local headers_json
      headers_json="$(printf '{"X-Api-Key":"%s"}' "$(json_escape "${WAHA_API_KEY}")")"
      insert_http_monitor "chamaeu-waha-server" \
        "http://waha:3000/api/server/status" 0 120 2 "" "${headers_json}" 10 0
      insert_http_monitor "chamaeu-waha-session" \
        "http://waha:3000/api/sessions" 0 120 2 "WORKING" "${headers_json}" 10 0
    fi
  else
    info "Skipping WAHA monitors (set KUMA_SEED_WAHA_MONITORS=true or add WAHA_API_KEY to compose/waha/.env)"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_command docker

  if [[ ! -f "${DB_FILE}" ]]; then
    die "Uptime Kuma database not found: ${DB_FILE} (start the service first)"
  fi

  info "Stopping uptime-kuma for safe DB write"
  docker compose -f "${COMPOSE_FILE}" stop

  if command -v sqlite3 >/dev/null 2>&1; then
    sqlite3 "${DB_FILE}" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
  fi

  USER_COUNT="$(sqlite_exec "SELECT COUNT(*) FROM user;")"
  if [[ "${USER_COUNT}" -lt 1 ]]; then
    docker compose -f "${COMPOSE_FILE}" start
    die "No Uptime Kuma user found. Create the admin in the UI first, then re-run."
  fi

  seed_chamaeu_monitors

  info "Starting uptime-kuma"
  docker compose -f "${COMPOSE_FILE}" start
  sleep 2
  docker compose -f "${COMPOSE_FILE}" ps

  section "ChamaEu monitors"
  sqlite_exec "SELECT id, name, interval, url FROM monitor WHERE name LIKE 'chamaeu-%' ORDER BY name;"

  ok "Done."
fi
