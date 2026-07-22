#!/usr/bin/env bash
#
# ci-deploy-service.sh
# Controlled single-service deploy for GitHub Actions over SSH.
# Does not prune, remove volumes, reset git hard, or alter /opt/docker data permissions.
#
# Prefer --config FILE (KEY=VALUE) from the GHA runner to avoid remote shell injection.
# Experimental until validated with a real application deploy (e.g. bot-ponto).

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

INFRA_ROOT="${INFRA_ROOT:-/opt/infra}"
COMPOSE_ROOT="${COMPOSE_ROOT:-${INFRA_ROOT}/compose}"
DATA_ROOT="${DATA_ROOT:-/opt/docker}"
DEPLOY_STATE_ROOT="${DEPLOY_STATE_ROOT:-${DATA_ROOT}/deploy-state}"
LOCK_DIR="${LOCK_DIR:-${INFRA_ROOT}/.locks}"
GIT_LOCK_FILE="${LOCK_DIR}/git.lock"
SERVICE_LOCK_FILE=""

SERVICE_NAME=""
IMAGE_REPO=""
IMAGE_TAG=""
COMPOSE_REL=""
COMPOSE_DIR=""
COMPOSE_FILE=""
CONTAINER_NAME=""
HEALTH_MODE="running"
HEALTH_COMMAND=""
HEALTH_URL=""
HEALTH_TIMEOUT=120
HEALTH_RETRIES=12
ENABLE_ROLLBACK=1
SKIP_GIT_PULL=0
DRY_RUN=0
REPORT_FILE=""
GITHUB_RUN_URL=""
GITHUB_SHA=""
PREVIOUS_IMAGE=""
NEW_IMAGE=""
STATE_IMAGE=""
ROLLBACK_PERFORMED=0
DEPLOY_RESULT="failure"
STARTED_AT=""
FINISHED_AT=""
STATE_DIR=""
GIT_LOCK_FD=""
SERVICE_LOCK_FD=""

usage() {
  cat <<'EOF'
Usage:
  ci-deploy-service.sh --config /path/to/deploy.env
  ci-deploy-service.sh [options]

Config file (preferred): KEY=VALUE lines, allowed keys only.

Required (config or flags):
  SERVICE_NAME / --service
  IMAGE_REPO / --image
  IMAGE_TAG / --tag
  COMPOSE_REL / --compose-dir   relative under /opt/infra (e.g. compose/my-svc)
  CONTAINER_NAME / --container

Optional:
  HEALTH_MODE / --health-mode           running|docker|http|exec
  HEALTH_COMMAND / --health-command
  HEALTH_URL / --health-url
  HEALTH_TIMEOUT / --health-timeout
  HEALTH_RETRIES / --health-retries
  ENABLE_ROLLBACK / --enable-rollback|--no-rollback
  SKIP_GIT_PULL / --skip-git-pull
  REPORT_FILE / --report-file
  GITHUB_RUN_URL / --github-run-url
  GITHUB_SHA / --github-sha
  --dry-run                             validate only; no pull/git/container/state writes
  -h, --help
EOF
}

is_safe_token() {
  # Letters, digits, dot, underscore, hyphen; 1..64 chars; must start alnum.
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$ ]]
}

is_safe_image_repo() {
  # registry/owner/name or owner/name segments
  [[ "$1" =~ ^[a-z0-9._/-]+$ ]] && [[ "$1" != *..* ]] && [[ "$1" != /* ]] && [[ "$1" == */* ]]
}

is_safe_tag() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$ ]]
}

is_safe_relative_compose() {
  local rel="$1"
  # Must be relative, under compose/, single extra segment, no metacharacters.
  [[ "${rel}" =~ ^compose/[a-zA-Z0-9][a-zA-Z0-9._-]*$ ]] || return 1
  [[ "${rel}" != *..* ]] || return 1
  [[ "${rel}" != /* ]] || return 1
  [[ "${rel}" != *[[:space:]]* ]] || return 1
  [[ "${rel}" != *[\`\$\;\|\&\<\>\(\)\{\}\[\]\'\"\\]* ]] || return 1
  return 0
}

load_config_file() {
  local file="$1"
  local line key value
  local -A seen=()

  [[ -f "${file}" ]] || die "Config file not found: ${file}"
  # Prefer mode 600; warn only if inspection fails or differs.
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[A-Z_][A-Z0-9_]*= ]] || die "Invalid config line: ${line}"
    key="${line%%=*}"
    value="${line#*=}"
    [[ -z "${seen[$key]+x}" ]] || die "Duplicate config key: ${key}"
    seen["${key}"]=1

    case "${key}" in
      SERVICE_NAME) SERVICE_NAME="${value}" ;;
      IMAGE_REPO) IMAGE_REPO="${value}" ;;
      IMAGE_TAG) IMAGE_TAG="${value}" ;;
      COMPOSE_REL) COMPOSE_REL="${value}" ;;
      CONTAINER_NAME) CONTAINER_NAME="${value}" ;;
      HEALTH_MODE) HEALTH_MODE="${value}" ;;
      HEALTH_COMMAND) HEALTH_COMMAND="${value}" ;;
      HEALTH_URL) HEALTH_URL="${value}" ;;
      HEALTH_TIMEOUT) HEALTH_TIMEOUT="${value}" ;;
      HEALTH_RETRIES) HEALTH_RETRIES="${value}" ;;
      ENABLE_ROLLBACK)
        case "${value}" in
          1 | true | yes) ENABLE_ROLLBACK=1 ;;
          0 | false | no) ENABLE_ROLLBACK=0 ;;
          *) die "Invalid ENABLE_ROLLBACK: ${value}" ;;
        esac
        ;;
      SKIP_GIT_PULL)
        case "${value}" in
          1 | true | yes) SKIP_GIT_PULL=1 ;;
          0 | false | no) SKIP_GIT_PULL=0 ;;
          *) die "Invalid SKIP_GIT_PULL: ${value}" ;;
        esac
        ;;
      REPORT_FILE) REPORT_FILE="${value}" ;;
      GITHUB_RUN_URL) GITHUB_RUN_URL="${value}" ;;
      GITHUB_SHA) GITHUB_SHA="${value}" ;;
      DRY_RUN)
        case "${value}" in
          1 | true | yes) DRY_RUN=1 ;;
          0 | false | no) DRY_RUN=0 ;;
          *) die "Invalid DRY_RUN: ${value}" ;;
        esac
        ;;
      *) die "Unknown config key: ${key}" ;;
    esac
  done <"${file}"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        load_config_file "${2:-}"
        shift 2
        ;;
      --service) SERVICE_NAME="${2:-}"; shift 2 ;;
      --image) IMAGE_REPO="${2:-}"; shift 2 ;;
      --tag) IMAGE_TAG="${2:-}"; shift 2 ;;
      --compose-dir) COMPOSE_REL="${2:-}"; shift 2 ;;
      --container) CONTAINER_NAME="${2:-}"; shift 2 ;;
      --health-mode) HEALTH_MODE="${2:-}"; shift 2 ;;
      --health-command) HEALTH_COMMAND="${2:-}"; shift 2 ;;
      --health-url) HEALTH_URL="${2:-}"; shift 2 ;;
      --health-timeout) HEALTH_TIMEOUT="${2:-}"; shift 2 ;;
      --health-retries) HEALTH_RETRIES="${2:-}"; shift 2 ;;
      --enable-rollback) ENABLE_ROLLBACK=1; shift ;;
      --no-rollback) ENABLE_ROLLBACK=0; shift ;;
      --skip-git-pull) SKIP_GIT_PULL=1; shift ;;
      --report-file) REPORT_FILE="${2:-}"; shift 2 ;;
      --github-run-url) GITHUB_RUN_URL="${2:-}"; shift 2 ;;
      --github-sha) GITHUB_SHA="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
}

resolve_compose_path() {
  local candidate resolved root_resolved

  is_safe_relative_compose "${COMPOSE_REL}" ||
    die "compose-dir must be relative like compose/<service> (got: ${COMPOSE_REL})"

  [[ "${COMPOSE_REL}" == /* ]] && die "Absolute compose-dir is not allowed from caller"

  candidate="${INFRA_ROOT}/${COMPOSE_REL}"
  [[ -e "${candidate}" ]] || die "Compose directory not found: ${candidate}"

  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "${candidate}")"
    root_resolved="$(realpath "${COMPOSE_ROOT}")"
  else
    resolved="$(cd "${candidate}" && pwd -P)"
    root_resolved="$(cd "${COMPOSE_ROOT}" && pwd -P)"
  fi

  case "${resolved}" in
    "${root_resolved}" | "${root_resolved}"/*) ;;
    *) die "Compose path escapes allowed root ${COMPOSE_ROOT}: ${resolved}" ;;
  esac

  # Reject if the path is a symlink that left the root after resolution (already covered),
  # or if compose.yml itself is a symlink escaping root.
  COMPOSE_DIR="${resolved}"
  COMPOSE_FILE="${COMPOSE_DIR}/compose.yml"
  [[ -f "${COMPOSE_FILE}" ]] || die "Compose file not found: ${COMPOSE_FILE}"

  if command -v realpath >/dev/null 2>&1; then
    local compose_resolved
    compose_resolved="$(realpath "${COMPOSE_FILE}")"
    case "${compose_resolved}" in
      "${root_resolved}" | "${root_resolved}"/*) ;;
      *) die "compose.yml symlink escapes allowed root" ;;
    esac
    COMPOSE_FILE="${compose_resolved}"
  fi
}

validate_inputs() {
  [[ -n "${SERVICE_NAME}" ]] || die "service is required"
  [[ -n "${IMAGE_REPO}" ]] || die "image is required"
  [[ -n "${IMAGE_TAG}" ]] || die "tag is required"
  [[ -n "${COMPOSE_REL}" ]] || die "compose-dir is required"
  [[ -n "${CONTAINER_NAME}" ]] || die "container is required"

  is_safe_token "${SERVICE_NAME}" || die "Invalid service name"
  is_safe_token "${CONTAINER_NAME}" || die "Invalid container name"
  is_safe_image_repo "${IMAGE_REPO}" || die "Invalid image repository"
  is_safe_tag "${IMAGE_TAG}" || die "Invalid image tag"

  case "${HEALTH_MODE}" in
    docker | http | exec | running) ;;
    *) die "Invalid health-mode: ${HEALTH_MODE}" ;;
  esac

  if [[ "${HEALTH_MODE}" == "http" ]]; then
    [[ -n "${HEALTH_URL}" ]] || die "health-url required for http mode"
    case "${HEALTH_URL}" in
      http://* | https://*) ;;
      *) die "Invalid health-url scheme" ;;
    esac
    [[ "${HEALTH_URL}" != *[[:space:]]* ]] || die "Invalid health-url spaces"
    [[ "${HEALTH_URL}" != *\`* && "${HEALTH_URL}" != *\$* && "${HEALTH_URL}" != *\;* ]] ||
      die "Invalid health-url metacharacters"
  fi
  if [[ "${HEALTH_MODE}" == "exec" ]]; then
    [[ -n "${HEALTH_COMMAND}" ]] || die "health-command required for exec mode"
    [[ "${HEALTH_COMMAND}" != *[\`\$\;\|\&\<\>\(\)]* ]] || die "health-command contains forbidden characters"
  fi

  [[ "${HEALTH_TIMEOUT}" =~ ^[1-9][0-9]{0,3}$ ]] || die "Invalid health-timeout"
  [[ "${HEALTH_RETRIES}" =~ ^[1-9][0-9]{0,2}$ ]] || die "Invalid health-retries"
  (( HEALTH_TIMEOUT <= 3600 )) || die "health-timeout too large"
  (( HEALTH_RETRIES <= 120 )) || die "health-retries too large"

  if [[ -n "${GITHUB_SHA}" ]]; then
    [[ "${GITHUB_SHA}" =~ ^[0-9a-fA-F]{7,40}$ ]] || die "Invalid github-sha"
  fi
  if [[ -n "${GITHUB_RUN_URL}" ]]; then
    [[ "${GITHUB_RUN_URL}" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+$ ]] ||
      die "Invalid github-run-url"
  fi
  if [[ -n "${REPORT_FILE}" ]]; then
    [[ "${REPORT_FILE}" =~ ^/tmp/[a-zA-Z0-9._/-]+$ ]] || die "report-file must be under /tmp"
    [[ "${REPORT_FILE}" != *..* ]] || die "report-file must not contain .."
  fi

  resolve_compose_path
  NEW_IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"
  STATE_DIR="${DEPLOY_STATE_ROOT}/${SERVICE_NAME}"
  SERVICE_LOCK_FILE="${LOCK_DIR}/compose-${SERVICE_NAME}.lock"
}

acquire_locks() {
  require_command flock
  mkdir -p "${LOCK_DIR}"
  chmod 755 "${LOCK_DIR}" 2>/dev/null || true

  # Global git lock + per-service compose lock (held for whole deploy).
  exec {GIT_LOCK_FD}>"${GIT_LOCK_FILE}"
  flock -w 600 "${GIT_LOCK_FD}" || die "Could not acquire git lock"
  exec {SERVICE_LOCK_FD}>"${SERVICE_LOCK_FILE}"
  flock -w 600 "${SERVICE_LOCK_FD}" || die "Could not acquire service lock for ${SERVICE_NAME}"
  ok "Acquired git and service locks"
}

release_locks() {
  # Invoked from EXIT trap; ShellCheck may mark body unreachable.
  # shellcheck disable=SC2317
  if [[ -n "${SERVICE_LOCK_FD}" ]]; then
    flock -u "${SERVICE_LOCK_FD}" 2>/dev/null || true
  fi
  # shellcheck disable=SC2317
  if [[ -n "${GIT_LOCK_FD}" ]]; then
    flock -u "${GIT_LOCK_FD}" 2>/dev/null || true
  fi
}

ensure_clean_repo() {
  local dirty
  dirty="$(git -C "${INFRA_ROOT}" status --porcelain)"
  if [[ -n "${dirty}" ]]; then
    fail "Repository working tree is not clean under ${INFRA_ROOT}"
    printf '%s\n' "${dirty}" >&2
    die "Refuse to deploy with a dirty working tree"
  fi
  ok "Repository working tree is clean"
}

git_pull_ff_only() {
  if [[ "${SKIP_GIT_PULL}" -eq 1 ]]; then
    info "Skipping git pull (--skip-git-pull)"
    return 0
  fi
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would run git pull --ff-only"
    return 0
  fi
  info "git pull --ff-only"
  git -C "${INFRA_ROOT}" pull --ff-only
  ok "Repository updated"
}

current_container_image() {
  local name="$1"
  if container_exists "${name}"; then
    docker inspect -f '{{.Config.Image}}' "${name}" 2>/dev/null || true
  fi
}

read_previous_from_state() {
  local current_env="${STATE_DIR}/current.env"
  if [[ -f "${current_env}" ]]; then
    # shellcheck disable=SC1090
    # Only IMAGE= line is trusted; re-validate after source-like parse.
    local line image_line=""
    while IFS= read -r line || [[ -n "${line}" ]]; do
      case "${line}" in
        IMAGE=*) image_line="${line#IMAGE=}" ;;
      esac
    done <"${current_env}"
    if [[ -n "${image_line}" ]] && [[ "${image_line}" == *:* ]]; then
      printf '%s\n' "${image_line}"
      return 0
    fi
  fi
  return 1
}

ensure_state_dir() {
  mkdir -p "${STATE_DIR}"
  chmod 700 "${STATE_DIR}"
}

write_state() {
  local result="$1"
  local tmp_current tmp_previous tmp_json

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would persist deploy state under ${STATE_DIR}"
    return 0
  fi

  ensure_state_dir
  umask 077

  tmp_previous="$(mktemp "${STATE_DIR}/previous.env.XXXXXX")"
  tmp_current="$(mktemp "${STATE_DIR}/current.env.XXXXXX")"
  tmp_json="$(mktemp "${STATE_DIR}/last-deploy.json.XXXXXX")"

  if [[ -f "${STATE_DIR}/current.env" ]]; then
    cp -f "${STATE_DIR}/current.env" "${tmp_previous}"
  else
    printf 'IMAGE=%s\n' "${PREVIOUS_IMAGE:-}" >"${tmp_previous}"
  fi

  cat >"${tmp_current}" <<EOF
IMAGE=${NEW_IMAGE}
SERVICE=${SERVICE_NAME}
CONTAINER=${CONTAINER_NAME}
COMMIT=${GITHUB_SHA:-}
UPDATED_AT=${FINISHED_AT:-${STARTED_AT}}
EOF

  cat >"${tmp_json}" <<EOF
{
  "service": "${SERVICE_NAME}",
  "container": "${CONTAINER_NAME}",
  "previous_image": "${PREVIOUS_IMAGE:-}",
  "current_image": "${NEW_IMAGE}",
  "commit": "${GITHUB_SHA:-}",
  "github_run_url": "${GITHUB_RUN_URL:-}",
  "started_at": "${STARTED_AT}",
  "finished_at": "${FINISHED_AT:-}",
  "result": "${result}",
  "rollback": ${ROLLBACK_PERFORMED},
  "health_mode": "${HEALTH_MODE}",
  "dry_run": false
}
EOF

  chmod 600 "${tmp_previous}" "${tmp_current}" "${tmp_json}"
  mv -f "${tmp_previous}" "${STATE_DIR}/previous.env"
  mv -f "${tmp_current}" "${STATE_DIR}/current.env"
  mv -f "${tmp_json}" "${STATE_DIR}/last-deploy.json"
  ok "Persisted deploy state in ${STATE_DIR}"
}

validate_compose_only() {
  local image_ref="$1"
  (
    cd "${COMPOSE_DIR}"
    SERVICE_IMAGE="${image_ref}" SERVICE_NAME="${CONTAINER_NAME}" \
      docker compose -f "${COMPOSE_FILE}" config --quiet
  )
}

apply_compose() {
  local image_ref="$1"

  info "Validating compose: ${COMPOSE_FILE}"
  validate_compose_only "${image_ref}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would pull and up -d ${image_ref}"
    return 0
  fi

  info "Pulling image: ${image_ref}"
  docker pull "${image_ref}"

  info "Applying compose up -d"
  (
    cd "${COMPOSE_DIR}"
    SERVICE_IMAGE="${image_ref}" SERVICE_NAME="${CONTAINER_NAME}" \
      docker compose -f "${COMPOSE_FILE}" up -d --pull never
  )
}

check_health_once() {
  case "${HEALTH_MODE}" in
    running)
      container_running "${CONTAINER_NAME}"
      ;;
    docker)
      local status
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
      [[ "${status}" == "healthy" || "${status}" == "running" ]]
      ;;
    http)
      require_command curl
      local code
      code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 "${HEALTH_URL}" || true)"
      [[ "${code}" =~ ^2[0-9][0-9]$ ]]
      ;;
    exec)
      # Intentionally non-shell argv: single command string already char-validated.
      docker exec "${CONTAINER_NAME}" /bin/sh -c "${HEALTH_COMMAND}" >/dev/null 2>&1
      ;;
  esac
}

wait_for_health() {
  local attempt
  local sleep_seconds

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    info "Dry-run: would wait for health (mode=${HEALTH_MODE})"
    return 0
  fi

  sleep_seconds=$((HEALTH_TIMEOUT / HEALTH_RETRIES))
  if [[ "${sleep_seconds}" -lt 1 ]]; then
    sleep_seconds=1
  fi

  info "Waiting for health (mode=${HEALTH_MODE}, retries=${HEALTH_RETRIES}, timeout=${HEALTH_TIMEOUT}s)"
  for attempt in $(seq 1 "${HEALTH_RETRIES}"); do
    if check_health_once; then
      ok "Healthcheck passed (attempt ${attempt}/${HEALTH_RETRIES})"
      return 0
    fi
    warn "Healthcheck not ready (attempt ${attempt}/${HEALTH_RETRIES})"
    if [[ "${attempt}" -lt "${HEALTH_RETRIES}" ]]; then
      sleep "${sleep_seconds}"
    fi
  done

  fail "Healthcheck failed after ${HEALTH_RETRIES} attempts"
  return 1
}

write_report() {
  local commit
  local target="${REPORT_FILE:-}"

  commit="$(git -C "${INFRA_ROOT}" rev-parse --short HEAD 2>/dev/null || echo n/a)"

  local report
  report="$(
    cat <<EOF
DEPLOY REPORT
=============
service:           ${SERVICE_NAME}
container:         ${CONTAINER_NAME}
compose_file:      ${COMPOSE_FILE}
previous_image:    ${PREVIOUS_IMAGE:-n/a}
new_image:         ${NEW_IMAGE}
result:            ${DEPLOY_RESULT}
rollback_performed:${ROLLBACK_PERFORMED}
health_mode:       ${HEALTH_MODE}
started_at:        ${STARTED_AT}
finished_at:       ${FINISHED_AT}
github_sha:        ${GITHUB_SHA:-n/a}
github_run_url:    ${GITHUB_RUN_URL:-n/a}
infra_commit:      ${commit}
dry_run:           ${DRY_RUN}
state_dir:         ${STATE_DIR}
EOF
  )"

  printf '%s\n' "${report}"
  if [[ -n "${target}" ]]; then
    umask 077
    printf '%s\n' "${report}" >"${target}"
    chmod 600 "${target}"
    ok "Wrote deploy report: ${target}"
  fi
}

perform_rollback() {
  if [[ "${ENABLE_ROLLBACK}" -ne 1 ]]; then
    warn "Rollback disabled; leaving failed deployment as-is"
    return 1
  fi

  if [[ -z "${PREVIOUS_IMAGE}" ]]; then
    warn "No previous image recorded; cannot rollback"
    return 1
  fi

  if [[ "${PREVIOUS_IMAGE}" == "${NEW_IMAGE}" ]]; then
    warn "Previous image equals new image; rollback would be a no-op"
    return 1
  fi

  section "Rollback"
  info "Restoring previous image: ${PREVIOUS_IMAGE}"
  ROLLBACK_PERFORMED=1

  if ! apply_compose "${PREVIOUS_IMAGE}"; then
    fail "Rollback apply failed"
    return 1
  fi

  if ! wait_for_health; then
    fail "Rollback healthcheck failed"
    return 1
  fi

  ok "Rollback completed"
  return 0
}

dry_run_checks() {
  section "Dry-run validation"
  kv "service" "${SERVICE_NAME}"
  kv "image" "${NEW_IMAGE}"
  kv "compose" "${COMPOSE_FILE}"
  kv "container" "${CONTAINER_NAME}"
  kv "health_mode" "${HEALTH_MODE}"
  kv "state_dir" "${STATE_DIR}"
  kv "rollback_possible" "$([[ -n "${PREVIOUS_IMAGE}" && "${PREVIOUS_IMAGE}" != "${NEW_IMAGE}" && "${ENABLE_ROLLBACK}" -eq 1 ]] && echo yes || echo no)"

  ensure_clean_repo
  validate_compose_only "${NEW_IMAGE}"

  if [[ -d "${DEPLOY_STATE_ROOT}" ]]; then
    ok "Deploy state root exists: ${DEPLOY_STATE_ROOT}"
  else
    warn "Deploy state root missing (will be created on real deploy): ${DEPLOY_STATE_ROOT}"
  fi

  if [[ -w "${DATA_ROOT}" ]] || [[ -w "$(dirname "${DEPLOY_STATE_ROOT}")" ]]; then
    ok "Data root appears writable for state persistence"
  else
    warn "Cannot verify write access to ${DATA_ROOT} (may need deploy user perms)"
  fi

  DEPLOY_RESULT="dry_run_ok"
  FINISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_report
  ok "Dry-run completed (no pull, no git mutation, no container change, no state write, no webhook)"
}

main() {
  local health_rc
  local rollback_rc
  local from_state=""

  parse_args "$@"
  validate_inputs

  require_command docker
  require_command git

  STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  trap 'release_locks' EXIT
  acquire_locks

  section "CI deploy: ${SERVICE_NAME}"
  kv "image" "${NEW_IMAGE}"
  kv "compose" "${COMPOSE_FILE}"
  kv "dry_run" "${DRY_RUN}"

  PREVIOUS_IMAGE="$(current_container_image "${CONTAINER_NAME}")"
  if [[ -z "${PREVIOUS_IMAGE}" ]]; then
    from_state="$(read_previous_from_state || true)"
    PREVIOUS_IMAGE="${from_state}"
  fi
  kv "previous_image" "${PREVIOUS_IMAGE:-none}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    dry_run_checks
    exit 0
  fi

  ensure_clean_repo
  git_pull_ff_only

  # Re-resolve after pull in case compose changed
  resolve_compose_path

  section "Apply new image"
  if ! apply_compose "${NEW_IMAGE}"; then
    DEPLOY_RESULT="failure"
    FINISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    write_state "${DEPLOY_RESULT}"
    write_report
    die "Failed to apply new compose image"
  fi

  health_rc=0
  wait_for_health || health_rc=$?

  if [[ "${health_rc}" -eq 0 ]]; then
    DEPLOY_RESULT="success"
    STATE_IMAGE="${NEW_IMAGE}"
    FINISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    write_state "${DEPLOY_RESULT}"
    write_report
    ok "Deploy succeeded"
    exit 0
  fi

  DEPLOY_RESULT="failure"
  rollback_rc=0
  STATE_IMAGE="${NEW_IMAGE}"
  if perform_rollback; then
    DEPLOY_RESULT="rolled_back"
    STATE_IMAGE="${PREVIOUS_IMAGE}"
  else
    rollback_rc=1
    DEPLOY_RESULT="failure_rollback_failed"
  fi

  FINISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  NEW_IMAGE="${STATE_IMAGE}"
  write_state "${DEPLOY_RESULT}"
  write_report

  if [[ "${rollback_rc}" -eq 0 && "${ROLLBACK_PERFORMED}" -eq 1 ]]; then
    die "Deploy healthcheck failed; rollback restored previous image"
  fi

  die "Deploy failed"
}

main "$@"
