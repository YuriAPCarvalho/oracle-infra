#!/usr/bin/env bash
# Logical dump of rankao database from shared postgres container.
set -Eeuo pipefail

CONTAINER="${PG_CONTAINER:-postgres}"
DB="${DB_NAME:-rankao}"
OUT="${1:-/opt/infra/backups/rankao-$(date +%Y%m%d-%H%M%S).sql.gz}"

mkdir -p "$(dirname "$OUT")"
docker exec "$CONTAINER" pg_dump -U postgres -d "$DB" | gzip > "$OUT"
chmod 600 "$OUT"
echo "Wrote $OUT"
