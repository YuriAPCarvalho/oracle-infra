#!/usr/bin/env bash
#
# r2-upload.sh
# Upload Layer-1 backup artifacts to Cloudflare R2 (S3-compatible).
# Free-tier guardrails: soft storage cap (default 8 GiB) + keep last N (default 3).
#
# Required env:
#   R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET
#   BACKUP_ARCHIVE  path to .tar.gz
#   BACKUP_META     path to .meta.json
#
# Optional:
#   R2_KEEP_LAST          default 3
#   R2_SOFT_MAX_BYTES     default 8589934592 (8 GiB)
#   R2_PREFIX             default full/
#
# Uses AWS CLI against the R2 endpoint. One ListObjectsV2 per run.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

R2_KEEP_LAST="${R2_KEEP_LAST:-3}"
R2_SOFT_MAX_BYTES="${R2_SOFT_MAX_BYTES:-8589934592}"
R2_PREFIX="${R2_PREFIX:-full/}"
R2_PREFIX="${R2_PREFIX%/}/"

require_r2_config() {
  local missing=0
  local var
  for var in R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET; do
    if [[ -z "${!var:-}" ]]; then
      warn "R2 upload skipped: ${var} is not set"
      missing=1
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    return 1
  fi
  return 0
}

r2_endpoint() {
  printf 'https://%s.r2.cloudflarestorage.com\n' "${R2_ACCOUNT_ID}"
}

aws_r2() {
  AWS_ACCESS_KEY_ID="${R2_ACCESS_KEY_ID}" \
    AWS_SECRET_ACCESS_KEY="${R2_SECRET_ACCESS_KEY}" \
    AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}" \
    AWS_EC2_METADATA_DISABLED=true \
    aws --endpoint-url "$(r2_endpoint)" "$@"
}

# Print: Key\tSize per object under prefix (empty OK). Paginated ListObjectsV2.
list_prefix_objects() {
  local token=""
  local page
  local next
  while true; do
    if [[ -n "${token}" ]]; then
      page="$(aws_r2 s3api list-objects-v2 \
        --bucket "${R2_BUCKET}" \
        --prefix "${R2_PREFIX}" \
        --continuation-token "${token}" \
        --output json 2>/dev/null || true)"
    else
      page="$(aws_r2 s3api list-objects-v2 \
        --bucket "${R2_BUCKET}" \
        --prefix "${R2_PREFIX}" \
        --output json 2>/dev/null || true)"
    fi
    # awscli v1 may emit empty/non-JSON for an empty prefix.
    if [[ -z "${page}" || "${page}" != \{* ]]; then
      page='{"Contents":[]}'
    fi
    python3 -c '
import json, sys
raw = sys.stdin.read().strip() or "{\"Contents\":[]}"
data = json.loads(raw)
for obj in data.get("Contents") or []:
    print("%s\t%s" % (obj["Key"], obj["Size"]))
' <<<"${page}"
    next="$(python3 -c '
import json, sys
raw = sys.stdin.read().strip() or "{\"Contents\":[]}"
data = json.loads(raw)
print(data.get("NextContinuationToken") or "")
' <<<"${page}")"
    if [[ -z "${next}" ]]; then
      break
    fi
    token="${next}"
  done
}

stem_from_key() {
  local key="$1"
  local base="${key##*/}"
  base="${base%.tar.gz.sha256}"
  base="${base%.tar.gz}"
  base="${base%.meta.json}"
  printf '%s\n' "${base}"
}

main() {
  local archive meta checksum
  local archive_base stem
  local key_tar key_sha key_meta
  local new_bytes current_bytes reclaim_bytes projected
  local listing
  local -a existing_stems=()
  local -a delete_keys=()
  local line key size stem_i
  local keep_stems

  if ! require_r2_config; then
    exit 0
  fi

  archive="${BACKUP_ARCHIVE:-}"
  meta="${BACKUP_META:-}"
  if [[ -z "${archive}" || ! -f "${archive}" ]]; then
    warn "R2 upload skipped: BACKUP_ARCHIVE missing or not a file"
    exit 0
  fi
  if [[ -z "${meta}" || ! -f "${meta}" ]]; then
    warn "R2 upload skipped: BACKUP_META missing or not a file"
    exit 0
  fi
  checksum="${archive}.sha256"
  if [[ ! -f "${checksum}" ]]; then
    warn "R2 upload skipped: checksum file not found: ${checksum}"
    exit 0
  fi

  if ! command -v aws >/dev/null 2>&1; then
    warn "R2 upload skipped: aws CLI not found (install awscli v2)"
    exit 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    warn "R2 upload skipped: python3 not found"
    exit 0
  fi

  if ! [[ "${R2_KEEP_LAST}" =~ ^[1-9][0-9]*$ ]]; then
    die "R2_KEEP_LAST must be a positive integer (got: ${R2_KEEP_LAST})"
  fi
  if ! [[ "${R2_SOFT_MAX_BYTES}" =~ ^[0-9]+$ ]]; then
    die "R2_SOFT_MAX_BYTES must be a non-negative integer"
  fi

  archive_base="$(basename "${archive}")"
  stem="${archive_base%.tar.gz}"
  key_tar="${R2_PREFIX}${archive_base}"
  key_sha="${R2_PREFIX}${archive_base}.sha256"
  key_meta="${R2_PREFIX}${stem}.meta.json"

  new_bytes=0
  new_bytes=$((new_bytes + $(stat -c %s "${archive}")))
  new_bytes=$((new_bytes + $(stat -c %s "${checksum}")))
  new_bytes=$((new_bytes + $(stat -c %s "${meta}")))

  info "R2: listing s3://${R2_BUCKET}/${R2_PREFIX} (ListObjectsV2)"
  if ! listing="$(list_prefix_objects)"; then
    warn "R2 upload skipped: failed to list bucket (check credentials / aws CLI)"
    exit 0
  fi

  current_bytes=0
  declare -A stem_keys=()
  declare -A stem_sizes=()
  declare -A stem_seen=()

  while IFS=$'\t' read -r key size; do
    [[ -z "${key:-}" ]] && continue
    [[ ! "${size}" =~ ^[0-9]+$ ]] && continue
    current_bytes=$((current_bytes + size))
    stem_i="$(stem_from_key "${key}")"
    [[ -z "${stem_i}" || "${stem_i}" == .* ]] && continue
    stem_seen["${stem_i}"]=1
    stem_keys["${stem_i}"]+="${key}"$'\n'
    stem_sizes["${stem_i}"]=$((${stem_sizes["${stem_i}"]:-0} + size))
  done <<<"${listing}"

  # Stems sorted newest-first (timestamp in name: backup-YYYYMMDD-HHMMSS)
  mapfile -t existing_stems < <(printf '%s\n' "${!stem_seen[@]}" | sort -r)

  reclaim_bytes=0
  delete_keys=()
  # After upload, remote set = existing without this stem + new stem, keep R2_KEEP_LAST
  keep_stems=()
  keep_stems+=("${stem}")
  for stem_i in "${existing_stems[@]}"; do
    [[ "${stem_i}" == "${stem}" ]] && continue
    if [[ "${#keep_stems[@]}" -lt "${R2_KEEP_LAST}" ]]; then
      keep_stems+=("${stem_i}")
    else
      reclaim_bytes=$((reclaim_bytes + ${stem_sizes["${stem_i}"]:-0}))
      while IFS= read -r key; do
        [[ -z "${key}" ]] && continue
        delete_keys+=("${key}")
      done <<<"${stem_keys["${stem_i}"]:-}"
    fi
  done

  # If replacing same stem keys already present, reclaim their size before put
  if [[ -n "${stem_sizes["${stem}"]:-}" ]]; then
    reclaim_bytes=$((reclaim_bytes + stem_sizes["${stem}"]))
    while IFS= read -r key; do
      [[ -z "${key}" ]] && continue
      delete_keys+=("${key}")
    done <<<"${stem_keys["${stem}"]:-}"
  fi

  projected=$((current_bytes + new_bytes - reclaim_bytes))
  if [[ "${projected}" -lt 0 ]]; then
    projected=0
  fi

  kv "R2 bucket" "${R2_BUCKET}"
  kv "Current bytes" "${current_bytes}"
  kv "New upload" "${new_bytes}"
  kv "Reclaim" "${reclaim_bytes}"
  kv "Projected" "${projected}"
  kv "Soft max" "${R2_SOFT_MAX_BYTES}"
  kv "Keep last" "${R2_KEEP_LAST}"

  if [[ "${projected}" -gt "${R2_SOFT_MAX_BYTES}" ]]; then
    warn "R2 upload skipped: projected ${projected} bytes exceeds soft cap ${R2_SOFT_MAX_BYTES} (free-tier guard)"
    record_r2_skip "${current_bytes}" "${#existing_stems[@]}"
    exit 0
  fi

  info "R2: uploading ${archive_base} (+ sha256 + meta)"
  aws_r2 s3 cp "${archive}" "s3://${R2_BUCKET}/${key_tar}" --only-show-errors
  aws_r2 s3 cp "${checksum}" "s3://${R2_BUCKET}/${key_sha}" --only-show-errors
  aws_r2 s3 cp "${meta}" "s3://${R2_BUCKET}/${key_meta}" --only-show-errors

  if [[ "${#delete_keys[@]}" -gt 0 ]]; then
    info "R2: retention deleting ${#delete_keys[@]} object(s)"
    for key in "${delete_keys[@]}"; do
      aws_r2 s3api delete-object --bucket "${R2_BUCKET}" --key "${key}" >/dev/null
    done
  fi

  # Object sets kept after this run (for metrics); approx object count = stems * 3 files.
  local kept_sets="${#keep_stems[@]}"
  record_r2_success "${projected}" "$((kept_sets * 3))"

  ok "R2 upload complete: s3://${R2_BUCKET}/${key_tar}"
}

# Persist markers for Prometheus textfile (emitted by storage-textfile.sh).
r2_metrics_paths() {
  local data_root
  data_root="$(persistent_data_root)"
  R2_MARKER="${data_root}/backups/full/.last-r2-success"
  R2_SKIP_MARKER="${data_root}/backups/full/.last-r2-skip"
  R2_USAGE_FILE="${data_root}/backups/full/.r2-usage"
}

record_r2_success() {
  local bytes="$1"
  local objects="$2"
  r2_metrics_paths
  mkdir -p "$(dirname "${R2_MARKER}")" 2>/dev/null || true
  touch "${R2_MARKER}" 2>/dev/null || sudo touch "${R2_MARKER}" || true
  printf 'bytes=%s\nobjects=%s\nsoft_max=%s\n' "${bytes}" "${objects}" "${R2_SOFT_MAX_BYTES}" >"${R2_USAGE_FILE}"
}

record_r2_skip() {
  local bytes="$1"
  local stems="$2"
  r2_metrics_paths
  mkdir -p "$(dirname "${R2_SKIP_MARKER}")" 2>/dev/null || true
  touch "${R2_SKIP_MARKER}" 2>/dev/null || sudo touch "${R2_SKIP_MARKER}" || true
  printf 'bytes=%s\nobjects=%s\nsoft_max=%s\n' "${bytes}" "$((stems * 3))" "${R2_SOFT_MAX_BYTES}" >"${R2_USAGE_FILE}"
}

main "$@"
