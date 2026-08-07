#!/usr/bin/env bash
# Canonical persistent storage layout under DATA_ROOT (/opt/docker).
# shellcheck shell=bash

DATA_ROOT="${DATA_ROOT:-/opt/docker}"

# Relative paths under DATA_ROOT that must exist for a healthy layout.
STORAGE_DIRS=(
  databases/postgres/data
  databases/redis/data
  object-storage/minio/data
  object-storage/minio/config
  object-storage/minio/certs
  monitoring/prometheus/data
  monitoring/grafana/data
  monitoring/node-exporter/textfile
  platform/traefik/letsencrypt
  platform/traefik/logs
  platform/portainer/data
  platform/uptime-kuma/data
  applications/gold-api/auth_info
  applications/waha/sessions
  applications/rankao
  backups/postgres
  backups/minio
  backups/redis
  backups/grafana
  backups/prometheus
  backups/applications
  backups/full
  logs
  screenshots
  uploads
  deploy-state
)

# Host paths checked by health / used by compose binds.
storage_path() {
  printf '%s/%s\n' "${DATA_ROOT}" "$1"
}

storage_health_paths() {
  storage_path platform/traefik/letsencrypt
  storage_path platform/traefik/logs
  storage_path platform/portainer/data
  storage_path platform/uptime-kuma/data
  storage_path databases/postgres/data
  storage_path databases/redis/data
  storage_path object-storage/minio/data
  storage_path applications/gold-api/auth_info
  storage_path applications/waha/sessions
  storage_path monitoring/prometheus/data
  storage_path monitoring/grafana/data
}

# Create dirs with default ubuntu ownership; special UIDs applied by caller.
ensure_storage_dirs() {
  local root="${1:-${DATA_ROOT}}"
  local rel
  local owner="${STORAGE_OWNER:-ubuntu}"
  local group="${STORAGE_GROUP:-ubuntu}"

  for rel in "${STORAGE_DIRS[@]}"; do
    if [[ "${EUID}" -eq 0 ]]; then
      install -d -m 0750 -o "${owner}" -g "${group}" "${root}/${rel}"
    else
      sudo install -d -m 0750 -o "${owner}" -g "${group}" "${root}/${rel}"
    fi
  done
}

apply_storage_special_ownership() {
  local root="${1:-${DATA_ROOT}}"

  if [[ "${EUID}" -eq 0 ]]; then
    chown -R 65534:65534 "${root}/monitoring/prometheus/data"
    chown -R 472:472 "${root}/monitoring/grafana/data"
    chmod 0750 "${root}/monitoring/prometheus/data" "${root}/monitoring/grafana/data"
  else
    sudo chown -R 65534:65534 "${root}/monitoring/prometheus/data"
    sudo chown -R 472:472 "${root}/monitoring/grafana/data"
    sudo chmod 0750 "${root}/monitoring/prometheus/data" "${root}/monitoring/grafana/data"
  fi
}
