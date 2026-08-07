#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/uptime-kuma/compose.yml"
DATA_DIR="/opt/docker/platform/uptime-kuma/data"

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

log "Criando diretório persistente"
sudo install -d -m 0750 -o ubuntu -g ubuntu "${DATA_DIR}"

log "Verificando a rede proxy"
if ! docker network inspect proxy >/dev/null 2>&1; then
  docker network create proxy
fi

log "Validando Docker Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo Uptime Kuma"
docker compose -f "${COMPOSE_FILE}" up -d

log "Aguardando inicialização"
for attempt in {1..30}; do
  if curl --silent --fail --max-time 3 \
    http://127.0.0.1:8082 >/dev/null; then
    echo "Uptime Kuma está respondendo."
    break
  fi

  if [[ "${attempt}" -eq 30 ]]; then
    docker logs uptime-kuma --tail 100
    fail "Uptime Kuma não respondeu dentro do prazo esperado."
  fi

  sleep 2
done

log "Status"
docker compose -f "${COMPOSE_FILE}" ps

echo
echo "Instalação concluída."
echo "Acesso local da VPS: http://127.0.0.1:8082"
echo "Use túnel SSH para acessar pelo seu computador."
