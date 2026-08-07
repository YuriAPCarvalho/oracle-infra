#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/prometheus/compose.yml"
DATA_DIR="/opt/docker/monitoring/prometheus/data"

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

log "Criando diretório persistente Prometheus (UID 65534)"
sudo install -d -m 0750 -o 65534 -g 65534 "${DATA_DIR}"

log "Verificando a rede monitoring"
if ! docker network inspect monitoring >/dev/null 2>&1; then
  docker network create monitoring
fi

log "Validando Docker Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo Prometheus"
docker compose -f "${COMPOSE_FILE}" up -d

log "Aguardando ready"
for attempt in {1..40}; do
  if docker run --rm --network monitoring curlimages/curl:8.12.1 \
    --silent --fail --max-time 5 \
    http://prometheus:9090/-/ready >/dev/null; then
    echo "Prometheus está ready."
    break
  fi

  if [[ "${attempt}" -eq 40 ]]; then
    docker logs prometheus --tail 100
    fail "Prometheus não ficou ready no prazo esperado."
  fi

  sleep 2
done

log "Status"
docker compose -f "${COMPOSE_FILE}" ps

echo
echo "Prometheus instalado."
echo "Acesso apenas na rede monitoring (sem porta no host)."
echo "Retenção: 15d / 5GB."
