#!/usr/bin/env bash
# Publish the grid archives that `cli/scripts/build-managed-grid.sh` produced, the same way
# publish-managed-tmux-runtime.sh publishes tmux: immutable archives under harness/runtime/grid/, and a
# manifest whose sha256 is what the installer and the daemon trust — never a checksum file fetched
# at install time. Its own manifest, harness/runtime/grid/metadata.json, rather than an entry in
# Node's: install.sh slices a manifest by the FIRST "<platform>" key it finds, and Node's already has one.
#
# The manifest's version is the PIN. `install.sh` lays that grid down; the daemon moves every installed
# machine to it on its next start (ensureManagedGrid, cli/src/lib/runtimeInstall.ts) — which is why
# this refuses a version below GRID_VERSION_FLOOR (cli/src/lib/gridExec.ts): a daemon would refuse it
# too, and a manifest nobody can follow is a manifest that pins nothing.
#
# Usage: bash scripts/publish-managed-grid-runtime.sh 0.3.47 <dir holding grid-0.3.47-<platform>.tar.gz>
#        GRID_PLATFORMS="darwin-arm64 linux-x64" … to publish fewer platforms than the default four.
set -euo pipefail
set +x

VERSION="${1:-}"
ARCHIVES_DIR="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ -z "$ARCHIVES_DIR" ]]; then
  echo "usage: $0 <grid version, e.g. 0.3.47> <archives dir>" >&2
  exit 2
fi
[[ -d "$ARCHIVES_DIR" ]] || { echo "error: $ARCHIVES_DIR is not a directory" >&2; exit 2; }

for command in gsutil shasum python3; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "error: $command is required" >&2
    exit 1
  }
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLOOR="$(sed -n "s/^export const GRID_VERSION_FLOOR = '\([0-9.]*\)'.*/\1/p" "$REPO_ROOT/cli/src/lib/gridExec.ts")"
[[ -n "$FLOOR" ]] || { echo "error: could not read GRID_VERSION_FLOOR from cli/src/lib/gridExec.ts" >&2; exit 1; }
if [[ "$(printf '%s\n%s\n' "$FLOOR" "$VERSION" | sort -V | head -1)" != "$FLOOR" ]]; then
  echo "error: grid $VERSION is below GRID_VERSION_FLOOR ($FLOOR) — the daemon would refuse this pin" >&2
  exit 1
fi

GCS_BUCKET="${GCS_BUCKET:-s3-autonomous-upgrade-3}"
PUBLIC_BASE="${GCS_PUBLIC_BASE_URL:-https://storage.googleapis.com/${GCS_BUCKET}}"
METADATA_PATH="${METADATA_PATH:-harness/runtime/grid/metadata.json}"
PLATFORMS="${GRID_PLATFORMS:-darwin-arm64 darwin-x64 linux-x64 linux-arm64}"
WORK_DIR="$(mktemp -d)"
SRC="$WORK_DIR/metadata.json"
DST="$WORK_DIR/metadata.next.json"
trap 'rm -rf "$WORK_DIR"' EXIT

# Every named platform or nothing: a manifest naming some and not others would make the installer's
# behaviour depend on which computer it runs on. Publish fewer on purpose with GRID_PLATFORMS.
declare -a ENTRIES=()
for platform in $PLATFORMS; do
  archive="grid-${VERSION}-${platform}.tar.gz"
  archive_path="$ARCHIVES_DIR/$archive"
  [[ -f "$archive_path" ]] || { echo "error: missing $archive_path" >&2; exit 1; }
  root="grid-${VERSION}-${platform}"
  tar -tzf "$archive_path" | grep -qx "${root}/bin/grid" || {
    echo "error: $archive has no ${root}/bin/grid" >&2
    exit 1
  }
  sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  size="$(wc -c < "$archive_path" | tr -d ' ')"
  ENTRIES+=("$platform|$VERSION|$archive|$sha256|$size|$root")
done

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r platform version archive sha256 size root <<< "$entry"
  object_path="harness/runtime/grid/v${version}/${archive}"
  echo ">> uploading $archive ($size bytes, sha256 $sha256)"
  gsutil -h 'Cache-Control:public, max-age=31536000, immutable' cp \
    "$ARCHIVES_DIR/$archive" "gs://${GCS_BUCKET}/${object_path}"
done

if ! gsutil cp "gs://${GCS_BUCKET}/${METADATA_PATH}" "$SRC" 2>/dev/null; then
  printf '{}' > "$SRC"
fi

python3 - "$SRC" "$DST" "${PUBLIC_BASE%/}" "${ENTRIES[@]}" <<'PY'
import json, sys
src, dst, public_base, *entries = sys.argv[1:]
try:
    with open(src) as f:
        document = json.load(f)
except (OSError, json.JSONDecodeError):
    document = {}
if not isinstance(document, dict):
    document = {}
grid = document.get("grid")
if not isinstance(grid, dict):
    grid = {}
document["grid"] = grid
for entry in entries:
    platform, version, archive, sha256, size, root = entry.split("|", 5)
    grid[platform] = {
        "version": version,
        "url": f"{public_base}/harness/runtime/grid/v{version}/{archive}",
        "sha256": sha256,
        "size": int(size),
        "archiveRoot": root,
    }
with open(dst, "w") as f:
    json.dump(document, f, indent=2)
    f.write("\n")
PY

gsutil -h 'Content-Type:application/json' \
       -h 'Cache-Control:no-cache, no-store, must-revalidate' \
       cp "$DST" "gs://${GCS_BUCKET}/${METADATA_PATH}"

echo ">> published managed grid ${VERSION} for: ${PLATFORMS}"
echo ">> manifest: ${PUBLIC_BASE%/}/${METADATA_PATH}"
