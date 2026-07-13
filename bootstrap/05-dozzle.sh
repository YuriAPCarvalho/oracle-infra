#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/dozzle/compose.yml"

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

log "Verificando a rede proxy"
if ! docker network inspect proxy >/dev/null 2>&1; then
  docker network create proxy
fi

log "Validando Docker Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo Dozzle"
docker compose -f "${COMPOSE_FILE}" up -d

log "Aguardando inicialização"
for attempt in {1..30}; do
  if curl --silent --fail --max-time 3 \
    http://127.0.0.1:8081 >/dev/null; then
    echo "Dozzle está respondendo."
    break
  fi

  if [[ "${attempt}" -eq 30 ]]; then
    docker logs dozzle --tail 100
    fail "Dozzle não respondeu dentro do prazo esperado."
  fi

  sleep 2
done

log "Validando porta"
sudo ss -lntp | grep ':8081' || true

log "Status"
docker compose -f "${COMPOSE_FILE}" ps

echo
echo "Dozzle instalado com sucesso."
echo "Acesso local: http://127.0.0.1:8081"
