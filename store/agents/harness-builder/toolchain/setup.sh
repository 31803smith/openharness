#!/usr/bin/env bash
# Harness Builder setup, cwd = the install dir. Installs the Builder's pinned Node tools (playwright-core
# for proof pictures, marked for the Studio), the headless Chromium they drive, and a read-only copy of
# the OpenHarness store the Builder builds against. Idempotent.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/toolchain"
# shellcheck source=runtimes.sh
. ./runtimes.sh
harness_node 20 || exit 1
npm ci --no-audit --no-fund --no-update-notifier --loglevel=error
echo "ok   builder tools: playwright-core $(node -p "require('playwright-core/package.json').version"), marked $(node -p "require('marked/package.json').version")"
if PLAYWRIGHT_BROWSERS_PATH="$ROOT/toolchain/.playwright" node node_modules/playwright-core/cli.js install chromium-headless-shell >/dev/null 2>&1; then
  echo "ok   chromium for proof pictures"
else
  echo "miss chromium for proof pictures did not install — run toolchain/setup.sh again"
  exit 1
fi
"$ROOT/toolchain/fetch-reference.sh"
