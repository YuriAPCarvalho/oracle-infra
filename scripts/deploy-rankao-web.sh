#!/usr/bin/env bash
set -Eeuo pipefail
export GIT_SSH_COMMAND='ssh -i /home/ubuntu/.ssh/github_oracle -o IdentitiesOnly=yes'

REPO_DIR=/opt/apps/rankao-app
COMPOSE_DIR=/opt/infra/compose/rankao-web

cd "$REPO_DIR"
git fetch origin
git reset --hard origin/main

docker build -t rankao-web:local --build-arg NEXT_PUBLIC_WEBAPI_URL=https://api.chamaeu.app .

cd "$COMPOSE_DIR"
export SERVICE_IMAGE=rankao-web:local
docker compose up -d --force-recreate

for i in $(seq 1 40); do
  if docker exec rankao-web node -e "fetch('http://127.0.0.1:3000').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
    echo "rankao-web healthy"
    exit 0
  fi
  sleep 3
done
exit 1
