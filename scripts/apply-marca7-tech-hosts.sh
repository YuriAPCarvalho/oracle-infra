#!/usr/bin/env bash
set -euo pipefail
cd /opt/infra

# Painéis e MinIO nesta VPS (Gestor Agro / marca7-app|api vivem em outra VPS).

sed -i 's|^SERVICE_HOST=.*|SERVICE_HOST=s3.marca7.tech|' compose/minio/.env
grep -q '^CONSOLE_HOST=' compose/minio/.env || echo 'CONSOLE_HOST=minio.marca7.tech' >> compose/minio/.env
sed -i 's|^CONSOLE_HOST=.*|CONSOLE_HOST=minio.marca7.tech|' compose/minio/.env
grep -q '^MINIO_SERVER_URL=' compose/minio/.env || echo 'MINIO_SERVER_URL=https://s3.marca7.tech' >> compose/minio/.env
sed -i 's|^MINIO_SERVER_URL=.*|MINIO_SERVER_URL=https://s3.marca7.tech|' compose/minio/.env
grep -q '^MINIO_BROWSER_REDIRECT_URL=' compose/minio/.env || echo 'MINIO_BROWSER_REDIRECT_URL=https://minio.marca7.tech' >> compose/minio/.env
sed -i 's|^MINIO_BROWSER_REDIRECT_URL=.*|MINIO_BROWSER_REDIRECT_URL=https://minio.marca7.tech|' compose/minio/.env

echo 'SERVICE_HOST=uptimekuma.marca7.tech' > compose/uptime-kuma/.env
echo 'SERVICE_HOST=dozzle.marca7.tech' > compose/dozzle/.env
echo 'SERVICE_HOST=portainer.marca7.tech' > compose/portainer/.env
echo 'SERVICE_HOST=traefik.marca7.tech' > compose/traefik/.env

echo "=== verify hosts ==="
grep -E 'SERVICE_HOST|CONSOLE_HOST|MINIO_SERVER_URL|MINIO_BROWSER_REDIRECT_URL' \
  compose/minio/.env \
  compose/uptime-kuma/.env compose/dozzle/.env compose/portainer/.env compose/traefik/.env

for s in traefik uptime-kuma dozzle portainer minio; do
  echo "=== up $s ==="
  docker compose -f "compose/$s/compose.yml" up -d --force-recreate
done

docker ps --format 'table {{.Names}}\t{{.Status}}'
