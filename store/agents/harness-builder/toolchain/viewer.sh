#!/usr/bin/env bash
# Builder Studio, the Harness Builder's pane. Harness runs this with HARNESS_VIEWER_PORT,
# HARNESS_WORKSPACE and HARNESS_DSH_DIR, through a shell whose PATH may hold no node.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${HARNESS_VIEWER_PORT:?HARNESS_VIEWER_PORT is required}"
: "${HARNESS_WORKSPACE:?HARNESS_WORKSPACE is required}"
# shellcheck source=runtimes.sh
. "$ROOT/toolchain/runtimes.sh"
harness_node 20 || exit 1
exec node "$ROOT/toolchain/studio/server.mjs"
