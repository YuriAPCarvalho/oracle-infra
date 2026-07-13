#!/usr/bin/env bash
#
# logs.sh
# Shows logs for a managed service, an existing container, or all managed
# services. Supports --tail/-n and --follow/-f.
#
# Usage:
#   ./scripts/logs.sh traefik
#   ./scripts/logs.sh portainer --tail 200
#   ./scripts/logs.sh all --follow

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

FOLLOW_PIDS=()

usage() {
  cat <<'EOF'
Usage: logs.sh <service|container|all> [--tail N] [--follow]

Options:
  -n, --tail N    Number of lines to show (default: 100)
  -f, --follow    Follow log output
  -h, --help      Show this help
EOF
}

docker_logs_args() {
  local tail="$1"
  local follow="$2"

  printf '%s\0%s\0' "--tail" "${tail}"

  if [[ "${follow}" == "true" ]]; then
    printf '%s\0' "--follow"
  fi

  return 0
}

show_container_logs() {
  local container="$1"
  local tail="$2"
  local follow="$3"
  local args=()

  mapfile -d '' -t args < <(docker_logs_args "${tail}" "${follow}")
  docker logs "${args[@]}" "${container}"
}

cleanup_follow_processes() {
  local process_pid

  for process_pid in "${FOLLOW_PIDS[@]}"; do
    kill "${process_pid}" 2>/dev/null || true
  done
}

show_all_logs() {
  local tail="$1"
  local follow="$2"
  local service

  if [[ "${follow}" != "true" ]]; then
    for service in "${SERVICES[@]}"; do
      if container_exists "${service}"; then
        section "${service}"
        show_container_logs "${service}" "${tail}" "false"
      else
        warn "Container not found: ${service}"
      fi
    done
    return 0
  fi

  trap cleanup_follow_processes INT TERM EXIT

  for service in "${SERVICES[@]}"; do
    if container_exists "${service}"; then
      info "Following ${service}"
      show_container_logs "${service}" "${tail}" "true" &
      FOLLOW_PIDS+=("$!")
    else
      warn "Container not found: ${service}"
    fi
  done

  [[ "${#FOLLOW_PIDS[@]}" -gt 0 ]] || die "No managed containers found."
  wait
}

main() {
  local target="${1:-}"
  local tail="100"
  local follow="false"
  local container

  if [[ "${target}" == "-h" || "${target}" == "--help" ]]; then
    usage
    exit 0
  fi

  [[ -n "${target}" ]] || {
    usage
    exit 1
  }

  shift || true

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -n|--tail)
        [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--tail requires a numeric value"
        tail="$2"
        shift 2
        ;;
      --tail=*)
        tail="${1#*=}"
        [[ "${tail}" =~ ^[0-9]+$ ]] || die "--tail requires a numeric value"
        shift
        ;;
      -f|--follow)
        follow="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  require_command docker

  if [[ "${target}" == "all" ]]; then
    show_all_logs "${tail}" "${follow}"
    return 0
  fi

  container="$(resolve_container "${target}" 2>/dev/null || true)"
  [[ -n "${container}" ]] || die "Service or container not found: ${target}"

  show_container_logs "${container}" "${tail}" "${follow}"
}

main "$@"
