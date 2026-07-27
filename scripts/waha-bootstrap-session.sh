#!/usr/bin/env bash
# Bootstrap WAHA session (GOWS) on VPS — run from /opt/infra after compose/waha is up.
set -euo pipefail

ROOT="${INFRA_ROOT:-/opt/infra}"
ENV_FILE="${ROOT}/compose/waha/.env"
SESSION="${WAHA_SESSION:-chamaeu}"
ENGINE="${WHATSAPP_DEFAULT_ENGINE:-GOWS}"
API="http://127.0.0.1:3000"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"
: "${WAHA_API_KEY:?WAHA_API_KEY not set in $ENV_FILE}"

waha_curl() {
  docker exec waha curl -fsS \
    -H "X-Api-Key: ${WAHA_API_KEY}" \
    "$@"
}

waha_json() {
  docker exec waha curl -fsS \
    -H "X-Api-Key: ${WAHA_API_KEY}" \
    -H "Content-Type: application/json" \
    "$@"
}

echo "==> WAHA server status"
waha_curl "$API/api/server/status"
echo

echo "==> Sessions (before)"
waha_curl "$API/api/sessions" || echo "[]"
echo

if waha_curl "$API/api/sessions/${SESSION}" 2>/dev/null; then
  echo "==> Removing existing session ${SESSION}"
  waha_json -X POST "$API/api/sessions/${SESSION}/stop" 2>/dev/null || true
  waha_json -X DELETE "$API/api/sessions/${SESSION}" 2>/dev/null || true
  sleep 2
fi

echo "==> Create session ${SESSION} engine=${ENGINE}"
waha_json -X POST "$API/api/sessions" \
  -d "{\"name\":\"${SESSION}\",\"config\":{\"engine\":\"${ENGINE}\"}}"

echo
echo "==> Start session"
waha_json -X POST "$API/api/sessions/${SESSION}/start"

echo
echo "==> Wait for SCAN_QR_CODE or WORKING"
status=""
for _ in $(seq 1 60); do
  st="$(waha_curl "$API/api/sessions/${SESSION}" 2>/dev/null || echo '{}')"
  status="$(echo "$st" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p' | head -1)"
  echo "status=${status:-unknown}"
  if [[ "$status" == "SCAN_QR_CODE" || "$status" == "WORKING" ]]; then
    break
  fi
  if [[ "$status" == "FAILED" ]]; then
    echo "$st"
    echo "Session FAILED — check: docker logs waha --tail 50" >&2
    exit 1
  fi
  sleep 2
done

echo "==> QR PNG"
OUT="/tmp/waha-${SESSION}-qr.png"
if docker exec waha curl -fsS \
  -H "X-Api-Key: ${WAHA_API_KEY}" \
  "$API/api/${SESSION}/auth/qr?format=image" \
  -o /tmp/qr-in-container.png; then
  docker cp "waha:/tmp/qr-in-container.png" "$OUT"
  echo "QR saved: $OUT"
else
  echo "==> QR (raw JSON, first 600 chars):"
  waha_curl "$API/api/${SESSION}/auth/qr" | head -c 600
  echo
fi

echo "==> Sync WAHA_* to rankao-api .env"
API_ENV="${ROOT}/compose/rankao-api/.env"
if [[ -f "$API_ENV" ]]; then
  tmp="$(mktemp)"
  grep -v '^WAHA_API_KEY=' "$API_ENV" | grep -v '^WAHA_SESSION=' | grep -v '^WAHA_BASE_URL=' >"$tmp" || true
  {
    cat "$tmp"
    echo "WAHA_BASE_URL=http://waha:3000"
    echo "WAHA_API_KEY=${WAHA_API_KEY}"
    echo "WAHA_SESSION=${SESSION}"
  } >"$API_ENV"
  rm -f "$tmp"
  cd "${ROOT}/compose/rankao-api"
  docker compose up -d --force-recreate
  echo "rankao-api recreated with matching WAHA_*"
  if [[ "${status:-}" == "WORKING" ]]; then
    if grep -q '^DISPARAR_NOTIFICACAO_WHATSAPP=' "$API_ENV"; then
      sed -i 's/^DISPARAR_NOTIFICACAO_WHATSAPP=.*/DISPARAR_NOTIFICACAO_WHATSAPP=true/' "$API_ENV"
    else
      echo "DISPARAR_NOTIFICACAO_WHATSAPP=true" >>"$API_ENV"
    fi
    docker compose up -d --force-recreate
    echo "DISPARAR_NOTIFICACAO_WHATSAPP=true (session WORKING)"
  else
    echo "After QR scan: set DISPARAR_NOTIFICACAO_WHATSAPP=true in rankao-api .env and recreate API"
  fi
fi

echo "DONE"
