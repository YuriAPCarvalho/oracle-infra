#!/usr/bin/env bash
#
# backup.sh
# Layer-1 operational backup: logical dumps + tar of project dirs and DATA_ROOT.
# Writes under ${DATA_ROOT}/backups/full/ (fallback: PROJECT_ROOT/backups).
#
# Env:
#   BACKUP_RETENTION_DAYS   delete full archives older than N days (default 7)
#   BACKUP_KEEP_LAST        always keep at least N full archives (default 5)
#   BACKUP_SKIP_PG_DUMP     set to 1 to skip postgres logical dump
#   BACKUP_INCLUDE_PROMETHEUS  set to 1 to include monitoring/prometheus in tar
#   BACKUP_DIR              override output directory
#
# Output:
#   backups/full/backup-YYYYMMDD-HHMMSS.tar.gz
#   backups/full/backup-YYYYMMDD-HHMMSS.tar.gz.sha256
#   backups/full/backup-YYYYMMDD-HHMMSS.meta.json

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/storage-layout.sh
source "${SCRIPT_DIR}/lib/storage-layout.sh"

BACKUP_FILE=""
BACKUP_PARTIAL_FILE=""
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
BACKUP_KEEP_LAST="${BACKUP_KEEP_LAST:-5}"
BACKUP_SKIP_PG_DUMP="${BACKUP_SKIP_PG_DUMP:-0}"
BACKUP_INCLUDE_PROMETHEUS="${BACKUP_INCLUDE_PROMETHEUS:-0}"

backup_error() {
  local exit_code="$1"
  local line="$2"

  if [[ -n "${BACKUP_PARTIAL_FILE}" && -e "${BACKUP_PARTIAL_FILE}" ]]; then
    rm -f -- "${BACKUP_PARTIAL_FILE}" || true
  fi

  fail "Backup failed at line ${line} (exit ${exit_code}). Partial archive removed."
  exit "${exit_code}"
}

trap 'backup_error "$?" "$LINENO"' ERR

run_privileged() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

set_backup_file_permissions() {
  local file="$1"
  local original_user="$2"
  local original_group="$3"
  local needs_privilege="$4"

  if [[ "${EUID}" -eq 0 ]]; then
    chown "${original_user}:${original_group}" "${file}"
  elif [[ "${needs_privilege}" == "true" ]]; then
    sudo chown "${original_user}:${original_group}" "${file}"
  fi

  chmod 600 "${file}"
}

resolve_backup_dir() {
  local data_root="$1"
  local preferred="${BACKUP_DIR:-}"

  if [[ -n "${preferred}" ]]; then
    mkdir -p "${preferred}"
    printf '%s\n' "${preferred}"
    return 0
  fi

  if [[ -d "${data_root}" ]]; then
    run_privileged mkdir -p "${data_root}/backups/full" "${data_root}/backups/postgres" \
      "${data_root}/backups/minio" "${data_root}/backups/redis" \
      "${data_root}/backups/grafana" "${data_root}/backups/prometheus" \
      "${data_root}/backups/applications" 2>/dev/null || true
    if [[ -w "${data_root}/backups/full" ]] || run_privileged test -d "${data_root}/backups/full"; then
      printf '%s\n' "${data_root}/backups/full"
      return 0
    fi
  fi

  mkdir -p "${PROJECT_ROOT}/backups"
  printf '%s\n' "${PROJECT_ROOT}/backups"
}

logical_postgres_dump() {
  local data_root="$1"
  local stamp="$2"
  local out_dir="${data_root}/backups/postgres"
  local out_file="${out_dir}/postgres-all-${stamp}.sql.gz"

  if [[ "${BACKUP_SKIP_PG_DUMP}" == "1" ]]; then
    warn "Skipping Postgres logical dump (BACKUP_SKIP_PG_DUMP=1)"
    return 0
  fi

  if ! command -v docker >/dev/null 2>&1; then
    warn "docker not available; skipping Postgres dump"
    return 0
  fi

  if ! container_running postgres; then
    warn "postgres container not running; skipping logical dump"
    return 0
  fi

  run_privileged mkdir -p "${out_dir}"
  info "Creating Postgres logical dump ${out_file}"
  if docker exec postgres pg_dumpall -U postgres | gzip >"${out_file}.partial"; then
    mv "${out_file}.partial" "${out_file}"
    chmod 600 "${out_file}"
    ok "Postgres dump: ${out_file}"
  else
    rm -f -- "${out_file}.partial" || true
    warn "Postgres dump failed; continuing with filesystem backup"
  fi
}

write_backup_meta() {
  local meta_file="$1"
  local backup_file="$2"
  local data_root="$3"
  local stamp="$4"
  local size_bytes="0"

  if [[ -f "${backup_file}" ]]; then
    size_bytes="$(wc -c <"${backup_file}" | tr -d ' ')"
  fi

  cat >"${meta_file}" <<EOF
{
  "timestamp": "${stamp}",
  "hostname": "$(hostname -f 2>/dev/null || hostname || echo unknown)",
  "data_root": "${data_root}",
  "archive": "$(basename "${backup_file}")",
  "size_bytes": ${size_bytes},
  "include_prometheus": ${BACKUP_INCLUDE_PROMETHEUS},
  "layers": {
    "local": true,
    "oci_volume_backup": "manual",
    "object_storage_upload": "hook-not-implemented"
  }
}
EOF
  chmod 600 "${meta_file}"
}

apply_retention() {
  local backup_dir="$1"
  local keep_last="${BACKUP_KEEP_LAST}"
  local retention_days="${BACKUP_RETENTION_DAYS}"
  local files=()
  local f
  local count=0

  shopt -s nullglob
  files=("${backup_dir}"/backup-*.tar.gz)
  shopt -u nullglob

  if [[ "${#files[@]}" -eq 0 ]]; then
    return 0
  fi

  # Newest first
  mapfile -t files < <(printf '%s\n' "${files[@]}" | sort -r)

  for f in "${files[@]}"; do
    count=$((count + 1))
    if [[ "${count}" -le "${keep_last}" ]]; then
      continue
    fi
    if [[ "${retention_days}" =~ ^[0-9]+$ ]] && [[ "${retention_days}" -gt 0 ]]; then
      if [[ "$(find "${f}" -mtime "+${retention_days}" 2>/dev/null || true)" == "${f}" ]]; then
        info "Retention: removing ${f}"
        rm -f -- "${f}" "${f}.sha256" "${f%.tar.gz}.meta.json" || true
        # meta naming: backup-TS.meta.json alongside backup-TS.tar.gz
        rm -f -- "${f%.tar.gz}.meta.json" || true
      fi
    fi
  done

  # Second pass: if still more than keep_last after age filter, trim oldest
  shopt -s nullglob
  files=("${backup_dir}"/backup-*.tar.gz)
  shopt -u nullglob
  mapfile -t files < <(printf '%s\n' "${files[@]}" | sort -r)
  count=0
  for f in "${files[@]}"; do
    count=$((count + 1))
    if [[ "${count}" -gt "${keep_last}" ]]; then
      info "Retention keep_last=${keep_last}: removing ${f}"
      rm -f -- "${f}" "${f}.sha256" "${f%.tar.gz}.meta.json" || true
    fi
  done
}

run_post_backup_hooks() {
  local backup_file="$1"
  local meta_file="$2"
  local hooks_dir="${SCRIPT_DIR}/backup/hooks"
  local hook

  if [[ ! -d "${hooks_dir}" ]]; then
    return 0
  fi

  shopt -s nullglob
  for hook in "${hooks_dir}"/*.sh; do
    if [[ -x "${hook}" ]]; then
      info "Running post-backup hook $(basename "${hook}")"
      BACKUP_ARCHIVE="${backup_file}" BACKUP_META="${meta_file}" bash "${hook}" ||
        warn "Hook failed: ${hook}"
    fi
  done
  shopt -u nullglob
}

main() {
  local timestamp
  local backup_dir
  local data_root
  local data_archive_path
  local original_user="${SUDO_USER:-${USER}}"
  local original_group
  local project_dir
  local tar_args=()
  local active_containers
  local needs_privileged_tar="false"
  local checksum_file
  local meta_file
  local exclude_args=()
  local project_dirs=(
    compose
    configs
    bootstrap
    scripts
    docs
  )

  require_command tar
  require_command sha256sum

  original_group="$(id -gn "${original_user}")"
  umask 077

  data_root="$(persistent_data_root)"
  backup_dir="$(resolve_backup_dir "${data_root}")"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="${backup_dir}/backup-${timestamp}.tar.gz"
  BACKUP_PARTIAL_FILE="${BACKUP_FILE}.partial"
  checksum_file="${BACKUP_FILE}.sha256"
  meta_file="${backup_dir}/backup-${timestamp}.meta.json"

  if [[ ! -w "$(dirname "${BACKUP_FILE}")" ]]; then
    needs_privileged_tar="true"
  fi

  if command -v docker >/dev/null 2>&1; then
    active_containers="$(with_timeout 8 docker ps --format '{{.Names}}' 2>/dev/null || true)"
    if [[ -n "${active_containers}" ]]; then
      warn "Containers are running. Backup will continue, but live data may not be fully consistent."
      printf '%s\n' "${active_containers}" >&2
    fi
  fi

  logical_postgres_dump "${data_root}" "${timestamp}"

  # Exclude nested full archives and optional prometheus TSDB from the tar payload.
  exclude_args+=(--exclude="${data_root#/}/backups/full")
  if [[ "${BACKUP_INCLUDE_PROMETHEUS}" != "1" ]]; then
    exclude_args+=(--exclude="${data_root#/}/monitoring/prometheus")
  fi

  tar_args=(-czf "${BACKUP_PARTIAL_FILE}")
  tar_args+=("${exclude_args[@]}")
  tar_args+=(-C "${PROJECT_ROOT}")
  for project_dir in "${project_dirs[@]}"; do
    if [[ -e "${PROJECT_ROOT}/${project_dir}" ]]; then
      tar_args+=("${project_dir}")
    else
      warn "Skipping missing directory: ${project_dir}"
    fi
  done

  if [[ -d "${data_root}" ]]; then
    data_archive_path="${data_root#/}"
    tar_args+=(-C / "${data_archive_path}")
    if [[ "${EUID}" -ne 0 ]]; then
      needs_privileged_tar="true"
    fi
  else
    warn "Skipping missing persistent data directory: ${data_root}"
  fi

  rm -f -- "${BACKUP_PARTIAL_FILE}" "${BACKUP_FILE}" "${checksum_file}" "${meta_file}"

  info "Creating backup ${BACKUP_FILE}"
  # GNU tar exits 1 when a file changes while being read (common with live Traefik logs).
  set +e
  if [[ "${needs_privileged_tar}" == "true" ]]; then
    # Write partial as root then re-own
    run_privileged tar "${tar_args[@]}"
  else
    tar "${tar_args[@]}"
  fi
  tar_rc=$?
  set -e
  if [[ "${tar_rc}" -gt 1 ]]; then
    die "tar failed with exit code ${tar_rc}"
  fi
  if [[ "${tar_rc}" -eq 1 ]]; then
    warn "tar reported files changed during read (exit 1); archive kept for live backup."
  fi

  set_backup_file_permissions "${BACKUP_PARTIAL_FILE}" "${original_user}" "${original_group}" "${needs_privileged_tar}"
  if [[ "${needs_privileged_tar}" == "true" && "${EUID}" -ne 0 ]]; then
    sudo mv "${BACKUP_PARTIAL_FILE}" "${BACKUP_FILE}"
  else
    mv "${BACKUP_PARTIAL_FILE}" "${BACKUP_FILE}"
  fi
  BACKUP_PARTIAL_FILE=""

  if ! tar -tzf "${BACKUP_FILE}" >/dev/null; then
    rm -f -- "${BACKUP_FILE}"
    die "Backup integrity validation failed. Archive removed."
  fi

  sha256sum "${BACKUP_FILE}" >"${checksum_file}"
  set_backup_file_permissions "${checksum_file}" "${original_user}" "${original_group}" "false"

  write_backup_meta "${meta_file}" "${BACKUP_FILE}" "${data_root}" "${timestamp}"
  set_backup_file_permissions "${meta_file}" "${original_user}" "${original_group}" "false"

  apply_retention "${backup_dir}"
  run_post_backup_hooks "${BACKUP_FILE}" "${meta_file}"

  # Touch marker for BackupStale alert (mtime of latest successful backup)
  touch "${backup_dir}/.last-success" 2>/dev/null ||
    run_privileged touch "${backup_dir}/.last-success" || true

  ok "Backup created: ${BACKUP_FILE}"
  kv "Size" "$(bytes_to_human "${BACKUP_FILE}")"
  kv "SHA-256" "${checksum_file}"
  kv "Meta" "${meta_file}"
}

main "$@"
