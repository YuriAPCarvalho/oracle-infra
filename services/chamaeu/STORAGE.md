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
| **A — OCI Object Storage** (default do plano até revisão) | 2026-03-27 | migração ChamaEu |

> Se o bucket Railway exceder ~20 GiB ou a sync OCI falhar, reavaliar **B** com o operador.

## Sync pós-decisão

Ver [`rankao-api/docs/oracle-migration/scripts/sync-object-storage.sh`](../../../rankao-api/docs/oracle-migration/scripts/sync-object-storage.sh).
