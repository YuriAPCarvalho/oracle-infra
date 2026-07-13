#!/usr/bin/env bash
#
# shell.sh
# Opens an interactive shell in a running container. It automatically detects
# bash, sh, or ash.
#
# Usage:
#   ./scripts/shell.sh portainer

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

usage() {
  cat <<'EOF'
Usage: shell.sh <service|container>
EOF
}

main() {
  local target="${1:-}"
  local container
  local shell_name

  if [[ "${target}" == "-h" || "${target}" == "--help" ]]; then
    usage
    exit 0
  fi

  [[ -n "${target}" ]] || {
    usage
    exit 1
  }

  require_command docker

  container="$(resolve_container "${target}" 2>/dev/null || true)"
  [[ -n "${container}" ]] || die "Service or container not found: ${target}"

  container_running "${container}" ||
    die "Container is not running: ${container}"

  for shell_name in bash sh ash; do
    if docker exec "${container}" command -v "${shell_name}" >/dev/null 2>&1; then
      info "Opening ${shell_name} in ${container}"
      exec docker exec -it "${container}" "${shell_name}"
    fi
  done

  die "No supported shell found in ${container} (bash, sh, ash)."
}

main "$@"
