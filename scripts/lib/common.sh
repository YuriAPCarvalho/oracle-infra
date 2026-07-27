#!/usr/bin/env bash

set -Eeuo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${COMMON_DIR}/../.." && pwd)"
DATA_ROOT="${DATA_ROOT:-/opt/docker}"
export DATA_ROOT

SERVICES=(
  traefik
  portainer
  dozzle
  uptime-kuma
  postgres
  minio
  redis
  waha
  gold-api
  gold-admin
  rankao-api
  rankao-web
  rankao-adm
)

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_BOLD=$'\033[1m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_RED=""
  COLOR_GREEN=""
  COLOR_YELLOW=""
  COLOR_BLUE=""
  COLOR_BOLD=""
  COLOR_RESET=""
fi

on_error() {
  local exit_code="$1"
  local line="$2"
  printf '%sERROR%s command failed at line %s (exit %s)\n' \
    "${COLOR_RED}" "${COLOR_RESET}" "${line}" "${exit_code}" >&2
  exit "${exit_code}"
}

info() {
  printf '%s==>%s %s\n' "${COLOR_BLUE}" "${COLOR_RESET}" "$*"
}

ok() {
  printf '%sOK%s %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$*"
}

warn() {
  printf '%sWARN%s %s\n' "${COLOR_YELLOW}" "${COLOR_RESET}" "$*" >&2
}

fail() {
  printf '%sFAIL%s %s\n' "${COLOR_RED}" "${COLOR_RESET}" "$*" >&2
}

die() {
  fail "$*"
  exit 1
}

section() {
  printf '\n%s%s%s\n' "${COLOR_BOLD}" "$*" "${COLOR_RESET}"
  printf '%s\n' "------------------------------------------------------------"
}

kv() {
  printf '  %-22s %s\n' "$1:" "${2:-n/a}"
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 ||
    die "Required command not found: ${command_name}"
}

with_timeout() {
  local seconds="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}" "$@"
  else
    "$@"
  fi
}

persistent_data_root() {
  printf '%s\n' "${DATA_ROOT}"
}

service_compose_file() {
  case "${1:-}" in
    traefik) printf '%s\n' "${PROJECT_ROOT}/compose/traefik/compose.yml" ;;
    portainer) printf '%s\n' "${PROJECT_ROOT}/compose/portainer/compose.yml" ;;
    dozzle) printf '%s\n' "${PROJECT_ROOT}/compose/dozzle/compose.yml" ;;
    uptime-kuma) printf '%s\n' "${PROJECT_ROOT}/compose/uptime-kuma/compose.yml" ;;
    postgres) printf '%s\n' "${PROJECT_ROOT}/compose/postgres/compose.yml" ;;
    minio) printf '%s\n' "${PROJECT_ROOT}/compose/minio/compose.yml" ;;
    gold-api) printf '%s\n' "${PROJECT_ROOT}/compose/gold-api/compose.yml" ;;
    gold-admin) printf '%s\n' "${PROJECT_ROOT}/compose/gold-admin/compose.yml" ;;
    redis) printf '%s\n' "${PROJECT_ROOT}/compose/redis/compose.yml" ;;
    waha) printf '%s\n' "${PROJECT_ROOT}/compose/waha/compose.yml" ;;
    rankao-api) printf '%s\n' "${PROJECT_ROOT}/compose/rankao-api/compose.yml" ;;
    rankao-web) printf '%s\n' "${PROJECT_ROOT}/compose/rankao-web/compose.yml" ;;
    rankao-adm) printf '%s\n' "${PROJECT_ROOT}/compose/rankao-adm/compose.yml" ;;
    *) return 1 ;;
  esac
}

is_managed_service() {
  local service="$1"
  local item

  for item in "${SERVICES[@]}"; do
    [[ "${item}" == "${service}" ]] && return 0
  done

  return 1
}

list_services() {
  printf '%s\n' "${SERVICES[@]}"
}

container_exists() {
  with_timeout 8 docker container inspect "$1" >/dev/null 2>&1
}

container_running() {
  [[ "$(with_timeout 8 docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" == "true" ]]
}

resolve_container() {
  local target="$1"

  if is_managed_service "${target}"; then
    printf '%s\n' "${target}"
    return 0
  fi

  if container_exists "${target}"; then
    printf '%s\n' "${target}"
    return 0
  fi

  return 1
}

compose_files() {
  local service
  for service in "${SERVICES[@]}"; do
    service_compose_file "${service}"
  done
}

validate_compose_file() {
  local compose_file="$1"

  [[ -f "${compose_file}" ]] ||
    die "Compose file not found: ${compose_file}"

  docker compose -f "${compose_file}" config --quiet
}

bytes_to_human() {
  local path="$1"

  if command -v du >/dev/null 2>&1; then
    du -h "${path}" | awk '{print $1}'
  else
    printf 'n/a\n'
  fi
}
