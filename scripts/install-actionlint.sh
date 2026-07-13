#!/usr/bin/env bash
#
# install-actionlint.sh
# Downloads a pinned actionlint release with SHA256 verification.
# Usage: bash scripts/install-actionlint.sh [install-dir]

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

ACTIONLINT_VERSION="1.7.12"
INSTALL_DIR="${1:-${PROJECT_ROOT}/.tools}"
BASE_URL="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}"
INSTALL_TMPDIR=""

cleanup_tmpdir() {
  if [[ -n "${INSTALL_TMPDIR}" && -d "${INSTALL_TMPDIR}" ]]; then
    rm -rf "${INSTALL_TMPDIR}"
  fi
}

# Checksums from the official checksums.txt for v1.7.7 (verified at pin time).
# Source: https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_1.7.7_checksums.txt
checksum_for() {
  case "$1" in
    linux_amd64) printf '%s\n' "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8" ;;
    linux_arm64) printf '%s\n' "325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6" ;;
    darwin_amd64) printf '%s\n' "5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644" ;;
    darwin_arm64) printf '%s\n' "aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f" ;;
    windows_amd64) printf '%s\n' "6e7241b51e6817ea6a047693d8e6fed13b31819c9a0dd6c5a726e1592d22f6e9" ;;
    windows_arm64) printf '%s\n' "cadcf7ea4efe3a68728893813643cebe1185e5b1d4be5b96245f65c9a4d5ea41" ;;
    *) return 1 ;;
  esac
}

detect_target() {
  local os arch

  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "${os}" in
    linux) os="linux" ;;
    darwin) os="darwin" ;;
    mingw* | msys* | cygwin*) os="windows" ;;
    *) die "Unsupported OS for actionlint install: ${os}" ;;
  esac

  case "${arch}" in
    x86_64 | amd64) arch="amd64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *) die "Unsupported architecture for actionlint install: ${arch}" ;;
  esac

  printf '%s_%s\n' "${os}" "${arch}"
}

verify_sha256() {
  local file="$1"
  local expected="$2"
  local actual

  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${file}" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "${file}" | awk '{print $1}')"
  else
    die "sha256sum or shasum is required to verify actionlint"
  fi

  [[ "${actual}" == "${expected}" ]] ||
    die "Checksum mismatch for ${file}: expected ${expected}, got ${actual}"
}

main() {
  local target archive_name url expected archive bin_name

  require_command curl
  require_command tar
  require_command uname

  trap cleanup_tmpdir EXIT

  target="$(detect_target)"
  expected="$(checksum_for "${target}")" || die "No pinned checksum for target ${target}"

  if [[ "${#expected}" -ne 64 ]]; then
    die "Refusing to install actionlint for ${target}: invalid checksum pin"
  fi

  archive_name="actionlint_${ACTIONLINT_VERSION}_${target}.tar.gz"
  url="${BASE_URL}/${archive_name}"
  bin_name="actionlint"
  if [[ "${target}" == windows_* ]]; then
    archive_name="actionlint_${ACTIONLINT_VERSION}_${target}.zip"
    url="${BASE_URL}/${archive_name}"
    bin_name="actionlint.exe"
  fi

  mkdir -p "${INSTALL_DIR}"
  INSTALL_TMPDIR="$(mktemp -d)"
  archive="${INSTALL_TMPDIR}/${archive_name}"

  info "Downloading actionlint v${ACTIONLINT_VERSION} (${target})"
  curl -fsSL --retry 3 --retry-delay 1 -o "${archive}" "${url}"
  verify_sha256 "${archive}" "${expected}"
  ok "Checksum verified"

  if [[ "${archive_name}" == *.zip ]]; then
    require_command unzip
    unzip -q "${archive}" -d "${INSTALL_TMPDIR}"
  else
    tar -xzf "${archive}" -C "${INSTALL_TMPDIR}" "${bin_name}"
  fi

  if [[ ! -f "${INSTALL_TMPDIR}/${bin_name}" ]]; then
    die "actionlint binary missing after extract"
  fi

  if command -v install >/dev/null 2>&1; then
    install -m 0755 "${INSTALL_TMPDIR}/${bin_name}" "${INSTALL_DIR}/actionlint"
  else
    cp "${INSTALL_TMPDIR}/${bin_name}" "${INSTALL_DIR}/actionlint"
    chmod 0755 "${INSTALL_DIR}/actionlint"
  fi
  ok "Installed ${INSTALL_DIR}/actionlint"
  "${INSTALL_DIR}/actionlint" -version
}

main "$@"
