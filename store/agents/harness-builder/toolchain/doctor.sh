#!/usr/bin/env bash
# Harness Builder doctor, cwd = the install dir: one line per thing the Builder needs.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
. ./VERSIONS
# shellcheck source=runtimes.sh
. toolchain/runtimes.sh
status=0
if harness_node 20 >/dev/null; then echo "ok   node $(node -v)"; else harness_node 20; status=1; fi
if [ -f toolchain/node_modules/playwright-core/package.json ]; then echo "ok   playwright-core"; else echo "miss playwright-core — run toolchain/setup.sh"; status=1; fi
if compgen -G "toolchain/.playwright/chromium_headless_shell-*" >/dev/null; then echo "ok   chromium for proof pictures"; else echo "miss chromium for proof pictures — run toolchain/setup.sh"; status=1; fi
if [ "$(cat reference/openharness/.harness-commit 2>/dev/null)" = "$OPENHARNESS_COMMIT" ]; then echo "ok   reference store @ ${OPENHARNESS_COMMIT:0:12}"; else echo "miss reference store — run toolchain/setup.sh"; status=1; fi
if command -v claude >/dev/null 2>&1; then echo "ok   claude for proofs"; else echo "warn claude is not on PATH: proofs cannot run a fresh agent"; fi
if command -v harness >/dev/null 2>&1; then echo "ok   harness CLI for conformance checks"; else echo "warn harness CLI is not on PATH: builder check skips harness dsh check"; fi
exit $status
