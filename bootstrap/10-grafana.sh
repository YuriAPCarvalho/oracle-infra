#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/compose/grafana/compose.yml"
ENV_FILE="${PROJECT_ROOT}/compose/grafana/.env"
ENV_EXAMPLE="${PROJECT_ROOT}/compose/grafana/.env.example"
DATA_DIR="/opt/docker/monitoring/grafana/data"

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

if [[ ! -f "${ENV_FILE}" ]]; then
  [[ -f "${ENV_EXAMPLE}" ]] || fail "Falta ${ENV_EXAMPLE}"
  fail "Crie ${ENV_FILE} a partir do .env.example com GF_SECURITY_ADMIN_USER e GF_SECURITY_ADMIN_PASSWORD antes do bootstrap."
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"
[[ -n "${GF_SECURITY_ADMIN_USER:-}" ]] ||
  fail "GF_SECURITY_ADMIN_USER vazio em compose/grafana/.env"
[[ -n "${GF_SECURITY_ADMIN_PASSWORD:-}" ]] ||
  fail "GF_SECURITY_ADMIN_PASSWORD vazio em compose/grafana/.env"

log "Criando diretório persistente Grafana (UID 472)"
sudo install -d -m 0750 -o 472 -g 472 "${DATA_DIR}"

log "Verificando a rede monitoring"
if ! docker network inspect monitoring >/dev/null 2>&1; then
  docker network create monitoring
fi

log "Validando Docker Compose"
docker compose -f "${COMPOSE_FILE}" config --quiet

log "Baixando imagem"
docker compose -f "${COMPOSE_FILE}" pull

log "Subindo Grafana"
docker compose -f "${COMPOSE_FILE}" up -d

log "Aguardando health"
for attempt in {1..40}; do
  if curl --silent --fail --max-time 5 \
    http://127.0.0.1:3000/api/health >/dev/null; then
    echo "Grafana está respondendo em 127.0.0.1:3000."
    break
  fi

  if [[ "${attempt}" -eq 40 ]]; then
    docker logs grafana --tail 100
    fail "Grafana não respondeu dentro do prazo esperado."
  fi

  sleep 2
done

log "Status"
docker compose -f "${COMPOSE_FILE}" ps

echo
echo "Grafana instalado."
echo "URL pública (Cloudflare Access): https://grafana.chamaeu.app"
echo "Fallback local: http://127.0.0.1:3000 (túnel SSH)"
if [[ -z "${GRAFANA_DISCORD_WEBHOOK_URL:-}" ]]; then
  echo "AVISO: GRAFANA_DISCORD_WEBHOOK_URL não definido — configure antes de testar alertas Discord."
fi
