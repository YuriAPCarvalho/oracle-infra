#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/traefik/compose.yml"
CONFIG_FILE="${PROJECT_ROOT}/compose/traefik/traefik.yml"
DATA_ROOT="/opt/docker/platform/traefik"
LETSENCRYPT_DIR="${DATA_ROOT}/letsencrypt"
LOGS_DIR="${DATA_ROOT}/logs"

log() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf '\nERRO: %s\n' "$1" >&2
  exit 1
}

command -v docker >/dev/null 2>&1 ||
  fail "Docker não está instalado."

docker compose version >/dev/null 2>&1 ||
  fail "Docker Compose Plugin não está disponível."

[[ -f "${COMPOSE_FILE}" ]] ||
  fail "Arquivo não encontrado: ${COMPOSE_FILE}"

[[ -f "${CONFIG_FILE}" ]] ||
  fail "Arquivo não encontrado: ${CONFIG_FILE}"

log "Criando diretórios persistentes"
sudo install -d -m 0750 -o ubuntu -g ubuntu \
  "${DATA_ROOT}" \
  "${LETSENCRYPT_DIR}" \
  "${LOGS_DIR}"

log "Verificando a rede proxy"
if ! docker network inspect proxy >/dev/null 2>&1; then
  docker network create proxy
fi

log "Validando Docker Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo Traefik"
docker compose -f "${COMPOSE_FILE}" up -d

log "Aguardando inicialização"
for attempt in {1..30}; do
  if curl --silent --fail --max-time 3 \
    http://127.0.0.1:8080/api/overview >/dev/null; then
    echo "Traefik está respondendo."
    break
  fi

  if [[ "${attempt}" -eq 30 ]]; then
    docker logs traefik --tail 100
    fail "Traefik não respondeu dentro do prazo esperado."
  fi

  sleep 2
done

log "Validando portas"
sudo ss -lntp | grep -E ':80|:443|:8080' || true

log "Status"
docker compose -f "${COMPOSE_FILE}" ps

echo
echo "Traefik instalado com sucesso."
echo "Dashboard local: http://127.0.0.1:8080/dashboard/"
