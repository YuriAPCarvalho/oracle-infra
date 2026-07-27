#!/usr/bin/env bash
#
# update.sh
# Updates the local repository and all Docker Compose services. It validates
# compose files, pulls images, recreates services when needed, and never runs
# prune or removes volumes.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

main() {
  local compose_file
  local service

  require_command git
  require_command docker

  info "Updating repository"
  git -C "${PROJECT_ROOT}" pull --ff-only

  section "Validating compose files"
  while IFS= read -r compose_file; do
    info "Validating ${compose_file}"
    validate_compose_file "${compose_file}"
  done < <(compose_files)

  section "Pulling images"
  while IFS= read -r compose_file; do
    # Local-only images (e.g. service:local) have no registry remotes.
    if ! docker compose -f "${compose_file}" pull; then
      warn "Pull skipped/failed for ${compose_file} (local image or registry unavailable)"
    fi
  done < <(compose_files)

  section "Applying compose services"
  while IFS= read -r compose_file; do
    docker compose -f "${compose_file}" up -d
  done < <(compose_files)

  section "Summary"
  for service in "${SERVICES[@]}"; do
    if container_exists "${service}"; then
      kv "${service}" "$(docker inspect -f '{{.State.Status}} - {{.Config.Image}}' "${service}")"
    else
      kv "${service}" "not found"
    fi
  done
}

main "$@"
