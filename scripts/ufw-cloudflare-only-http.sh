#!/usr/bin/env bash
# Restrict UFW HTTP/HTTPS to Cloudflare edge IPs only.
# Keeps SSH (22/tcp LIMIT) unchanged.
#
# Usage (on VPS):
#   sudo bash scripts/ufw-cloudflare-only-http.sh
#
# Idempotent: refreshes CF CIDR allows and removes world-open 80/443.
set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute com sudo: sudo bash scripts/ufw-cloudflare-only-http.sh" >&2
  exit 1
fi

command -v ufw >/dev/null 2>&1 || {
  echo "ufw não instalado" >&2
  exit 1
}
command -v curl >/dev/null 2>&1 || {
  echo "curl não instalado" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "==> Baixando listas oficiais Cloudflare"
curl -fsS https://www.cloudflare.com/ips-v4 >"${TMP}/ips-v4"
curl -fsS https://www.cloudflare.com/ips-v6 >"${TMP}/ips-v6"

[[ -s "${TMP}/ips-v4" ]] || {
  echo "Falha ao baixar ips-v4" >&2
  exit 1
}
[[ -s "${TMP}/ips-v6" ]] || {
  echo "Falha ao baixar ips-v6" >&2
  exit 1
}

echo "==> Removendo allow world-open 80/443 (se existirem)"
# May appear twice (IPv4 + IPv6); delete until ufw says not found.
for _ in 1 2 3 4; do
  ufw delete allow 80/tcp >/dev/null 2>&1 || true
  ufw delete allow 443/tcp >/dev/null 2>&1 || true
done

echo "==> Removendo regras Cloudflare antigas (refresh de CIDRs)"
delete_commented_rules() {
  local needle="$1"
  local num
  while true; do
    num="$(
      ufw status numbered |
        grep -F "${needle}" |
        head -n 1 |
        sed -n 's/^\[\s*\([0-9][0-9]*\)\].*/\1/p'
    )"
    [[ -n "${num}" ]] || break
    yes | ufw delete "${num}" >/dev/null || break
  done
}
delete_commented_rules 'Cloudflare HTTP'
delete_commented_rules 'Cloudflare HTTPS'

echo "==> Permitindo 80/443 apenas de CIDRs Cloudflare (IPv4)"
while read -r cidr; do
  [[ -n "${cidr}" ]] || continue
  ufw allow from "${cidr}" to any port 80 proto tcp comment 'Cloudflare HTTP'
  ufw allow from "${cidr}" to any port 443 proto tcp comment 'Cloudflare HTTPS'
done <"${TMP}/ips-v4"

echo "==> Permitindo 80/443 apenas de CIDRs Cloudflare (IPv6)"
while read -r cidr; do
  [[ -n "${cidr}" ]] || continue
  ufw allow from "${cidr}" to any port 80 proto tcp comment 'Cloudflare HTTP'
  ufw allow from "${cidr}" to any port 443 proto tcp comment 'Cloudflare HTTPS'
done <"${TMP}/ips-v6"

echo "==> Garantindo SSH"
ufw status | grep -q '22/tcp' || ufw limit 22/tcp comment 'SSH'

ufw --force enable
echo
ufw status verbose | head -n 40
echo "..."
echo "Total regras Cloudflare HTTP:" "$(ufw status | grep -c 'Cloudflare HTTP' || true)"
echo "Total regras Cloudflare HTTPS:" "$(ufw status | grep -c 'Cloudflare HTTPS' || true)"
echo
echo "OK — 80/443 restritos aos IPs Cloudflare. SSH permanece LIMIT."
echo "Teste: https://grafana.chamaeu.app e https://api.chamaeu.app/health"
echo "Acesso direto por IP público na 80/443 deve falhar."
