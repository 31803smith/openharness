#!/usr/bin/env bash
# Publish cli/scripts/install.sh — the one-line CLI installer — to the public, CDN-fronted bucket
# everything else here publishes to. Same idiom as upload-cli.sh: one `cp` with explicit headers, no
# build step, no version to bump — this is one static file. `make upload-cli-install-sh` from the
# repo root.
#
#   gs://s3-autonomous-upgrade-3/harness/cli/install.sh -> https://cdn.autonomous.ai/harness/cli/install.sh
#
# Cache-Control is no-cache/no-store/must-revalidate at the GCS origin. A positive max-age does not
# survive Cloudflare (which fronts cdn.autonomous.ai): it rewrites it to its own ~31-day edge TTL
# (`cache-control: public, max-age=2678400` observed for an origin max-age=300), a zone-level setting
# nothing in this repo can override. no-cache/no-store is the one directive it DOES honor (confirmed
# via `cf-cache-status: BYPASS`), so that is what keeps a publish reaching people promptly. After
# running this, verify the CDN itself serves the new bytes — the command this script prints at the end.
#
# Prereqs: `gcloud storage` (or gsutil) authenticated with WRITE access on the bucket.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # cli/
SCRIPT="$ROOT/scripts/install.sh"

GCS_BUCKET="${GCS_BUCKET:-s3-autonomous-upgrade-3}"
GCS_PATH="harness/cli/install.sh"
CDN_URL="https://cdn.autonomous.ai/${GCS_PATH}"

# --- GCS client: `gcloud storage` if we have it, else gsutil (see upload-cli.sh for why) ---
if command -v gcloud >/dev/null 2>&1 && gcloud storage --help >/dev/null 2>&1; then
  GCS_CLI=gcloud
elif command -v gsutil >/dev/null 2>&1; then
  GCS_CLI=gsutil
  echo ">> note: falling back to gsutil (no 'gcloud storage'); this will not work under workload identity federation" >&2
else
  echo "error: neither 'gcloud storage' nor gsutil found — install/authenticate the gcloud SDK" >&2
  exit 1
fi

[ -f "$SCRIPT" ] || { echo "error: $SCRIPT not found" >&2; exit 1; }
sh -n "$SCRIPT"   # fail before uploading a script that doesn't even parse

CC="no-cache, no-store, must-revalidate"
CT="text/x-shellscript; charset=utf-8"
echo ">> uploading $SCRIPT"
echo "   ->  gs://${GCS_BUCKET}/${GCS_PATH}"
if [ "$GCS_CLI" = gcloud ]; then
  gcloud storage cp --cache-control="$CC" --content-type="$CT" "$SCRIPT" "gs://${GCS_BUCKET}/${GCS_PATH}"
else
  gsutil -h "Cache-Control:$CC" -h "Content-Type:$CT" cp "$SCRIPT" "gs://${GCS_BUCKET}/${GCS_PATH}"
fi

echo ""
echo ">> published: ${CDN_URL}"
echo ">> verify the CDN edge actually serves it (may lag the origin — see this script's header):"
echo "     curl -fsSL ${CDN_URL} | head -5"
