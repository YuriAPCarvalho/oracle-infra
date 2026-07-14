# WhatsApp (Baileys) ops

Session path: `/opt/docker/gold-api/auth_info` → `/data/auth_info`

## Re-auth (QR)

1. Stop Railway `gold-whatsapp` / `gold-api` (avoid dual session) — whatsapp already scaled to 0.
2. Clear session if logged out: `rm -rf /opt/docker/gold-api/auth_info/*`
3. `docker restart gold-api`
4. Watch QR in Dozzle / `docker logs -f gold-api` (base64 in debug / warn).

Migration note: starting Oracle while Railway still held the session caused `DisconnectReason.loggedOut` (401). Fresh QR required after cutover.
