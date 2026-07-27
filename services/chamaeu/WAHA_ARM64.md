## WAHA on ARM64 (Oracle Ampere)

GOWS **não usa Chromium** — imagem `devlikeapro/waha:gows` (amd64). Na Ampere ainda roda via QEMU:

```bash
docker run --privileged --rm tonistiigi/binfmt --install amd64
```

Compose: `platform: linux/amd64`, `WHATSAPP_DEFAULT_ENGINE=GOWS` (see `compose/waha/compose.yml`).

Trocar de WEBJS → GOWS exige **novo pareamento** (QR); dados de sessão WEBJS em `/opt/docker/waha/sessions` não são reutilizáveis.

Imagem nativa ARM sem browser: `devlikeapro/waha:noweb-arm` + `NOWEB` (alternativa futura se existir `gows-arm`).
