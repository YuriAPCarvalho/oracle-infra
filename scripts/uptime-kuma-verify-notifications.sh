#!/usr/bin/env bash
# Read-only check: Uptime Kuma container, Discord env, notification links.
#
# Usage (on the VPS):
#   bash scripts/uptime-kuma-verify-notifications.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DATA_DIR="${DATA_ROOT}/uptime-kuma/data"
DB_FILE="${DATA_DIR}/kuma.db"
ENV_FILE="${PROJECT_ROOT}/compose/uptime-kuma/.env"
NOTIF_NAME="discord-infra"

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

section "Uptime Kuma — verify notifications"

if docker ps --filter name=uptime-kuma --filter status=running -q | grep -q .; then
  ok "container uptime-kuma is running"
else
  warn "container uptime-kuma is not running"
fi

if [[ -f "${ENV_FILE}" ]] && grep -qE '^KUMA_DISCORD_WEBHOOK_URL=.+' "${ENV_FILE}" 2>/dev/null; then
  ok "KUMA_DISCORD_WEBHOOK_URL is set in ${ENV_FILE}"
else
  warn "KUMA_DISCORD_WEBHOOK_URL missing in ${ENV_FILE}"
fi

if [[ ! -f "${DB_FILE}" ]]; then
  if ! docker run --rm -v "${DATA_DIR}:/data:ro" busybox test -f /data/kuma.db 2>/dev/null; then
    die "database not found: ${DB_FILE}"
  fi
fi

NOTIF_COUNT="$(sqlite_exec "SELECT COUNT(*) FROM notification WHERE name = '${NOTIF_NAME}';")"
kv "notification ${NOTIF_NAME}" "${NOTIF_COUNT} row(s)"

LINK_COUNT="$(sqlite_exec "SELECT COUNT(*) FROM monitor_notification mn
  JOIN notification n ON n.id = mn.notification_id
  WHERE n.name = '${NOTIF_NAME}';")"
kv "monitor links" "${LINK_COUNT}"

section "Monitors linked to ${NOTIF_NAME}"
sqlite_exec "SELECT m.name
  FROM monitor m
  JOIN monitor_notification mn ON mn.monitor_id = m.id
  JOIN notification n ON n.id = mn.notification_id
  WHERE n.name = '${NOTIF_NAME}'
  ORDER BY m.name;" || true

section "All monitors"
sqlite_exec "SELECT id, name, type, active FROM monitor ORDER BY name;" || true

ok "Read-only verify complete."
