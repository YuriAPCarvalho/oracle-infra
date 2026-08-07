#!/usr/bin/env bash
set -euo pipefail
curl -sS http://127.0.0.1:8080/api/http/routers -o /tmp/routers.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/routers.json"))
for r in sorted(d, key=lambda x: x.get("name","")):
    print(f"{r.get('name')} | {r.get('rule')} | {r.get('status')}")
PY
echo "=== public smoke ==="
for u in \
  https://s3.marca7.tech/ \
  https://portainer.marca7.tech/ \
  https://minio.marca7.tech/ \
  https://dozzle.marca7.tech/ \
  https://uptimekuma.marca7.tech/ \
  https://traefik.marca7.tech/
do
  code=$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 15 -L --max-redirs 0 "$u" || echo ERR)
  loc=$(curl -sSI --connect-timeout 15 "$u" 2>/dev/null | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r' | head -1)
  echo "$code $u loc=$loc"
done
