#!/usr/bin/env bash
set -euo pipefail
cd /opt/infra

# Restore MinIO console host
sed -i 's|^CONSOLE_HOST=.*|CONSOLE_HOST=minio.marca7.tech|' compose/minio/.env

# Reconnect ops panels to proxy
for c in portainer dozzle uptime-kuma; do
  docker network connect proxy "$c" 2>/dev/null || true
done

docker compose -f compose/minio/compose.yml up -d --force-recreate
docker compose -f compose/portainer/compose.yml up -d --force-recreate
docker compose -f compose/dozzle/compose.yml up -d --force-recreate
docker compose -f compose/uptime-kuma/compose.yml up -d --force-recreate
docker compose -f compose/traefik/compose.yml up -d --force-recreate

sleep 5
echo "=== routers ==="
curl -sS http://127.0.0.1:8080/api/http/routers | python3 - <<'PY'
import json,sys
d=json.load(sys.stdin)
for r in sorted(d, key=lambda x: x.get("name","")):
    n=r.get("name","")
    if any(x in n for x in ("portainer","dozzle","uptime","traefik@docker","minio")):
        print(n, r.get("rule"), r.get("status"))
PY
