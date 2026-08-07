#!/usr/bin/env bash
# Build compose/postgres-exporter/.env from compose/postgres/.env (VPS only).
# Never prints credentials.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

PG_ENV="${PROJECT_ROOT}/compose/postgres/.env"
OUT_ENV="${PROJECT_ROOT}/compose/postgres-exporter/.env"

require_command python3

[[ -f "${PG_ENV}" ]] || die "Missing ${PG_ENV}"

# shellcheck disable=SC1090
set -a
# shellcheck source=/dev/null
source "${PG_ENV}"
set +a

[[ -n "${POSTGRES_USER:-}" ]] || die "POSTGRES_USER missing in postgres .env"
[[ -n "${POSTGRES_PASSWORD:-}" ]] || die "POSTGRES_PASSWORD missing in postgres .env"
DB_NAME="${POSTGRES_DB:-postgres}"

DSN="$(
  POSTGRES_USER="${POSTGRES_USER}" \
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  DB_NAME="${DB_NAME}" \
  python3 - <<'PY'
import os, urllib.parse
user = urllib.parse.quote(os.environ["POSTGRES_USER"], safe="")
password = urllib.parse.quote(os.environ["POSTGRES_PASSWORD"], safe="")
db = urllib.parse.quote(os.environ["DB_NAME"], safe="")
print(f"postgresql://{user}:{password}@postgres:5432/{db}?sslmode=disable")
PY
)"

umask 077
printf 'DATA_SOURCE_NAME=%s\n' "${DSN}" >"${OUT_ENV}"
chmod 600 "${OUT_ENV}"
ok "Wrote ${OUT_ENV} (credentials redacted)"
