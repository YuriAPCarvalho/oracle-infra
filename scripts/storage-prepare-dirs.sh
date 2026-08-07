#!/usr/bin/env bash
#
# storage-prepare-dirs.sh
# Creates the canonical /opt/docker hierarchy with ownership.
# Safe to re-run. Does not migrate existing flat paths (see runbook).
#
# Usage:
#   bash scripts/storage-prepare-dirs.sh
#   DATA_ROOT=/mnt/docker-new bash scripts/storage-prepare-dirs.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/storage-layout.sh
source "${SCRIPT_DIR}/lib/storage-layout.sh"

main() {
  local root
  root="$(persistent_data_root)"

  info "Preparing storage layout under ${root}"
  ensure_storage_dirs "${root}"
  apply_storage_special_ownership "${root}"
  ok "Storage directories ready"
  section "Layout"
  if command -v find >/dev/null 2>&1; then
    find "${root}" -maxdepth 3 -type d 2>/dev/null | sort || true
  fi
}

main "$@"
