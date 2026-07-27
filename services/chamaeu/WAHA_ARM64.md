
## WAHA on ARM64 (Oracle Ampere)

The official `devlikeapro/waha` image is **amd64-only**. On this VPS, enable QEMU binfmt once:

```bash
docker run --privileged --rm tonistiigi/binfmt --install amd64
```

Compose uses `platform: linux/amd64` (see `compose/waha/compose.yml`).
