#!/usr/bin/env bash
# Restrict HTTP/HTTPS origin access to Cloudflare edge IPs.
#
# Important: Traefik publishes 80/443 via Docker. Docker iptables bypasses UFW
# for published ports, so this script also hardens the DOCKER-USER chain.
#
# Usage (on VPS):
#   sudo bash scripts/ufw-cloudflare-only-http.sh
#
# Idempotent. Keeps SSH (22/tcp LIMIT) unchanged.
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
command -v iptables >/dev/null 2>&1 || {
  echo "iptables não instalado" >&2
  exit 1
}

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "==> Baixando listas oficiais Cloudflare"
curl -fsS https://www.cloudflare.com/ips-v4 >"${TMP}/ips-v4"
curl -fsS https://www.cloudflare.com/ips-v6 >"${TMP}/ips-v6"
[[ -s "${TMP}/ips-v4" && -s "${TMP}/ips-v6" ]] || {
  echo "Falha ao baixar listas Cloudflare" >&2
  exit 1
}

echo "==> Removendo allow world-open 80/443 no UFW (se existirem)"
for _ in 1 2 3 4; do
  ufw delete allow 80/tcp >/dev/null 2>&1 || true
  ufw delete allow 443/tcp >/dev/null 2>&1 || true
done

echo "==> Removendo regras UFW Cloudflare antigas"
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

echo "==> UFW: allow 80/443 apenas de CIDRs Cloudflare"
while read -r cidr; do
  [[ -n "${cidr}" ]] || continue
  ufw allow from "${cidr}" to any port 80 proto tcp comment 'Cloudflare HTTP'
  ufw allow from "${cidr}" to any port 443 proto tcp comment 'Cloudflare HTTPS'
done <"${TMP}/ips-v4"
while read -r cidr; do
  [[ -n "${cidr}" ]] || continue
  ufw allow from "${cidr}" to any port 80 proto tcp comment 'Cloudflare HTTP'
  ufw allow from "${cidr}" to any port 443 proto tcp comment 'Cloudflare HTTPS'
done <"${TMP}/ips-v6"

ufw status | grep -q '22/tcp' || ufw limit 22/tcp comment 'SSH'
ufw --force enable >/dev/null

apply_docker_user_v4() {
  iptables -N DOCKER-USER 2>/dev/null || true
  iptables -F DOCKER-USER
  iptables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
  while read -r cidr; do
    [[ -n "${cidr}" ]] || continue
    iptables -A DOCKER-USER -p tcp -s "${cidr}" --dport 80 -j RETURN
    iptables -A DOCKER-USER -p tcp -s "${cidr}" --dport 443 -j RETURN
  done <"${TMP}/ips-v4"
  iptables -A DOCKER-USER -p tcp --dport 80 -j DROP
  iptables -A DOCKER-USER -p tcp --dport 443 -j DROP
  iptables -A DOCKER-USER -j RETURN
}

apply_docker_user_v6() {
  command -v ip6tables >/dev/null 2>&1 || return 0
  ip6tables -N DOCKER-USER 2>/dev/null || true
  ip6tables -F DOCKER-USER
  ip6tables -A DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
  while read -r cidr; do
    [[ -n "${cidr}" ]] || continue
    ip6tables -A DOCKER-USER -p tcp -s "${cidr}" --dport 80 -j RETURN
    ip6tables -A DOCKER-USER -p tcp -s "${cidr}" --dport 443 -j RETURN
  done <"${TMP}/ips-v6"
  ip6tables -A DOCKER-USER -p tcp --dport 80 -j DROP
  ip6tables -A DOCKER-USER -p tcp --dport 443 -j DROP
  ip6tables -A DOCKER-USER -j RETURN
}

echo "==> DOCKER-USER: bloquear 80/443 que não venham da Cloudflare"
apply_docker_user_v4
apply_docker_user_v6

echo "==> Instalando unit systemd para reaplicar após Docker/reboot"
UNIT=/etc/systemd/system/oracle-infra-cloudflare-docker-filter.service
cat >"${UNIT}" <<EOF
[Unit]
Description=Restrict Docker published 80/443 to Cloudflare IPs
After=docker.service ufw.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
# Avoid recursive full script on every boot calling itself through unit with heavy ufw churn:
# Prefer a dedicated ExecStart that only refreshes DOCKER-USER by re-running this script
# (idempotent). Enable unit.
systemctl daemon-reload
systemctl enable oracle-infra-cloudflare-docker-filter.service >/dev/null

echo
echo "UFW (amostra):"
ufw status | head -n 15
echo "..."
echo "DOCKER-USER (IPv4):"
iptables -L DOCKER-USER -n | head -n 20
echo
echo "OK — 80/443 origin restritos à Cloudflare (UFW + DOCKER-USER)."
echo "SSH permanece LIMIT. Teste via domínio Cloudflare;"
echo "acesso direto ao IP público:80/443 deve falhar."
