#!/usr/bin/env bash
#
# status.sh
# Shows a friendly operational snapshot of the VPS, Docker runtime,
# managed services, networks, volumes, firewall, and Fail2Ban.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
trap 'on_error "$?" "$LINENO"' ERR

command_output() {
  local fallback="$1"
  shift
  "$@" 2>/dev/null || printf '%s\n' "${fallback}"
}

docker_value() {
  local fallback="$1"
  shift

  if command -v docker >/dev/null 2>&1; then
    with_timeout 8 "$@" 2>/dev/null || printf '%s\n' "${fallback}"
  else
    printf '%s\n' "${fallback}"
  fi
}

service_status() {
  local service="$1"
  local status

  status="$(docker_value "not found" docker inspect -f '{{.State.Status}}' "${service}")"
  printf '%s\n' "${status}"
}

ufw_status() {
  local status="n/a"

  if command -v ufw >/dev/null 2>&1; then
    if [[ "${EUID}" -eq 0 ]]; then
      status="$(ufw status 2>/dev/null | head -n 1 || true)"
    elif sudo -n true 2>/dev/null; then
      status="$(sudo -n ufw status 2>/dev/null | head -n 1 || true)"
    else
      status="requires sudo"
    fi
  else
    status="not installed"
  fi

  printf '%s\n' "${status:-n/a}"
}

fail2ban_status() {
  local status="n/a"

  if command -v fail2ban-client >/dev/null 2>&1; then
    if fail2ban-client ping >/dev/null 2>&1; then
      status="$(fail2ban-client ping 2>/dev/null || true)"
    elif [[ "${EUID}" -ne 0 ]] && sudo -n true 2>/dev/null && sudo -n fail2ban-client ping >/dev/null 2>&1; then
      status="$(sudo -n fail2ban-client ping 2>/dev/null || true)"
    elif systemctl is-active fail2ban >/dev/null 2>&1; then
      status="active"
    elif [[ "${EUID}" -ne 0 ]] && sudo -n true 2>/dev/null && sudo -n systemctl is-active fail2ban >/dev/null 2>&1; then
      status="active"
    else
      status="not running or requires sudo"
    fi
  else
    status="not installed"
  fi

  printf '%s\n' "${status:-n/a}"
}

main() {
  local os_name="n/a"
  local os_version="n/a"
  local docker_version="not installed"
  local compose_version="not installed"
  local docker_ready="false"
  local service

  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    os_name="${PRETTY_NAME:-${NAME:-n/a}}"
    os_version="${VERSION_ID:-n/a}"
  fi

  if command -v docker >/dev/null 2>&1; then
    if with_timeout 8 docker info >/dev/null 2>&1; then
      docker_ready="true"
      docker_version="$(with_timeout 8 docker version --format '{{.Server.Version}}' 2>/dev/null || docker --version)"
    else
      docker_version="$(docker --version 2>/dev/null || printf 'installed, daemon unavailable\n')"
      docker_version="${docker_version} (daemon unavailable)"
    fi
    compose_version="$(with_timeout 8 docker compose version --short 2>/dev/null || with_timeout 8 docker compose version 2>/dev/null || printf 'not available\n')"
  fi

  section "Host"
  kv "Hostname" "$(command_output n/a hostname -f)"
  kv "IP" "$(command_output n/a hostname -I | awk '{$1=$1; print}')"
  kv "Operating system" "${os_name}"
  kv "OS version" "${os_version}"
  kv "Kernel" "$(uname -r)"
  kv "Architecture" "$(uname -m)"

  section "Resources"
  kv "CPU" "$(command_output n/a sh -c "lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, \"\", \$2); print \$2; exit}'")"
  kv "CPU cores" "$(command_output n/a nproc)"
  kv "RAM" "$(command_output n/a sh -c "free -h | awk '/^Mem:/ {print \$3 \" used / \" \$2 \" total\"}'")"
  kv "Swap" "$(command_output n/a sh -c "free -h | awk '/^Swap:/ {print \$3 \" used / \" \$2 \" total\"}'")"
  kv "Disk /" "$(command_output n/a sh -c "df -h / | awk 'NR==2 {print \$3 \" used / \" \$2 \" total (\" \$5 \")\"}'")"
  kv "Load average" "$(command_output n/a sh -c "cut -d ' ' -f 1-3 /proc/loadavg")"

  section "Docker"
  kv "Docker version" "${docker_version}"
  kv "Compose version" "${compose_version}"
  if [[ "${docker_ready}" == "true" ]]; then
    kv "Active containers" "$(docker_value 0 sh -c "docker ps -q | wc -l | tr -d ' '")"
    kv "Images" "$(docker_value 0 sh -c "docker images -q | sort -u | wc -l | tr -d ' '")"
    kv "Volumes" "$(docker_value 0 sh -c "docker volume ls -q | wc -l | tr -d ' '")"
    kv "Networks" "$(docker_value 0 sh -c "docker network ls -q | wc -l | tr -d ' '")"
  else
    kv "Active containers" "daemon unavailable"
    kv "Images" "daemon unavailable"
    kv "Volumes" "daemon unavailable"
    kv "Networks" "daemon unavailable"
  fi

  section "Managed services"
  for service in "${SERVICES[@]}"; do
    if [[ "${docker_ready}" == "true" ]]; then
      kv "${service}" "$(service_status "${service}")"
    else
      kv "${service}" "daemon unavailable"
    fi
  done

  section "Security"
  kv "UFW" "$(ufw_status)"
  kv "Fail2Ban" "$(fail2ban_status)"
}

main "$@"
