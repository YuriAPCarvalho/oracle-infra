#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Execute com sudo: sudo ./bootstrap/02-docker.sh"
  exit 1
fi

echo "==> Removendo pacotes conflitantes, se existirem"

CONFLICTING_PACKAGES=(
  docker.io
  docker-compose
  docker-compose-v2
  docker-doc
  podman-docker
  containerd
  runc
)

for package in "${CONFLICTING_PACKAGES[@]}"; do
  apt-get remove -y "$package" 2>/dev/null || true
done

echo "==> Instalando dependências"

apt-get update
apt-get install -y ca-certificates curl

echo "==> Configurando repositório oficial do Docker"

install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod a+r /etc/apt/keyrings/docker.asc

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "==> Instalando Docker Engine e Compose Plugin"

apt-get update
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

echo "==> Configurando rotação de logs"

install -m 0755 -d /etc/docker

cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true
}
EOF

echo "==> Habilitando serviço"

systemctl enable docker
systemctl restart docker

echo "==> Adicionando usuário ubuntu ao grupo docker"

usermod -aG docker ubuntu

echo "==> Criando redes padrão"

docker network inspect proxy >/dev/null 2>&1 ||
  docker network create proxy

docker network inspect internal >/dev/null 2>&1 ||
  docker network create --internal internal

echo "==> Validando instalação"

docker version
docker compose version
docker info --format 'Arquitetura: {{.Architecture}}'
docker network ls

echo
echo "Docker instalado com sucesso."
echo "Saia da sessão SSH e conecte novamente para ativar o grupo docker."
