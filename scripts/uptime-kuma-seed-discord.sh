#!/usr/bin/env bash
# Seed Discord notification for infra monitors in Uptime Kuma.
# Reads KUMA_DISCORD_WEBHOOK_URL from the environment or compose/uptime-kuma/.env.
# Idempotent: creates/updates notification "discord-infra" and links traefik/portainer/dozzle.
#
# Usage (on the VPS):
#   bash scripts/uptime-kuma-seed-discord.sh
#
# Never prints the full webhook URL.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DATA_DIR="${DATA_ROOT}/uptime-kuma/data"
DB_FILE="${DATA_DIR}/kuma.db"
COMPOSE_FILE="$(service_compose_file uptime-kuma)"
ENV_FILE="${PROJECT_ROOT}/compose/uptime-kuma/.env"
NOTIF_NAME="discord-infra"
MONITOR_NAMES=(traefik portainer dozzle marca7-api marca7-app)

require_command docker

mask_webhook_hint() {
  local url="${1-}"
  if [[ -z "${url}" ]]; then
    printf '%s\n' "(not set)"
    return
  fi
  if [[ "${url}" =~ ^https?://([^/]+) ]]; then
    printf 'https://%s/... (redacted)\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "(redacted)"
  fi
}

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
    # Strip optional surrounding quotes
    if [[ "${value}" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "${value}" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    # Do not override a value already exported in the environment
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

section "Uptime Kuma — seed Discord alerts"

load_env_file "${ENV_FILE}"

if [[ -z "${KUMA_DISCORD_WEBHOOK_URL:-}" ]]; then
  die "KUMA_DISCORD_WEBHOOK_URL is not set. Put it in ${ENV_FILE} or export it."
fi

if [[ ! "${KUMA_DISCORD_WEBHOOK_URL}" =~ ^https://(discord|discordapp)\.com/api/webhooks/ ]]; then
  die "KUMA_DISCORD_WEBHOOK_URL does not look like a Discord webhook URL"
fi

if [[ ! -f "${DB_FILE}" ]]; then
  die "Uptime Kuma database not found: ${DB_FILE}"
fi

kv "webhook" "$(mask_webhook_hint "${KUMA_DISCORD_WEBHOOK_URL}")"
kv "env file" "${ENV_FILE}"

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

CONFIG_JSON="$(printf '%s' \
  "{\"type\":\"discord\",\"discordWebhookUrl\":\"$(json_escape "${KUMA_DISCORD_WEBHOOK_URL}")\",\"discordUsername\":\"Infra VPS\",\"discordChannelType\":\"channel\",\"discordMessageFormat\":\"normal\"}")"
CONFIG_SQL="$(sql_escape "${CONFIG_JSON}")"
NAME_SQL="$(sql_escape "${NOTIF_NAME}")"

NOTIF_ID="$(sqlite_exec "SELECT id FROM notification WHERE name = '${NAME_SQL}' LIMIT 1;")"

if [[ -n "${NOTIF_ID}" ]]; then
  sqlite_exec "UPDATE notification SET active = 1, user_id = 1, is_default = 0, config = '${CONFIG_SQL}' WHERE id = ${NOTIF_ID};"
  ok "updated notification: ${NOTIF_NAME} (id=${NOTIF_ID})"
else
  sqlite_exec "INSERT INTO notification (name, active, user_id, is_default, config)
    VALUES ('${NAME_SQL}', 1, 1, 0, '${CONFIG_SQL}');"
  NOTIF_ID="$(sqlite_exec "SELECT id FROM notification WHERE name = '${NAME_SQL}' LIMIT 1;")"
  ok "created notification: ${NOTIF_NAME} (id=${NOTIF_ID})"
fi

for monitor_name in "${MONITOR_NAMES[@]}"; do
  monitor_sql="$(sql_escape "${monitor_name}")"
  monitor_id="$(sqlite_exec "SELECT id FROM monitor WHERE name = '${monitor_sql}' LIMIT 1;")"
  if [[ -z "${monitor_id}" ]]; then
    warn "monitor not found, skip link: ${monitor_name}"
    continue
  fi

  linked="$(sqlite_exec "SELECT COUNT(*) FROM monitor_notification WHERE monitor_id = ${monitor_id} AND notification_id = ${NOTIF_ID};")"
  if [[ "${linked}" -gt 0 ]]; then
    ok "already linked: ${monitor_name} -> ${NOTIF_NAME}"
    continue
  fi

  next_id="$(sqlite_exec "SELECT COALESCE(MAX(id), 0) + 1 FROM monitor_notification;")"
  sqlite_exec "INSERT INTO monitor_notification (id, monitor_id, notification_id)
    VALUES (${next_id}, ${monitor_id}, ${NOTIF_ID});"
  ok "linked: ${monitor_name} (monitor_id=${monitor_id}) -> ${NOTIF_NAME}"
done

info "Starting uptime-kuma"
docker compose -f "${COMPOSE_FILE}" start
sleep 2
docker compose -f "${COMPOSE_FILE}" ps

section "Notification links"
sqlite_exec "SELECT n.id, n.name, m.name
  FROM notification n
  JOIN monitor_notification mn ON mn.notification_id = n.id
  JOIN monitor m ON m.id = mn.monitor_id
  WHERE n.name = '${NAME_SQL}'
  ORDER BY m.name;"

ok "Done. Discord alerts fire on monitor DOWN/UP only (not on healthy heartbeats)."
