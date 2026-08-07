#!/usr/bin/env bash
#
# backup.sh
# Creates a compressed backup with operational project directories and
# persistent data from /opt/docker.
#
# Output:
#   backups/backup-YYYYMMDD-HHMMSS.tar.gz

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

BACKUP_FILE=""
BACKUP_PARTIAL_FILE=""

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

main() {
  local timestamp
  local backup_dir="${PROJECT_ROOT}/backups"
  local data_root
  local data_archive_path
  local original_user="${SUDO_USER:-${USER}}"
  local original_group
  local project_dir
  local tar_args=()
  local active_containers
  local needs_privileged_tar="false"
  local checksum_file
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
  mkdir -p "${backup_dir}"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_FILE="${backup_dir}/backup-${timestamp}.tar.gz"
  BACKUP_PARTIAL_FILE="${BACKUP_FILE}.partial"
  checksum_file="${BACKUP_FILE}.sha256"

  if command -v docker >/dev/null 2>&1; then
    active_containers="$(with_timeout 8 docker ps --format '{{.Names}}' 2>/dev/null || true)"
    if [[ -n "${active_containers}" ]]; then
      warn "Containers are running. Backup will continue, but live data may not be fully consistent."
      printf '%s\n' "${active_containers}" >&2
    fi
  fi

  tar_args=(-czf "${BACKUP_PARTIAL_FILE}" -C "${PROJECT_ROOT}")
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

  rm -f -- "${BACKUP_PARTIAL_FILE}" "${BACKUP_FILE}" "${checksum_file}"

  info "Creating backup ${BACKUP_FILE}"
  # GNU tar exits 1 when a file changes while being read (common with live Traefik logs).
  # Treat that as success for operational live backups; fail on real errors (>=2).
  set +e
  if [[ "${needs_privileged_tar}" == "true" ]]; then
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
  mv "${BACKUP_PARTIAL_FILE}" "${BACKUP_FILE}"
  BACKUP_PARTIAL_FILE=""

  if ! tar -tzf "${BACKUP_FILE}" >/dev/null; then
    rm -f -- "${BACKUP_FILE}"
    die "Backup integrity validation failed. Archive removed."
  fi

  sha256sum "${BACKUP_FILE}" >"${checksum_file}"
  set_backup_file_permissions "${checksum_file}" "${original_user}" "${original_group}" "false"

  ok "Backup created: ${BACKUP_FILE}"
  kv "Size" "$(bytes_to_human "${BACKUP_FILE}")"
  kv "SHA-256" "${checksum_file}"
}

main "$@"
