#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/postgres-exporter/compose.yml"
ENV_FILE="${PROJECT_ROOT}/compose/postgres-exporter/.env"

log() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf '\nERRO: %s\n' "$1" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 || fail "Docker não está instalado."
docker compose version >/dev/null 2>&1 || fail "Docker Compose Plugin não está disponível."
[[ -f "${COMPOSE_FILE}" ]] || fail "Arquivo não encontrado: ${COMPOSE_FILE}"

ARCH="$(uname -m)"
[[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]] ||
  fail "Arquitetura não suportada: ${ARCH}"

if [[ ! -f "${ENV_FILE}" ]] || ! grep -qE '^DATA_SOURCE_NAME=postgresql://.+' "${ENV_FILE}"; then
  log "Gerando .env do postgres-exporter"
  bash "${PROJECT_ROOT}/scripts/postgres-exporter-seed-env.sh"
fi

log "Verificando redes monitoring/internal"
docker network inspect monitoring >/dev/null 2>&1 || docker network create monitoring
docker network inspect internal >/dev/null 2>&1 || fail "Rede internal ausente (suba o Postgres antes)."

log "Validando Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo postgres-exporter"
docker compose -f "${COMPOSE_FILE}" up -d

log "Status"
docker compose -f "${COMPOSE_FILE}" ps
echo "postgres-exporter na rede monitoring (scrape :9187)."
