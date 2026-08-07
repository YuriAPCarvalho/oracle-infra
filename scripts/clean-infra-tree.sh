#!/usr/bin/env bash
set -euo pipefail
git config --global --add safe.directory /opt/infra
cd /opt/infra
echo "=== before ==="
git status -sb
git checkout -- .
git clean -fd
echo "=== after ==="
git status -sb
if [[ -z "$(git status --porcelain)" ]]; then
  echo CLEAN_OK
else
  echo STILL_DIRTY
  git status --porcelain
  exit 1
fi
