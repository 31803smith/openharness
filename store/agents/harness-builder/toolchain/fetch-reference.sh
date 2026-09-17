#!/usr/bin/env bash
# The OpenHarness store at the commit VERSIONS pins, read-only, sparse and blob-less, into
# reference/openharness: the contract, runtimes.sh, the starter, the shared viewers, and the harnesses
# the Builder learns from. A matching reference/openharness/.harness-commit means it is already here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. ./VERSIONS
dest=reference/openharness
if [ -f "$dest/.harness-commit" ] && [ "$(cat "$dest/.harness-commit")" = "$OPENHARNESS_COMMIT" ]; then
  echo "ok   reference store @ ${OPENHARNESS_COMMIT:0:12}"
  exit 0
fi
command -v git >/dev/null 2>&1 || { echo "miss git on PATH (the reference store is fetched with it)"; exit 1; }
rm -rf reference/partial
mkdir -p reference
git init -q reference/partial
git -C reference/partial remote add origin "$OPENHARNESS_REPO"
read -r -a patterns <<<"$OPENHARNESS_SPARSE"
git -C reference/partial sparse-checkout set --no-cone -- "${patterns[@]}"
git -C reference/partial fetch -q --depth 1 --filter=blob:none origin "$OPENHARNESS_COMMIT"
git -C reference/partial checkout -q FETCH_HEAD
echo "$OPENHARNESS_COMMIT" > reference/partial/.harness-commit
rm -rf "$dest"
mv reference/partial "$dest"
echo "ok   reference store @ ${OPENHARNESS_COMMIT:0:12} ($(du -sh "$dest" | cut -f1))"
