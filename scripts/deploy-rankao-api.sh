#!/usr/bin/env bash
set -Eeuo pipefail
export GIT_SSH_COMMAND='ssh -i /home/ubuntu/.ssh/github_oracle -o IdentitiesOnly=yes'

REPO_DIR=/opt/apps/rankao-api
COMPOSE_DIR=/opt/infra/compose/rankao-api

cd "$REPO_DIR"
git fetch origin
git reset --hard origin/main

docker build -t rankao-api:local .

cd "$COMPOSE_DIR"
export SERVICE_IMAGE=rankao-api:local
docker compose up -d --force-recreate

for i in $(seq 1 60); do
  if docker exec rankao-api node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" 2>/dev/null; then
    echo "rankao-api healthy"
    exit 0
  fi
  sleep 3
done

echo "rankao-api healthcheck timed out" >&2
docker logs rankao-api --tail 80 >&2 || true
exit 1
