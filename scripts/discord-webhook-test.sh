#!/usr/bin/env bash
# POST a test message using KUMA_DISCORD_WEBHOOK_URL from compose/uptime-kuma/.env
# Never prints the full webhook URL.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${PROJECT_ROOT}/compose/uptime-kuma/.env"
MESSAGE="${1:-Oracle VPS webhook test OK}"

load_env() {
  local line key value
  [[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ "${line}" =~ ^KUMA_DISCORD_WEBHOOK_URL=(.*)$ ]] || continue
    value="${BASH_REMATCH[1]}"
    printf '%s' "${value}"
    return 0
  done < "${ENV_FILE}"
  die "KUMA_DISCORD_WEBHOOK_URL not set in ${ENV_FILE}"
}

webhook_url="$(load_env)"
payload="$(printf '{"content":"%s"}' "$(printf '%s' "${MESSAGE}" | sed 's/\\/\\\\/g; s/"/\\"/g')")"

http_code="$(curl -sS -o /tmp/discord-webhook-test.out -w '%{http_code}' \
  -X POST \
  -H 'Content-Type: application/json' \
  --data-binary "${payload}" \
  "${webhook_url}")"

if [[ "${http_code}" == "204" || "${http_code}" == "200" ]]; then
  ok "Discord webhook accepted (HTTP ${http_code})"
  exit 0
fi

fail "Discord webhook failed (HTTP ${http_code})"
head -c 300 /tmp/discord-webhook-test.out >&2 || true
exit 1
