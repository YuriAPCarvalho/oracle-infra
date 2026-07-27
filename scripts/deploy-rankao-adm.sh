#!/usr/bin/env bash
set -Eeuo pipefail
export GIT_SSH_COMMAND='ssh -i /home/ubuntu/.ssh/github_oracle -o IdentitiesOnly=yes'

REPO_DIR=/opt/apps/rankao-adm
COMPOSE_DIR=/opt/infra/compose/rankao-adm

cd "$REPO_DIR"
git fetch origin
git reset --hard origin/main

docker build -t rankao-adm:local .

cd "$COMPOSE_DIR"
export SERVICE_IMAGE=rankao-adm:local
docker compose up -d --force-recreate

for i in $(seq 1 40); do
  if docker exec rankao-adm wget -qO- http://127.0.0.1:3000 >/dev/null 2>&1; then
    echo "rankao-adm healthy"
    exit 0
  fi
  sleep 3
done
exit 1
