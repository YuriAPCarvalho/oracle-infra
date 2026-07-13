#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '\n============================================================\n'
  printf '%s\n' "$1"
  printf '============================================================\n'
}

log "03/06 - Traefik"
"${SCRIPT_DIR}/03-traefik.sh"

log "04/06 - Portainer"
"${SCRIPT_DIR}/04-portainer.sh"

log "05/06 - Dozzle"
"${SCRIPT_DIR}/05-dozzle.sh"

log "06/06 - Uptime Kuma"
"${SCRIPT_DIR}/06-uptime-kuma.sh"

log "Infraestrutura iniciada com sucesso"

docker ps --format \
  'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
