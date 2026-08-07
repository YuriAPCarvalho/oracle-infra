#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/cadvisor/compose.yml"

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

[[ -S /run/containerd/containerd.sock ]] ||
  fail "Socket containerd ausente em /run/containerd/containerd.sock (necessário no Docker 29 + overlayfs)."

log "Verificando a rede monitoring"
if ! docker network inspect monitoring >/dev/null 2>&1; then
  docker network create monitoring
fi

log "Validando Docker Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo cAdvisor"
docker compose -f "${COMPOSE_FILE}" up -d

log "Aguardando métricas reais de containers"
for attempt in {1..45}; do
  metrics="$(
    docker run --rm --network monitoring curlimages/curl:8.12.1 \
      --silent --fail --max-time 8 \
      http://cadvisor:8080/metrics 2>/dev/null || true
  )"

  if printf '%s\n' "${metrics}" | grep -q 'container_memory_working_set_bytes' &&
    printf '%s\n' "${metrics}" | grep -E 'name="(traefik|portainer|dozzle|uptime-kuma)"' >/dev/null; then
    echo "cAdvisor está expondo métricas dos containers vizinhos."
    break
  fi

  if [[ "${attempt}" -eq 45 ]]; then
    docker logs cadvisor --tail 200
    fail "cAdvisor não expôs métricas reais dos containers (gate falhou)."
  fi

  sleep 2
done

log "Status"
docker compose -f "${COMPOSE_FILE}" ps

echo
echo "cAdvisor instalado."
echo "Endpoint interno: http://cadvisor:8080/metrics (rede monitoring)."
echo "privileged=true justificado para cgroup/overlayfs; sem portas no host."
