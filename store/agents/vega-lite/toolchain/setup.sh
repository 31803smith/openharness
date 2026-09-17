#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. toolchain/runtimes.sh
harness_node 20.19 || exit 1
lock_sha="$(_harness_sha256 package-lock.json)"
if [ -f node_modules/.harness-lock ] && [ "$(cat node_modules/.harness-lock)" = "$lock_sha" ]; then
  if node toolchain/smoke.mjs >/dev/null 2>&1; then
    echo "ok   pinned Vega toolchain already installed"
    exit 0
  fi
fi
install_tmp="$(mktemp -d "$PWD/.install.XXXXXX")"
trap 'rm -rf "$install_tmp"' EXIT
cp package.json package-lock.json "$install_tmp/"
cp toolchain/smoke.mjs "$install_tmp/smoke.mjs"
if ! npm ci --prefix "$install_tmp" --ignore-scripts --no-audit --no-fund; then
  echo "miss Vega dependencies — check the npm connection and run toolchain/setup.sh again"
  exit 1
fi
if ! node "$install_tmp/smoke.mjs"; then
  echo "miss Vega compiler/render smoke test — run toolchain/setup.sh again"
  exit 1
fi
printf "%s\n" "$lock_sha" > "$install_tmp/node_modules/.harness-lock"
if [ -d node_modules ]; then mv node_modules "$install_tmp/previous"; fi
mv "$install_tmp/node_modules" node_modules
echo "ok   locked Vega dependencies installed locally"
