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

### A) OCI Object Storage (Always Free) — **recomendado**

- ~20 GiB gratuitos na home region.
- Dados fora da VPS (sobrevive à perda do VM).
- API S3-compatible: Customer Secret Keys + namespace + regional endpoint.
- Variáveis na `rankao-api`:
  - `AWS_ENDPOINT_URL=https://<namespace>.compat.objectstorage.<region>.oraclecloud.com`
  - `AWS_DEFAULT_REGION=<region>` (ex.: `sa-saopaulo-1`)
  - Bucket + keys OCI.

Guia: [OCI Object Storage S3 Compatibility](https://docs.oracle.com/en-us/iaas/Content/Object/Tasks/s3compatibleapi.htm).

### B) MinIO na VPS (fallback)

- Usa disco local (`/opt/docker/minio/data`).
- Já existe compose em [`compose/minio/`](../../compose/minio/compose.yml) (padrão Marca7).
- Para ChamaEu: bucket dedicado `chamaeu`, subdomínios `s3.chamaeu.app` / console (ajustar `SERVICE_HOST` no `.env`).
- Escolher se uso > ~20 GiB ou preferir evitar console OCI.

## Decisão registrada

| Opção escolhida | Data | Responsável |
|-----------------|------|-------------|
| **B — MinIO na VPS** (ativo em `s3.chamaeu.app` / `minio.chamaeu.app`) | 2026-08-07 | ops ChamaEu |

Console: Cloudflare Access. S3 API: sem Access (credenciais MinIO). Bucket default: `chamaeu`.

> OCI Object Storage (opção A) permanece alternativa se o volume local ficar apertado.

## Sync pós-decisão

Ver [`rankao-api/docs/oracle-migration/scripts/sync-object-storage.sh`](../../../rankao-api/docs/oracle-migration/scripts/sync-object-storage.sh).
