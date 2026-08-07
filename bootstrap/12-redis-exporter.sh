#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/redis-exporter/compose.yml"

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

log "Verificando redes monitoring/internal"
docker network inspect monitoring >/dev/null 2>&1 || docker network create monitoring
docker network inspect internal >/dev/null 2>&1 || fail "Rede internal ausente (suba o Redis antes)."

log "Validando Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo redis-exporter"
docker compose -f "${COMPOSE_FILE}" up -d

log "Status"
docker compose -f "${COMPOSE_FILE}" ps
echo "redis-exporter na rede monitoring (scrape :9121)."
