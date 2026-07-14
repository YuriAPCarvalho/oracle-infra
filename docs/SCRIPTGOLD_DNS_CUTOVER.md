# ScriptGold DNS cutover (Cloudflare)

## Domains (preserve names)

| Record | Type | Content | Proxy |
|--------|------|---------|-------|
| `scriptgold.com.br` | A | `129.146.161.65` | Proxied (orange) |
| `adm.scriptgold.com.br` | A | `129.146.161.65` | Proxied (orange) |
| `www` | CNAME / redirect | `scriptgold.com.br` | keep existing |

## SSL

Cloudflare SSL/TLS mode: **Full (strict)**

Traefik issues Let's Encrypt via HTTP-01 after DNS points to Oracle.

## After DNS

1. Smoke: `https://scriptgold.com.br/health`, `https://adm.scriptgold.com.br/health`, login admin
2. Re-auth WhatsApp (QR in Dozzle `gold-api` logs) — Railway session was invalidated
3. Scale Railway to 0: `gold-api`, `gold-admin` (whatsapp already 0)
4. Remove Railway custom domains after 48–72h

## Automation

With `CLOUDFLARE_API_TOKEN` (Zone:DNS:Edit):

```bash
bash .migration/cutover-dns.sh
```
