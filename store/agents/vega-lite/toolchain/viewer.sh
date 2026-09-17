#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/runtimes.sh"
harness_node 20.19 || exit 1
: "${HARNESS_VIEWER_PORT:?}" "${HARNESS_WORKSPACE:?}"
exec node "$HERE/viewer.mjs"
