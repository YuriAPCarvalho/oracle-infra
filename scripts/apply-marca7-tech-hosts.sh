#!/usr/bin/env bash
set -euo pipefail
cd /opt/infra

sed -i 's|^SERVICE_HOST=.*|SERVICE_HOST=api.gestoragro.marca7.tech|' compose/marca7-api/.env
sed -i 's|^FRONTEND_URL=.*|FRONTEND_URL=https://gestoragro.marca7.tech|' compose/marca7-api/.env
sed -i 's|^MINIO_PUBLIC_URL=.*|MINIO_PUBLIC_URL=https://s3.marca7.tech|' compose/marca7-api/.env

sed -i 's|^SERVICE_HOST=.*|SERVICE_HOST=gestoragro.marca7.tech|' compose/marca7-app/.env

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
grep -E 'SERVICE_HOST|FRONTEND_URL|MINIO_PUBLIC_URL|CONSOLE_HOST|MINIO_SERVER_URL|MINIO_BROWSER_REDIRECT_URL' \
  compose/marca7-api/.env compose/marca7-app/.env compose/minio/.env \
  compose/uptime-kuma/.env compose/dozzle/.env compose/portainer/.env compose/traefik/.env

for s in traefik uptime-kuma dozzle portainer minio marca7-api marca7-app; do
  echo "=== up $s ==="
  docker compose -f "compose/$s/compose.yml" up -d --force-recreate
done

docker ps --format 'table {{.Names}}\t{{.Status}}'
