#!/usr/bin/env bash
# Create a MinIO bucket (idempotent) using the official mc client image.
#
# Usage (on VPS):
#   bash scripts/minio-create-bucket.sh
#   bash scripts/minio-create-bucket.sh --bucket marca7-estoque
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${PROJECT_ROOT}/compose/minio/.env"
BUCKET="marca7-estoque"
CONTAINER="minio"
NETWORK="internal"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket) BUCKET="${2:-}"; shift 2 ;;
    --container) CONTAINER="${2:-}"; shift 2 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -f "${ENV_FILE}" ]] || die "Missing ${ENV_FILE}"
# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a

[[ -n "${MINIO_ROOT_USER:-}" ]] || die "MINIO_ROOT_USER missing in .env"
[[ -n "${MINIO_ROOT_PASSWORD:-}" ]] || die "MINIO_ROOT_PASSWORD missing in .env"
[[ -n "${BUCKET}" ]] || die "--bucket is required"

require_command docker
container_running "${CONTAINER}" || die "Container ${CONTAINER} is not running"

info "Ensuring bucket ${BUCKET}"
docker run --rm --network "${NETWORK}" \
  -e MC_HOST_local="http://${MINIO_ROOT_USER}:${MINIO_ROOT_PASSWORD}@${CONTAINER}:9000" \
  minio/mc:RELEASE.2025-04-16T18-13-26Z \
  mb --ignore-existing "local/${BUCKET}"

ok "Bucket ready: ${BUCKET}"
