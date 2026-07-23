#!/usr/bin/env bash
set -euo pipefail
echo "=== local ==="
curl -sS -o /dev/null -w "api:%{http_code}\n" http://127.0.0.1:4000/health || true
curl -sS -o /dev/null -w "app:%{http_code}\n" http://127.0.0.1:3000/ || true
echo "=== routers minio ==="
curl -sS http://127.0.0.1:8080/api/http/routers | python3 -c 'import json,sys; d=json.load(sys.stdin); print([r["name"] for r in d if "minio" in r.get("name","")])'
echo "=== traefik recent ==="
docker logs traefik 2>&1 | tail -20
