#!/usr/bin/env bash
# Send Uptime Kuma "Test notification" for discord-infra (same code path as the UI Test button).
#
# Usage (on the VPS):
#   bash scripts/uptime-kuma-test-discord.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DATA_DIR="${DATA_ROOT}/uptime-kuma/data"
NOTIF_NAME="${1:-discord-infra}"

require_command docker

if ! docker ps --filter name=uptime-kuma --filter status=running -q | grep -q .; then
  die "uptime-kuma container is not running"
fi

CONFIG_JSON="$(docker run --rm \
  -v "${DATA_DIR}:/data:ro" \
  --entrypoint sqlite3 \
  louislam/uptime-kuma:1 \
  /data/kuma.db "SELECT config FROM notification WHERE name = '${NOTIF_NAME}' LIMIT 1;")"

if [[ -z "${CONFIG_JSON}" ]]; then
  die "notification not found: ${NOTIF_NAME}"
fi

info "Sending Kuma test notification (${NOTIF_NAME})"

docker exec -i -e "KUMA_NOTIF_CONFIG=${CONFIG_JSON}" uptime-kuma node - <<'NODE'
const { Notification } = require("/app/server/notification");
Notification.init();
const config = JSON.parse(process.env.KUMA_NOTIF_CONFIG);
Notification.send(config, config.name + " Testing")
  .then((msg) => {
    console.log("OK", msg);
    process.exit(0);
  })
  .catch((err) => {
    console.error("FAIL", err && err.message ? err.message : err);
    process.exit(1);
  });
NODE
