#!/usr/bin/env bash
#
# validate-workflows.sh
# Runs actionlint on active workflows and on template workflows with
# placeholders substituted for lint-only synthetic values.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

ACTIONLINT_BIN="${ACTIONLINT_BIN:-${PROJECT_ROOT}/.tools/actionlint}"
VALIDATE_TMPDIR=""

cleanup_tmpdir() {
  if [[ -n "${VALIDATE_TMPDIR}" && -d "${VALIDATE_TMPDIR}" ]]; then
    rm -rf "${VALIDATE_TMPDIR}"
  fi
}

ensure_actionlint() {
  if [[ -x "${ACTIONLINT_BIN}" ]]; then
    return 0
  fi
  if command -v actionlint >/dev/null 2>&1; then
    ACTIONLINT_BIN="$(command -v actionlint)"
    return 0
  fi

  info "actionlint not found; installing pinned release into .tools/"
  bash "${SCRIPT_DIR}/install-actionlint.sh" "${PROJECT_ROOT}/.tools"
  ACTIONLINT_BIN="${PROJECT_ROOT}/.tools/actionlint"
}

render_templates() {
  local out_dir="$1"
  local file base

  mkdir -p "${out_dir}"
  for file in "${PROJECT_ROOT}/templates/github-actions/"*.yml; do
    [[ -f "${file}" ]] || continue
    base="$(basename "${file}")"
    sed \
      -e 's/<OWNER_OR_ORG>/example-org/g' \
      -e 's/<SERVICE_NAME>/example-service/g' \
      -e 's/<PRODUCTION_BRANCH>/main/g' \
      -e 's/<BUILD_CONTEXT>/./g' \
      -e 's/<DOCKERFILE_PATH>/Dockerfile/g' \
      -e 's/<TEST_COMMAND>/echo tests/g' \
      -e 's/<HEALTH_MODE>/running/g' \
      "${file}" >"${out_dir}/${base}"
  done
}

assert_no_secrets_in_templates() {
  if git -C "${PROJECT_ROOT}" grep -nIE -- \
    '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9_]{30,}|https://discord(app)?\.com/api/webhooks/[0-9]+/' \
    -- 'templates/github-actions' 2>/dev/null; then
    die "Potential secret detected in github-actions templates"
  fi
  ok "Template secret scan passed"
}

main() {
  ensure_actionlint
  require_command git
  trap cleanup_tmpdir EXIT

  section "actionlint: active workflows"
  "${ACTIONLINT_BIN}" -color \
    "${PROJECT_ROOT}/.github/workflows/infra.yml" \
    "${PROJECT_ROOT}/.github/workflows/reusable-docker-build.yml" \
    "${PROJECT_ROOT}/.github/workflows/reusable-vps-deploy.yml"
  ok "Active workflows passed actionlint"

  section "actionlint: rendered templates"
  VALIDATE_TMPDIR="$(mktemp -d)"
  render_templates "${VALIDATE_TMPDIR}"
  "${ACTIONLINT_BIN}" -color "${VALIDATE_TMPDIR}"/*.yml
  ok "Rendered templates passed actionlint"

  assert_no_secrets_in_templates
}

main "$@"
