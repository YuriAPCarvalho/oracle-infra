# ChamaEu — cutover DNS Cloudflare

Referência: [SCRIPTGOLD_DNS_CUTOVER.md](../SCRIPTGOLD_DNS_CUTOVER.md).

## Pré-requisitos

- Traefik emitiu certificados para `chamaeu.app`, `api.chamaeu.app`, `adm.chamaeu.app` (teste com `--resolve` ou hosts file).
- `/health` OK na VPS.
- TTL reduzido (300s) 24h antes.

## Registros alvo

| Tipo | Nome | Conteúdo | Proxied |
|------|------|----------|---------|
| A | `@` | `129.146.161.65` | sim |
| A | `api` | `129.146.161.65` | sim |
| A | `adm` | `129.146.161.65` | sim |

Remover: CNAMEs `*.up.railway.app`, TXT `_railway-verify*`.

Script automatizado: `rankao-api/scripts/setup-chamaeu-dns.ps1` (modo Oracle).

## Pós-cutover (48h)

- Uptime Kuma verde
- Mercado Pago webhook teste
- Login app + admin + WebAuthn smoke
