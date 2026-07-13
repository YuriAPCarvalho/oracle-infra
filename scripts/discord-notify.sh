#!/usr/bin/env bash
#
# discord-notify.sh
# Sends a Discord webhook notification for CI/CD events.
# Never prints the full webhook URL. Supports --dry-run (no network).
#
# Usage:
#   DISCORD_WEBHOOK_URL=... bash scripts/discord-notify.sh \
#     --title "Deploy concluido" --service my-svc --status success ...
#   bash scripts/discord-notify.sh --dry-run --title "Test" --status started

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

TITLE=""
SERVICE=""
ENVIRONMENT=""
STATUS=""
COMMIT=""
AUTHOR=""
BRANCH=""
RUN_URL=""
MESSAGE=""
DRY_RUN=0
FAIL_ON_ERROR=0
TIMEOUT_SECONDS=10
MAX_ATTEMPTS=2

usage() {
  cat <<'EOF'
Usage: discord-notify.sh [options]

Required:
  --title TEXT
  --status started|success|failure|rollback_started|rollback_success|rollback_failure

Optional:
  --service NAME
  --environment NAME
  --commit SHA
  --author NAME
  --branch NAME
  --run-url URL
  --message TEXT
  --timeout SECONDS   (default: 10)
  --attempts N        (default: 2)
  --fail-on-error     Exit non-zero when notify fails (default: soft-fail)
  --dry-run           Print sanitized payload JSON; do not send
  -h, --help
EOF
}

status_color() {
  case "$1" in
    started | rollback_started) printf '%s\n' "3447003" ;;      # blue
    success | rollback_success) printf '%s\n' "3066993" ;;      # green
    failure | rollback_failure) printf '%s\n' "15158332" ;;     # red
    *) printf '%s\n' "9807270" ;;                               # gray
  esac
}

status_label() {
  case "$1" in
    started) printf '%s\n' "deploy iniciado" ;;
    success) printf '%s\n' "deploy concluido" ;;
    failure) printf '%s\n' "deploy falhou" ;;
    rollback_started) printf '%s\n' "rollback iniciado" ;;
    rollback_success) printf '%s\n' "rollback concluido" ;;
    rollback_failure) printf '%s\n' "rollback falhou" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

json_escape() {
  # Minimal JSON string escape without requiring jq.
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "${s}"
}

build_payload() {
  local color
  local label
  local description

  color="$(status_color "${STATUS}")"
  label="$(status_label "${STATUS}")"
  description="**Status:** ${label}"

  [[ -n "${SERVICE}" ]] && description+=$'\n'"**Servico:** ${SERVICE}"
  [[ -n "${ENVIRONMENT}" ]] && description+=$'\n'"**Ambiente:** ${ENVIRONMENT}"
  [[ -n "${BRANCH}" ]] && description+=$'\n'"**Branch:** ${BRANCH}"
  [[ -n "${COMMIT}" ]] && description+=$'\n'"**Commit:** \`${COMMIT}\`"
  [[ -n "${AUTHOR}" ]] && description+=$'\n'"**Autor:** ${AUTHOR}"
  [[ -n "${RUN_URL}" ]] && description+=$'\n'"**Execucao:** ${RUN_URL}"
  [[ -n "${MESSAGE}" ]] && description+=$'\n'"**Mensagem:** ${MESSAGE}"

  cat <<EOF
{
  "embeds": [
    {
      "title": "$(json_escape "${TITLE}")",
      "description": "$(json_escape "${description}")",
      "color": ${color},
      "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    }
  ]
}
EOF
}

mask_webhook_hint() {
  local url="${1-}"
  if [[ -z "${url}" ]]; then
    printf '%s\n' "(not set)"
    return
  fi
  # Show only host + trailing token length hint; never the full path/secret.
  if [[ "${url}" =~ ^https?://([^/]+) ]]; then
    printf 'https://%s/... (redacted)\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "(redacted)"
  fi
}

send_webhook() {
  local payload="$1"
  local webhook_url="$2"
  local attempt
  local http_code
  local curl_exit

  for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
    http_code=0
    curl_exit=0
    http_code="$(
      curl \
        --silent \
        --show-error \
        --output /dev/null \
        --write-out '%{http_code}' \
        --max-time "${TIMEOUT_SECONDS}" \
        --connect-timeout "${TIMEOUT_SECONDS}" \
        -H 'Content-Type: application/json' \
        -d "${payload}" \
        "${webhook_url}"
    )" || curl_exit=$?

    if [[ "${curl_exit}" -eq 0 && "${http_code}" =~ ^2[0-9][0-9]$ ]]; then
      ok "Discord notification sent (HTTP ${http_code})"
      return 0
    fi

    warn "Discord notify attempt ${attempt}/${MAX_ATTEMPTS} failed (http=${http_code:-n/a} curl=${curl_exit})"
    if [[ "${attempt}" -lt "${MAX_ATTEMPTS}" ]]; then
      sleep 1
    fi
  done

  return 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title)
        TITLE="${2:-}"
        shift 2
        ;;
      --service)
        SERVICE="${2:-}"
        shift 2
        ;;
      --environment)
        ENVIRONMENT="${2:-}"
        shift 2
        ;;
      --status)
        STATUS="${2:-}"
        shift 2
        ;;
      --commit)
        COMMIT="${2:-}"
        shift 2
        ;;
      --author)
        AUTHOR="${2:-}"
        shift 2
        ;;
      --branch)
        BRANCH="${2:-}"
        shift 2
        ;;
      --run-url)
        RUN_URL="${2:-}"
        shift 2
        ;;
      --message)
        MESSAGE="${2:-}"
        shift 2
        ;;
      --timeout)
        TIMEOUT_SECONDS="${2:-}"
        shift 2
        ;;
      --attempts)
        MAX_ATTEMPTS="${2:-}"
        shift 2
        ;;
      --fail-on-error)
        FAIL_ON_ERROR=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  local payload
  local webhook_url
  local notify_rc

  parse_args "$@"

  [[ -n "${TITLE}" ]] || die "--title is required"
  [[ -n "${STATUS}" ]] || die "--status is required"

  case "${STATUS}" in
    started | success | failure | rollback_started | rollback_success | rollback_failure) ;;
    *) die "Invalid --status: ${STATUS}" ;;
  esac

  [[ "${TIMEOUT_SECONDS}" =~ ^[1-9][0-9]*$ ]] || die "Invalid --timeout"
  [[ "${MAX_ATTEMPTS}" =~ ^[1-9][0-9]*$ ]] || die "Invalid --attempts"

  payload="$(build_payload)"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Discord notify dry-run (webhook not contacted)"
    kv "webhook" "$(mask_webhook_hint "${DISCORD_WEBHOOK_URL:-}")"
    printf '%s\n' "${payload}"
    exit 0
  fi

  require_command curl

  webhook_url="${DISCORD_WEBHOOK_URL:-}"
  if [[ -z "${webhook_url}" ]]; then
    warn "DISCORD_WEBHOOK_URL is not set; skipping notification"
    if [[ "${FAIL_ON_ERROR}" -eq 1 ]]; then
      exit 1
    fi
    exit 0
  fi

  info "Sending Discord notification ($(status_label "${STATUS}"))"
  kv "webhook" "$(mask_webhook_hint "${webhook_url}")"

  notify_rc=0
  send_webhook "${payload}" "${webhook_url}" || notify_rc=$?

  if [[ "${notify_rc}" -ne 0 ]]; then
    fail "Discord notification failed after ${MAX_ATTEMPTS} attempt(s)"
    if [[ "${FAIL_ON_ERROR}" -eq 1 ]]; then
      exit 1
    fi
    exit 0
  fi
}

main "$@"
