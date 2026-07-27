#!/usr/bin/env bash
#
# health.sh
# Runs operational health checks for Docker, host resources, network,
# managed services, Docker networks, persistent data, and Docker socket.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

FAILURES=0
DOCKER_READY=false

record_ok() {
  printf '%sOK%s   %-18s %s\n' "${COLOR_GREEN}" "${COLOR_RESET}" "$1" "${2:-}"
}

record_fail() {
  printf '%sFAIL%s %-18s %s\n' "${COLOR_RED}" "${COLOR_RESET}" "$1" "$2"
  FAILURES=$((FAILURES + 1))
}

check() {
  local name="$1"
  local output
  shift

  if output="$("$@" 2>&1)"; then
    record_ok "${name}" "${output}"
    return 0
  else
    record_fail "${name}" "${output:-check failed}"
    return 1
  fi
}

run_check() {
  check "$@" || true
}

check_docker() {
  command -v docker >/dev/null 2>&1 || {
    printf 'docker command not found\n'
    return 1
  }
  with_timeout 8 docker info >/dev/null 2>&1 || {
    printf 'Docker daemon is not reachable\n'
    return 1
  }
  printf 'daemon reachable\n'
}

check_compose() {
  with_timeout 8 docker compose version >/dev/null 2>&1 || {
    printf 'Docker Compose Plugin is not available\n'
    return 1
  }
  with_timeout 8 docker compose version --short
}

check_disk() {
  local usage
  usage="$(df -P / | awk 'NR==2 {gsub("%", "", $5); print $5}')"
  [[ "${usage}" -lt 90 ]] || {
    printf 'root filesystem usage is %s%%\n' "${usage}"
    return 1
  }
  printf 'root filesystem usage is %s%%\n' "${usage}"
}

check_ram() {
  local available total percent
  read -r available total < <(free -m | awk '/^Mem:/ {print $7, $2}')
  percent="$(awk -v available="${available}" -v total="${total}" 'BEGIN {printf "%.0f", (available / total) * 100}')"
  [[ "${percent}" -ge 10 ]] || {
    printf 'available memory is %s%%\n' "${percent}"
    return 1
  }
  printf 'available memory is %s%%\n' "${percent}"
}

check_swap() {
  local total used
  read -r total used < <(free -m | awk '/^Swap:/ {print $2, $3}')
  [[ "${total}" -gt 0 ]] || {
    printf 'swap is not configured\n'
    return 1
  }
  printf '%s MB used / %s MB total\n' "${used}" "${total}"
}

check_cpu() {
  local cores
  cores="$(nproc)"
  [[ "${cores}" -gt 0 ]] || {
    printf 'no CPU cores detected\n'
    return 1
  }
  printf '%s cores detected\n' "${cores}"
}

check_load() {
  local load_value cores limit
  load_value="$(awk '{print $1}' /proc/loadavg)"
  cores="$(nproc)"
  limit=$((cores * 2))
  awk -v load_value="${load_value}" -v limit="${limit}" 'BEGIN {exit !(load_value <= limit)}' || {
    printf '1m load %s is above limit %s\n' "${load_value}" "${limit}"
    return 1
  }
  printf '1m load %s, limit %s\n' "${load_value}" "${limit}"
}

check_internet() {
  curl --silent --fail --max-time 5 https://1.1.1.1 >/dev/null || {
    printf 'cannot reach https://1.1.1.1\n'
    return 1
  }
  printf 'internet reachable\n'
}

check_dns() {
  getent hosts cloudflare.com >/dev/null || {
    printf 'DNS resolution failed for cloudflare.com\n'
    return 1
  }
  printf 'DNS resolution working\n'
}

check_service_container() {
  local service="$1"

  [[ "${DOCKER_READY}" == "true" ]] || {
    printf 'Docker daemon is not reachable\n'
    return 1
  }

  container_exists "${service}" || {
    printf 'container not found\n'
    return 1
  }

  container_running "${service}" || {
    printf 'container is not running\n'
    return 1
  }

  printf 'container running\n'
}

check_network() {
  local network="$1"

  [[ "${DOCKER_READY}" == "true" ]] || {
    printf 'Docker daemon is not reachable\n'
    return 1
  }

  with_timeout 8 docker network inspect "${network}" >/dev/null 2>&1 || {
    printf 'Docker network %s not found\n' "${network}"
    return 1
  }
  printf 'network exists\n'
}

check_persistent_dirs() {
  local missing=0
  local dir
  local dirs=(
    /opt/docker/traefik/letsencrypt
    /opt/docker/traefik/logs
    /opt/docker/portainer/data
    /opt/docker/uptime-kuma/data
    /opt/docker/postgres/data
    /opt/docker/minio/data
    /opt/docker/dailybot/storage
    /opt/docker/gold-api/auth_info
    /opt/docker/redis/data
    /opt/docker/waha/sessions
  )

  for dir in "${dirs[@]}"; do
    [[ -d "${dir}" ]] || {
      printf 'missing %s\n' "${dir}"
      missing=1
    }
  done

  [[ "${missing}" -eq 0 ]] || return 1
  printf 'persistent directories exist\n'
}

check_docker_socket() {
  [[ -S /var/run/docker.sock ]] || {
    printf '/var/run/docker.sock is not a socket\n'
    return 1
  }
  [[ -r /var/run/docker.sock ]] || {
    printf '/var/run/docker.sock is not readable by current user\n'
    return 1
  }
  printf 'socket exists and is readable\n'
}

check_volumes() {
  [[ "${DOCKER_READY}" == "true" ]] || {
    printf 'Docker daemon is not reachable\n'
    return 1
  }

  with_timeout 8 docker volume ls >/dev/null 2>&1 || {
    printf 'cannot list Docker volumes\n'
    return 1
  }
  printf 'Docker volume subsystem reachable\n'
}

main() {
  local service

  section "Health checks"
  if check "Docker" check_docker; then
    DOCKER_READY=true
  fi
  run_check "Compose" check_compose
  run_check "Disk" check_disk
  run_check "RAM" check_ram
  run_check "Swap" check_swap
  run_check "CPU" check_cpu
  run_check "Load average" check_load
  run_check "Internet" check_internet
  run_check "DNS" check_dns

  for service in "${SERVICES[@]}"; do
    run_check "${service}" check_service_container "${service}"
  done

  run_check "proxy network" check_network proxy
  run_check "internal network" check_network internal
  run_check "Volumes" check_volumes
  run_check "Persistent data" check_persistent_dirs
  run_check "Docker socket" check_docker_socket

  printf '\n'
  if [[ "${FAILURES}" -eq 0 ]]; then
    ok "All health checks passed."
    return 0
  fi

  fail "${FAILURES} health check(s) failed."
  return 1
}

if ! main "$@"; then
  exit 1
fi
