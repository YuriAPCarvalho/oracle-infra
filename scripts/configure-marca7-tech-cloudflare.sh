#!/usr/bin/env bash
# Configure marca7.tech DNS + Cloudflare Access via API.
# Requires: CLOUDFLARE_API_TOKEN with Zone.DNS Edit, Account.Access apps write, SSL settings.
set -euo pipefail

ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-20f799331aa75509ff16ec3b68aa2064}"
ZONE_NAME="${CLOUDFLARE_ZONE_NAME:-marca7.tech}"
ORIGIN_IP="${ORIGIN_IP:-179.197.238.11}"
TOKEN="${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"

api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -X "$method" "https://api.cloudflare.com/client/v4${path}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

echo "== zone id =="
ZONE_ID=$(api GET "/zones?name=${ZONE_NAME}" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["result"][0]["id"] if d.get("success") and d["result"] else "")')
if [[ -z "$ZONE_ID" ]]; then
  echo "Zone ${ZONE_NAME} not found" >&2
  exit 1
fi
echo "ZONE_ID=$ZONE_ID"

echo "== SSL Full (strict) =="
api PATCH "/zones/${ZONE_ID}/settings/ssl" --data '{"value":"strict"}' | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("success"), d.get("result",{}).get("value"), d.get("errors"))'

HOSTS=(
  s3
  minio
  uptimekuma
  dozzle
  portainer
  traefik
)

echo "== DNS A records (proxied) =="
EXISTING=$(api GET "/zones/${ZONE_ID}/dns_records?per_page=100")
for name in "${HOSTS[@]}"; do
  fqdn="${name}.${ZONE_NAME}"
  rec_id=$(echo "$EXISTING" | python3 -c "
import json,sys
name=sys.argv[1]
d=json.load(sys.stdin)
for r in d.get('result',[]):
  if r.get('type')=='A' and r.get('name')==name:
    print(r['id']); break
" "$fqdn")
  body=$(python3 -c "import json; print(json.dumps({'type':'A','name':'''$name''','content':'''$ORIGIN_IP''','ttl':1,'proxied':True}))")
  if [[ -n "$rec_id" ]]; then
    echo "update $fqdn ($rec_id)"
    api PUT "/zones/${ZONE_ID}/dns_records/${rec_id}" --data "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("success"), d.get("errors"))'
  else
    echo "create $fqdn"
    api POST "/zones/${ZONE_ID}/dns_records" --data "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("success"), d.get("errors"))'
  fi
done

echo "== Access IdP Cloudflare (ensure) =="
IDPS=$(api GET "/accounts/${ACCOUNT_ID}/access/identity_providers")
CF_IDP=$(echo "$IDPS" | python3 -c '
import json,sys
d=json.load(sys.stdin)
for p in d.get("result",[]):
  if p.get("type") in ("cloudflare","github") or "cloudflare" in (p.get("name") or "").lower():
    if p.get("type")=="cloudflare":
      print(p["id"]); break
else:
  # also accept type onetimepin only if cloudflare missing — create cloudflare below
  pass
')

if [[ -z "$CF_IDP" ]]; then
  # create Cloudflare IdP if missing
  CF_IDP=$(api POST "/accounts/${ACCOUNT_ID}/access/identity_providers" --data '{"name":"Cloudflare","type":"cloudflare","config":{}}' | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("result",{}).get("id",""))')
  echo "created IdP $CF_IDP"
else
  echo "IdP exists $CF_IDP"
fi

create_app() {
  local app_name="$1" domain="$2"
  local apps existing_id
  apps=$(api GET "/accounts/${ACCOUNT_ID}/access/apps")
  existing_id=$(echo "$apps" | python3 -c "
import json,sys
domain=sys.argv[1]
d=json.load(sys.stdin)
for a in d.get('result',[]):
  if a.get('domain')==domain or domain in (a.get('self_hosted_domains') or []):
    print(a['id']); break
" "$domain")

  local app_body
  app_body=$(python3 -c "import json; print(json.dumps({
    'name': '''$app_name''',
    'domain': '''$domain''',
    'type': 'self_hosted',
    'session_duration': '24h',
    'auto_redirect_to_identity': True,
  }))")

  local app_id
  if [[ -n "$existing_id" ]]; then
    echo "update app $domain ($existing_id)"
    app_id="$existing_id"
    api PUT "/accounts/${ACCOUNT_ID}/access/apps/${existing_id}" --data "$app_body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("success"), d.get("errors"))'
  else
    echo "create app $domain"
    app_id=$(api POST "/accounts/${ACCOUNT_ID}/access/apps" --data "$app_body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("result",{}).get("id","")); print(d.get("errors"), file=sys.stderr)')
  fi

  if [[ -z "$app_id" ]]; then
    echo "failed app $domain" >&2
    return 1
  fi

  # Policy: allow Cloudflare account members (selector) — fallback emails via include email_domain marca7.com.br + gmail if needed
  # Prefer login_method cloudflare + everyone in account via "everyone" is too open.
  # Use include: email ending with allowed list via group; simplest durable: include login_method + email for known admins.
  local pol_body
  pol_body=$(python3 -c "import json; print(json.dumps({
    'name': 'Allow Cloudflare account members',
    'decision': 'allow',
    'precedence': 1,
    'include': [{'login_method': ['''$CF_IDP''']}],
  }))")

  # Replace policies: list then create if empty
  local pols
  pols=$(api GET "/accounts/${ACCOUNT_ID}/access/apps/${app_id}/policies")
  local pol_count
  pol_count=$(echo "$pols" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d.get("result",[])))')
  if [[ "$pol_count" == "0" ]]; then
    echo "create policy for $domain"
    api POST "/accounts/${ACCOUNT_ID}/access/apps/${app_id}/policies" --data "$pol_body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("success"), d.get("errors"))'
  else
    echo "policies already exist for $domain ($pol_count)"
  fi
}

echo "== Access applications =="
create_app "MinIO Console" "minio.marca7.tech"
create_app "Uptime Kuma" "uptimekuma.marca7.tech"
create_app "Dozzle" "dozzle.marca7.tech"
create_app "Portainer" "portainer.marca7.tech"
create_app "Traefik" "traefik.marca7.tech"

echo "DONE"
