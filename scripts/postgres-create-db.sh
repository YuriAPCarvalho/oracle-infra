#!/usr/bin/env bash
#
# postgres-create-db.sh
# Create an application database + role on the shared Postgres container.
# Idempotent for role/database names (skips if already present).
#
# Usage:
#   bash scripts/postgres-create-db.sh --name dailybot --password 'secret'
#   bash scripts/postgres-create-db.sh --name myapp --password 'secret' --container postgres
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

DB_NAME=""
DB_PASSWORD=""
DB_OWNER=""
CONTAINER="postgres"
SUPERUSER="postgres"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/postgres-create-db.sh --name <db> --password <pass> [--owner <role>] [--container postgres]

Creates ROLE (login) and DATABASE owned by that role on the shared Postgres.
Does not print the password after creation.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) DB_NAME="${2:-}"; shift 2 ;;
    --password) DB_PASSWORD="${2:-}"; shift 2 ;;
    --owner) DB_OWNER="${2:-}"; shift 2 ;;
    --container) CONTAINER="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "${DB_NAME}" ]] || die "--name is required"
[[ -n "${DB_PASSWORD}" ]] || die "--password is required"
DB_OWNER="${DB_OWNER:-${DB_NAME}}"

[[ "${DB_NAME}" =~ ^[a-z][a-z0-9_]*$ ]] || die "Invalid --name (use lowercase [a-z0-9_])"
[[ "${DB_OWNER}" =~ ^[a-z][a-z0-9_]*$ ]] || die "Invalid --owner"

require_command docker
container_running "${CONTAINER}" || die "Container ${CONTAINER} is not running"

# Escape single quotes for SQL string literals
sql_quote() {
  printf "%s" "${1//\'/\'\'}"
}

PASS_SQL=$(sql_quote "${DB_PASSWORD}")

info "Ensuring role ${DB_OWNER}"
docker exec -i "${CONTAINER}" psql -U "${SUPERUSER}" -d postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_OWNER}') THEN
    CREATE ROLE ${DB_OWNER} LOGIN PASSWORD '${PASS_SQL}';
  ELSE
    ALTER ROLE ${DB_OWNER} WITH LOGIN PASSWORD '${PASS_SQL}';
  END IF;
END
\$\$;
SQL

info "Ensuring database ${DB_NAME}"
EXISTS=$(docker exec -i "${CONTAINER}" psql -U "${SUPERUSER}" -d postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" | tr -d '[:space:]')

if [[ "${EXISTS}" == "1" ]]; then
  ok "Database ${DB_NAME} already exists"
else
  docker exec -i "${CONTAINER}" psql -U "${SUPERUSER}" -d postgres -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE ${DB_NAME} OWNER ${DB_OWNER};"
  ok "Created database ${DB_NAME}"
fi

docker exec -i "${CONTAINER}" psql -U "${SUPERUSER}" -d postgres -v ON_ERROR_STOP=1 \
  -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_OWNER};"

# Schema privileges for future objects (connect to the app DB)
docker exec -i "${CONTAINER}" psql -U "${SUPERUSER}" -d "${DB_NAME}" -v ON_ERROR_STOP=1 <<SQL
GRANT ALL ON SCHEMA public TO ${DB_OWNER};
ALTER SCHEMA public OWNER TO ${DB_OWNER};
SQL

ok "Ready: postgresql://${DB_OWNER}@${CONTAINER}:5432/${DB_NAME}"
