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
  local bytes=0
  if [[ -d "${path}" ]]; then
    # pipefail: du may exit 1 on permission-denied leaves; keep metric emission going.
    bytes="$(du -sb "${path}" 2>/dev/null | awk '{print $1}')" || true
  fi
  printf '%s\n' "${bytes:-0}"
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

  # Layer-3 R2 (updated by r2-upload.sh; refreshed here from markers so scrape stays fresh)
  r2_bytes=0
  r2_objects=0
  r2_soft_max=8589934592
  r2_usage="${DATA_ROOT}/backups/full/.r2-usage"
  if [[ -f "${r2_usage}" ]]; then
    # shellcheck disable=SC1090
    # file format: bytes=N / objects=N / soft_max=N
    while IFS='=' read -r k v; do
      case "${k}" in
        bytes) r2_bytes="${v:-0}" ;;
        objects) r2_objects="${v:-0}" ;;
        soft_max) r2_soft_max="${v:-8589934592}" ;;
      esac
    done <"${r2_usage}"
  fi
  printf '# HELP infra_r2_bucket_bytes Approximate R2 backup prefix size in bytes\n'
  printf '# TYPE infra_r2_bucket_bytes gauge\n'
  printf 'infra_r2_bucket_bytes %s\n' "${r2_bytes}"
  printf '# HELP infra_r2_object_count Approximate object count under R2 backup prefix\n'
  printf '# TYPE infra_r2_object_count gauge\n'
  printf 'infra_r2_object_count %s\n' "${r2_objects}"
  printf '# HELP infra_r2_soft_max_bytes Soft storage cap (free-tier guard)\n'
  printf '# TYPE infra_r2_soft_max_bytes gauge\n'
  printf 'infra_r2_soft_max_bytes %s\n' "${r2_soft_max}"
  printf '# HELP infra_r2_last_success_timestamp_seconds Unix time of last successful R2 upload\n'
  printf '# TYPE infra_r2_last_success_timestamp_seconds gauge\n'
  if [[ -e "${DATA_ROOT}/backups/full/.last-r2-success" ]]; then
    r2_ts="$(stat -c %Y "${DATA_ROOT}/backups/full/.last-r2-success" 2>/dev/null || echo 0)"
  else
    r2_ts=0
  fi
  printf 'infra_r2_last_success_timestamp_seconds %s\n' "${r2_ts}"
  printf '# HELP infra_r2_last_skip_timestamp_seconds Unix time of last R2 upload skip (soft cap)\n'
  printf '# TYPE infra_r2_last_skip_timestamp_seconds gauge\n'
  if [[ -e "${DATA_ROOT}/backups/full/.last-r2-skip" ]]; then
    r2_skip_ts="$(stat -c %Y "${DATA_ROOT}/backups/full/.last-r2-skip" 2>/dev/null || echo 0)"
  else
    r2_skip_ts=0
  fi
  printf 'infra_r2_last_skip_timestamp_seconds %s\n' "${r2_skip_ts}"
} >"${PARTIAL}"

if ! mv -f "${PARTIAL}" "${OUT_FILE}" 2>/dev/null; then
  sudo mv -f "${PARTIAL}" "${OUT_FILE}"
  sudo chown "${USER:-ubuntu}:${USER:-ubuntu}" "${OUT_FILE}" 2>/dev/null || true
fi
chmod 644 "${OUT_FILE}" 2>/dev/null || sudo chmod 644 "${OUT_FILE}" || true
