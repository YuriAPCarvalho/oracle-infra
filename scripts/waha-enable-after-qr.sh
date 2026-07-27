#!/usr/bin/env bash
# After scanning QR: wait for WORKING and enable WhatsApp jobs on rankao-api.
set -euo pipefail

ROOT="${INFRA_ROOT:-/opt/infra}"
ENV_FILE="${ROOT}/compose/waha/.env"
SESSION="${WAHA_SESSION:-chamaeu}"
API="http://127.0.0.1:3000"
TIMEOUT="${WAHA_PAIR_TIMEOUT_SEC:-600}"

source "$ENV_FILE"
: "${WAHA_API_KEY:?}"

echo "Waiting up to ${TIMEOUT}s for session ${SESSION} WORKING..."
deadline=$((SECONDS + TIMEOUT))
while (( SECONDS < deadline )); do
  st="$(docker exec waha curl -fsS -H "X-Api-Key: ${WAHA_API_KEY}" "$API/api/sessions/${SESSION}" || echo '{}')"
  if echo "$st" | grep -q '"status":"WORKING"'; then
    echo "Session WORKING."
    API_ENV="${ROOT}/compose/rankao-api/.env"
    if grep -q '^DISPARAR_NOTIFICACAO_WHATSAPP=' "$API_ENV"; then
      sed -i 's/^DISPARAR_NOTIFICACAO_WHATSAPP=.*/DISPARAR_NOTIFICACAO_WHATSAPP=true/' "$API_ENV"
    else
      echo "DISPARAR_NOTIFICACAO_WHATSAPP=true" >>"$API_ENV"
    fi
    cd "${ROOT}/compose/rankao-api" && docker compose up -d --force-recreate
    echo "DISPARAR_NOTIFICACAO_WHATSAPP=true — API recreated."
    exit 0
  fi
  echo "$st" | sed -n 's/.*"status":"\([^"]*\)".*/status=\1/p' | head -1
  sleep 5
done
echo "Timeout — scan QR and run again." >&2
exit 1
