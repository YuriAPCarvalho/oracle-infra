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
trap 'on_error "$?" "$LINENO"' ERR

main() {
  local timestamp
  local backup_dir="${PROJECT_ROOT}/backups"
  local backup_file
  local project_dir
  local tar_args=()
  local active_containers
  local project_dirs=(
    compose
    configs
    bootstrap
    scripts
    docs
  )

  require_command tar

  mkdir -p "${backup_dir}"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_file="${backup_dir}/backup-${timestamp}.tar.gz"

  if command -v docker >/dev/null 2>&1; then
    active_containers="$(with_timeout 8 docker ps --format '{{.Names}}' 2>/dev/null || true)"
    if [[ -n "${active_containers}" ]]; then
      warn "Containers are running. Backup will continue, but live data may not be fully consistent."
      printf '%s\n' "${active_containers}" >&2
    fi
  fi

  tar_args=(-czf "${backup_file}" -C "${PROJECT_ROOT}")
  for project_dir in "${project_dirs[@]}"; do
    if [[ -e "${PROJECT_ROOT}/${project_dir}" ]]; then
      tar_args+=("${project_dir}")
    else
      warn "Skipping missing directory: ${project_dir}"
    fi
  done

  if [[ -d "${DATA_ROOT}" ]]; then
    tar_args+=(-C / opt/docker)
  else
    warn "Skipping missing persistent data directory: ${DATA_ROOT}"
  fi

  info "Creating backup ${backup_file}"
  tar "${tar_args[@]}"

  ok "Backup created: ${backup_file}"
  kv "Size" "$(bytes_to_human "${backup_file}")"
}

main "$@"
