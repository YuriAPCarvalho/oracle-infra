#!/usr/bin/env bash
#
# storage-textfile.sh
# Emits Prometheus textfile metrics for directory growth under DATA_ROOT.
# Output: ${DATA_ROOT}/monitoring/node-exporter/textfile/storage.prom
#
# Schedule via cron (see scripts/backup/cron.example). Requires node-exporter
# with --collector.textfile.directory=/textfile mounted to that path.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

DATA_ROOT="$(persistent_data_root)"
OUT_DIR="${DATA_ROOT}/monitoring/node-exporter/textfile"
OUT_FILE="${OUT_DIR}/storage.prom"
PARTIAL="${OUT_FILE}.$$"

dir_bytes() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    du -sb "${path}" 2>/dev/null | awk '{print $1}'
  else
    printf '0\n'
  fi
}

emit() {
  local name="$1"
  local path="$2"
  local bytes
  bytes="$(dir_bytes "${path}")"
  printf 'infra_storage_dir_bytes{path="%s"} %s\n' "${name}" "${bytes}"
}

mkdir -p "${OUT_DIR}" 2>/dev/null || sudo mkdir -p "${OUT_DIR}"

{
  printf '# HELP infra_storage_dir_bytes Directory size in bytes under DATA_ROOT.\n'
  printf '# TYPE infra_storage_dir_bytes gauge\n'
  emit "databases/postgres" "${DATA_ROOT}/databases/postgres"
  emit "databases/redis" "${DATA_ROOT}/databases/redis"
  emit "object-storage/minio" "${DATA_ROOT}/object-storage/minio/data"
  emit "monitoring/prometheus" "${DATA_ROOT}/monitoring/prometheus"
  emit "monitoring/grafana" "${DATA_ROOT}/monitoring/grafana"
  emit "backups" "${DATA_ROOT}/backups"
  emit "backups/full" "${DATA_ROOT}/backups/full"
  emit "backups/postgres" "${DATA_ROOT}/backups/postgres"
  emit "applications" "${DATA_ROOT}/applications"
  emit "deploy-state" "${DATA_ROOT}/deploy-state"

  printf '# HELP infra_backup_last_success_timestamp_seconds mtime of backups/full/.last-success\n'
  printf '# TYPE infra_backup_last_success_timestamp_seconds gauge\n'
  if [[ -e "${DATA_ROOT}/backups/full/.last-success" ]]; then
    # portable-ish: prefer stat -c %Y (GNU)
    ts="$(stat -c %Y "${DATA_ROOT}/backups/full/.last-success" 2>/dev/null || echo 0)"
  else
    ts=0
  fi
  printf 'infra_backup_last_success_timestamp_seconds %s\n' "${ts}"
} >"${PARTIAL}"

mv -f "${PARTIAL}" "${OUT_FILE}"
chmod 644 "${OUT_FILE}" 2>/dev/null || true
