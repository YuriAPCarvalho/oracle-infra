#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/node-exporter/compose.yml"

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

ARCH="$(uname -m)"
[[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]] ||
  fail "Arquitetura não suportada para esta stack: ${ARCH} (esperado aarch64/arm64)."

log "Criando diretório textfile (storage metrics)"
sudo install -d -m 0755 -o ubuntu -g ubuntu /opt/docker/monitoring/node-exporter/textfile

log "Verificando a rede monitoring"
if ! docker network inspect monitoring >/dev/null 2>&1; then
  docker network create monitoring
fi

log "Validando Docker Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo Node Exporter"
docker compose -f "${COMPOSE_FILE}" up -d

log "Aguardando métricas"
for attempt in {1..30}; do
  if docker run --rm --network monitoring curlimages/curl:8.12.1 \
    --silent --fail --max-time 5 \
    http://node-exporter:9100/metrics >/dev/null; then
    echo "Node Exporter está expondo /metrics."
    break
  fi

  if [[ "${attempt}" -eq 30 ]]; then
    docker logs node-exporter --tail 100
    fail "Node Exporter não respondeu dentro do prazo esperado."
  fi

  sleep 2
done

log "Status"
docker compose -f "${COMPOSE_FILE}" ps

echo
echo "Node Exporter instalado."
echo "Endpoint interno: http://node-exporter:9100/metrics (rede monitoring)."
