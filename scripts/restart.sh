#!/usr/bin/env bash
#
# restart.sh
# Restarts one managed service or all managed services after validating that
# the service compose file and container exist.
#
# Usage:
#   ./scripts/restart.sh traefik
#   ./scripts/restart.sh all

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

usage() {
  cat <<'EOF'
Usage: restart.sh <service|all>

Managed services:
  traefik
  portainer
  dozzle
  uptime-kuma
EOF
}

restart_service() {
  local service="$1"
  local compose_file

  is_managed_service "${service}" ||
    die "Unknown managed service: ${service}"

  container_exists "${service}" ||
    die "Container not found: ${service}"

  compose_file="$(service_compose_file "${service}")"
  validate_compose_file "${compose_file}"

  info "Restarting ${service}"
  docker compose -f "${compose_file}" restart "${service}"
  ok "${service} restarted"
}

main() {
  local target="${1:-}"
  local service

  if [[ "${target}" == "-h" || "${target}" == "--help" ]]; then
    usage
    exit 0
  fi

  [[ -n "${target}" ]] || {
    usage
    exit 1
  }

  require_command docker

  if [[ "${target}" == "all" ]]; then
    for service in "${SERVICES[@]}"; do
      restart_service "${service}"
    done
    return 0
  fi

  restart_service "${target}"
}

main "$@"
