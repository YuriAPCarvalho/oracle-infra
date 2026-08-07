# ChamaEu — decisão de object storage

## Medição Railway (obrigatório antes do sync)

```bash
aws s3 ls "s3://${AWS_S3_BUCKET_NAME}" --recursive --summarize \
  --endpoint-url "${AWS_ENDPOINT_URL}"
```

Registrar **Total Size** abaixo:

| Data | Total objetos | Tamanho |
|------|---------------|---------|
| _preencher_ | | |

## Opções

### A) OCI Object Storage (Always Free) — alternativa / Camada 3

- ~20 GiB gratuitos na home region.
- Dados fora da VPS (sobrevive à perda do VM).
- API S3-compatible: Customer Secret Keys + namespace + regional endpoint.
- **Nesta arquitetura:** uso preferencial como **backup offsite (Camada 3)**, não como primary dos buckets de app se o volume crescer além de 20 GiB.
- Guia: [OCI Object Storage S3 Compatibility](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/s3compatibleapi.htm) · [docs/OCI_STORAGE.md](../../docs/OCI_STORAGE.md).

### B) MinIO na VPS (primary ativo)

- Disco local: `/opt/docker/object-storage/minio/data` (nunca sob `databases/`).
- Compose: [`compose/minio/`](../../compose/minio/compose.yml).
- Bucket dedicado `chamaeu`, hosts `s3.chamaeu.app` / `minio.chamaeu.app`.

## Decisão registrada

| Opção escolhida | Data | Responsável |
|-----------------|------|-------------|
| **B — MinIO na VPS** (ativo em `s3.chamaeu.app` / `minio.chamaeu.app`) | 2026-08-07 | ops ChamaEu |

Console: Cloudflare Access. S3 API: sem Access (credenciais MinIO). Bucket default: `chamaeu`.

> OCI Object Storage (opção A) permanece Camada 3 de backup e fallback se o volume local ficar apertado.

Layout completo: [docs/STORAGE_ARCHITECTURE.md](../../docs/STORAGE_ARCHITECTURE.md).

## Sync pós-decisão

Ver [`rankao-api/docs/oracle-migration/scripts/sync-object-storage.sh`](../../../rankao-api/docs/oracle-migration/scripts/sync-object-storage.sh).
