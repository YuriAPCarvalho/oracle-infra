#!/usr/bin/env bash
# Logical dump of a single database from the shared postgres container.
# Default output: ${DATA_ROOT}/backups/postgres/<db>-<timestamp>.sql.gz
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CONTAINER="${PG_CONTAINER:-postgres}"
DB="${DB_NAME:-rankao}"
DATA_ROOT="$(persistent_data_root)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="${1:-${DATA_ROOT}/backups/postgres/${DB}-${STAMP}.sql.gz}"

mkdir -p "$(dirname "$OUT")" 2>/dev/null || sudo mkdir -p "$(dirname "$OUT")"
docker exec "$CONTAINER" pg_dump -U postgres -d "$DB" | gzip > "$OUT"
chmod 600 "$OUT"
echo "Wrote $OUT"
