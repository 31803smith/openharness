#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. toolchain/runtimes.sh
harness_node 20.19 || exit 1
echo "ok   Node $(node --version) via runtimes.sh"
if ! node toolchain/smoke.mjs 2>/dev/null; then
  echo "miss Vega dependencies — run toolchain/setup.sh"
  exit 1
fi
