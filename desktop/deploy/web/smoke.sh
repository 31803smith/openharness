#!/usr/bin/env bash
# Smoke-test a running web image against its release manifest — the website's check-harness-web.mjs,
# plus the check that would have stopped v1.2.22_web: `/` must be the Flutter app, not some other page.
#
#   bash smoke.sh http://127.0.0.1:8080 harness-web-release.json
# No -e: every check runs and reports, and the exit status says whether any failed.
set -uo pipefail

BASE="${1:?usage: smoke.sh <base-url> <harness-web-release.json>}"
MANIFEST="${2:?usage: smoke.sh <base-url> <harness-web-release.json>}"
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$MANIFEST")"
SHA12="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"][:12])' "$MANIFEST")"
ASSET_BASE="/harness-web/releases/$VERSION-$SHA12/"
FAILED=0

check() { # <description> <condition-exit-code>
  if [ "$2" -eq 0 ]; then echo "  ok    $1"; else echo "  FAIL  $1"; FAILED=1; fi
}

for _ in $(seq 1 30); do curl -fs "$BASE/healthz" >/dev/null && break; sleep 1; done

for route in / /s/11111111-1111-4111-8111-111111111111 '/auth/callback?code=fixture-code&state=fixture-state' /callback /harness-web; do
  headers="$(curl -s -D - -o /tmp/harness-web-smoke.html "$BASE$route")"
  html="$(cat /tmp/harness-web-smoke.html)"
  grep -q '^HTTP/[0-9.]* 200' <<<"$headers"; check "$route → 200" $?
  grep -qi '^content-type: text/html' <<<"$headers"; check "$route is HTML" $?
  grep -qi '^cache-control: no-store' <<<"$headers"; check "$route is no-store" $?
  grep -qi '^referrer-policy: no-referrer' <<<"$headers"; check "$route sends no referrer" $?
  grep -q '<base href="/harness-web/">' <<<"$html"; check "$route is the Flutter app" $?
  grep -qF "\"entrypointBaseUrl\":\"$ASSET_BASE\"" <<<"$html"; check "$route loads $ASSET_BASE" $?
  ! grep -q 'fixture-code' <<<"$html"; check "$route does not echo the callback code" $?
done

for spec in 'main.dart.js|javascript' 'assets/FontManifest.json|json' 'canvaskit/chromium/canvaskit.wasm|application/wasm'; do
  path="${spec%%|*}"; type="${spec#*|}"
  headers="$(curl -s -I "$BASE$ASSET_BASE$path")"
  grep -q '^HTTP/[0-9.]* 200' <<<"$headers"; check "$path → 200" $?
  grep -qi "^content-type: .*$type" <<<"$headers"; check "$path is $type" $?
  grep -qi '^cache-control: .*immutable' <<<"$headers"; check "$path is immutable" $?
done

curl -s "$BASE/harness-web/release.json" | grep -q "\"version\": \"$VERSION\""; check "release.json reports $VERSION" $?
[ "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/download")" = 404 ]; check "website routes are not served here" $?

rm -f /tmp/harness-web-smoke.html
[ "$FAILED" -eq 0 ] || { echo "smoke test FAILED"; exit 1; }
echo "smoke test passed: Harness web $VERSION"
