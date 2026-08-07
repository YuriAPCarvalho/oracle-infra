#!/usr/bin/env bash
# Wire Grafana Alerting → Discord (same pattern as uptime-kuma-seed-discord.sh).
#
# Reads GRAFANA_DISCORD_WEBHOOK_URL from compose/grafana/.env.
# If missing, copies KUMA_DISCORD_WEBHOOK_URL from compose/uptime-kuma/.env
# (same #infra-alertas channel as Uptime Kuma).
#
# Usage (on the VPS):
#   bash scripts/grafana-seed-discord.sh
#   bash scripts/grafana-seed-discord.sh --test
#
# Never prints the full webhook URL.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

COMPOSE_FILE="$(service_compose_file grafana)"
ENV_FILE="${PROJECT_ROOT}/compose/grafana/.env"
KUMA_ENV_FILE="${PROJECT_ROOT}/compose/uptime-kuma/.env"
DO_TEST=0

for arg in "$@"; do
  case "${arg}" in
    --test) DO_TEST=1 ;;
    -h | --help)
      cat <<'EOF'
Usage: grafana-seed-discord.sh [--test]

  Ensures GRAFANA_DISCORD_WEBHOOK_URL in compose/grafana/.env
  (falls back to KUMA_DISCORD_WEBHOOK_URL), recreates Grafana, and
  optionally sends a Discord test via the discord-metrics contact point.
EOF
      exit 0
      ;;
    *)
      die "Unknown argument: ${arg}"
      ;;
  esac
done

require_command docker
require_command curl
require_command python3

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

load_env_file() {
  local file="$1"
  local line key value

  [[ -f "${file}" ]] || return 0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" == *=* ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    key="${key#"${key%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    if [[ "${value}" =~ ^\".*\"$ || "${value}" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi
    if [[ -z "${!key+x}" ]]; then
      export "${key}=${value}"
    fi
  done <"${file}"
}

upsert_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp

  touch "${file}"
  chmod 600 "${file}"
  tmp="$(mktemp)"
  if grep -qE "^${key}=" "${file}" 2>/dev/null; then
    # shellcheck disable=SC2001
    sed "s|^${key}=.*|${key}=${value}|" "${file}" >"${tmp}"
  else
    cat "${file}" >"${tmp}"
    printf '\n%s=%s\n' "${key}" "${value}" >>"${tmp}"
  fi
  mv "${tmp}" "${file}"
  chmod 600 "${file}"
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

load_env_file "${ENV_FILE}"
load_env_file "${KUMA_ENV_FILE}"

if [[ -z "${GRAFANA_DISCORD_WEBHOOK_URL:-}" ]]; then
  if [[ -n "${KUMA_DISCORD_WEBHOOK_URL:-}" ]]; then
    info "GRAFANA_DISCORD_WEBHOOK_URL missing — reusing KUMA_DISCORD_WEBHOOK_URL (same Discord channel as Uptime Kuma)"
    export GRAFANA_DISCORD_WEBHOOK_URL="${KUMA_DISCORD_WEBHOOK_URL}"
  else
    die "Set GRAFANA_DISCORD_WEBHOOK_URL in ${ENV_FILE} (or KUMA_DISCORD_WEBHOOK_URL in ${KUMA_ENV_FILE})"
  fi
else
  export GRAFANA_DISCORD_WEBHOOK_URL
fi

if [[ ! "${GRAFANA_DISCORD_WEBHOOK_URL}" =~ ^https://(discord|discordapp)\.com/api/webhooks/ ]]; then
  die "GRAFANA_DISCORD_WEBHOOK_URL does not look like a Discord webhook URL"
fi

[[ -n "${GF_SECURITY_ADMIN_USER:-}" ]] || die "GF_SECURITY_ADMIN_USER missing in ${ENV_FILE}"
[[ -n "${GF_SECURITY_ADMIN_PASSWORD:-}" ]] || die "GF_SECURITY_ADMIN_PASSWORD missing in ${ENV_FILE}"

upsert_env_var "${ENV_FILE}" "GRAFANA_DISCORD_WEBHOOK_URL" "${GRAFANA_DISCORD_WEBHOOK_URL}"

kv "webhook" "$(mask_webhook_hint "${GRAFANA_DISCORD_WEBHOOK_URL}")"
kv "contact" "discord-metrics"

info "Recreating Grafana so contact point picks up webhook"
docker compose -f "${COMPOSE_FILE}" up -d --force-recreate

info "Waiting for Grafana health"
for attempt in {1..40}; do
  if curl --silent --fail --max-time 5 http://127.0.0.1:3000/api/health >/dev/null; then
    break
  fi
  if [[ "${attempt}" -eq 40 ]]; then
    docker logs grafana --tail 80 >&2 || true
    die "Grafana did not become healthy"
  fi
  sleep 2
done

# Confirm container env (masked)
container_url="$(docker exec grafana printenv GRAFANA_DISCORD_WEBHOOK_URL 2>/dev/null || true)"
if [[ -z "${container_url}" ]]; then
  die "GRAFANA_DISCORD_WEBHOOK_URL not present inside container"
fi
if [[ "${container_url}" == *"grafana-discord-unconfigured"* || "${container_url}" == http://127.0.0.1:1* ]]; then
  die "Container still has noop Discord URL — check compose env_file"
fi
ok "Grafana Discord webhook configured ($(mask_webhook_hint "${container_url}"))"

if [[ "${DO_TEST}" -eq 1 ]]; then
  info "Sending Discord test via contact point discord-metrics"
  payload="$(
    python3 - <<'PY'
import json, os
url = os.environ["GRAFANA_DISCORD_WEBHOOK_URL"]
print(json.dumps({
  "receivers": [{
    "name": "discord-metrics",
    "grafana_managed_receiver_configs": [{
      "uid": "discord-metrics",
      "name": "discord-metrics",
      "type": "discord",
      "disableResolveMessage": False,
      "settings": {
        "url": url,
        "title": "Oracle Infra — Grafana test",
        "message": "Grafana Alerting → Discord OK (metrics alerts).",
      },
    }],
  }],
}))
PY
  )"
  http_code="$(
    curl -sS -o /tmp/grafana-discord-test.out -w '%{http_code}' \
      -u "${GF_SECURITY_ADMIN_USER}:${GF_SECURITY_ADMIN_PASSWORD}" \
      -H 'Content-Type: application/json' \
      -X POST \
      --data "${payload}" \
      http://127.0.0.1:3000/api/alertmanager/grafana/config/api/v1/receivers/test
  )"
  if [[ "${http_code}" =~ ^2 ]]; then
    ok "Discord test accepted (HTTP ${http_code})"
  else
    warn "Discord test HTTP ${http_code}"
    head -c 400 /tmp/grafana-discord-test.out >&2 || true
    echo >&2
    die "Contact point test failed"
  fi
fi

ok "Done — alerts with severity warning|critical route to discord-metrics"
