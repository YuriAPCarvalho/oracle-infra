#!/usr/bin/env bash
# Validate ChamaEu monitoring artifacts and (optionally) live endpoints.
#
# Usage:
#   bash scripts/chamaeu-monitoring-validate.sh           # local checks only
#   bash scripts/chamaeu-monitoring-validate.sh --smoke   # + public HTTPS smoke (needs curl)
#
# On the VPS after seed:
#   bash scripts/uptime-kuma-verify-notifications.sh
#   bash scripts/chamaeu-monitoring-validate.sh --smoke

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

RUN_SMOKE=false
if [[ "${1:-}" == "--smoke" ]]; then
  RUN_SMOKE=true
fi

FAILURES=0

check() {
  local name="$1"
  shift
  if "$@"; then
    ok "${name}"
  else
    fail "${name}"
    FAILURES=$((FAILURES + 1))
  fi
}

section "ChamaEu monitoring — validate"

check "syntax uptime-kuma-seed-monitors.sh" \
  bash -n "${SCRIPT_DIR}/uptime-kuma-seed-monitors.sh"
check "syntax uptime-kuma-seed-chamaeu-monitors.sh" \
  bash -n "${SCRIPT_DIR}/uptime-kuma-seed-chamaeu-monitors.sh"
check "syntax uptime-kuma-seed-discord.sh" \
  bash -n "${SCRIPT_DIR}/uptime-kuma-seed-discord.sh"

MONITORS_JSON="${PROJECT_ROOT}/services/chamaeu/uptime-kuma-monitors.json"
if command -v python3 >/dev/null 2>&1; then
  check "uptime-kuma-monitors.json parse" \
    python3 -c "import json; json.load(open('${MONITORS_JSON}'))"
else
  warn "python3 not found — skip JSON parse"
fi

if [[ "${RUN_SMOKE}" == "true" ]]; then
  section "Public smoke (ChamaEu)"
  SMOKE="${PROJECT_ROOT}/../rankao-api/docs/oracle-migration/scripts/smoke-chamaeu.sh"
  if [[ ! -f "${SMOKE}" ]]; then
    SMOKE="${SCRIPT_DIR}/../../rankao-api/docs/oracle-migration/scripts/smoke-chamaeu.sh"
  fi
  if [[ -f "${SMOKE}" ]]; then
    check "smoke-chamaeu.sh" env RESOLVE_IP=off bash "${SMOKE}"
  else
    warn "smoke-chamaeu.sh not found at ${SMOKE}"
  fi
else
  info "Skip live smoke (pass --smoke to run curl checks against production URLs)"
fi

section "VPS checklist (manual)"
info "1. cd /opt/infra && bash scripts/uptime-kuma-seed-monitors.sh"
info "2. bash scripts/uptime-kuma-seed-discord.sh"
info "3. bash scripts/uptime-kuma-verify-notifications.sh"
info "4. Kuma UI → discord-infra → Send Test"
info "5. Controlled DOWN test (e.g. pause rankao-web 2 min) → Discord DOWN/UP"

if [[ "${FAILURES}" -gt 0 ]]; then
  die "${FAILURES} validation check(s) failed"
fi

ok "All automated validation checks passed."
