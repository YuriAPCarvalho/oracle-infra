#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
  printf '\n============================================================\n'
  printf '%s\n' "$1"
  printf '============================================================\n'
}

log "03/12 - Traefik"
"${SCRIPT_DIR}/03-traefik.sh"

log "04/12 - Portainer"
"${SCRIPT_DIR}/04-portainer.sh"

log "05/12 - Dozzle"
"${SCRIPT_DIR}/05-dozzle.sh"

log "06/12 - Uptime Kuma"
"${SCRIPT_DIR}/06-uptime-kuma.sh"

log "07/12 - Node Exporter"
"${SCRIPT_DIR}/07-node-exporter.sh"

log "08/12 - cAdvisor"
"${SCRIPT_DIR}/08-cadvisor.sh"

log "09/12 - Prometheus"
"${SCRIPT_DIR}/09-prometheus.sh"

log "10/12 - Grafana"
"${SCRIPT_DIR}/10-grafana.sh"

log "11/12 - Postgres exporter"
"${SCRIPT_DIR}/11-postgres-exporter.sh"

log "12/12 - Redis exporter"
"${SCRIPT_DIR}/12-redis-exporter.sh"

log "Infraestrutura iniciada com sucesso"

docker ps --format \
  'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
