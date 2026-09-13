#!/bin/bash
set -euo pipefail

desktop_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_sdk="${1:?Pass the Flutter SDK path}"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/harness-keymap.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
cd "$desktop_dir"
# Export the production Dart adapter's resolved payload, then exercise that
# exact payload in Swift. No user config, real windows or agent connections.
HARNESS_KEYMAP_FIXTURE_PATH="$check_dir/bindings.json" \
  "$flutter_sdk/bin/flutter" test --no-pub test/keymap_native_test.dart
cat macos/Runner/HarnessKeymap.swift tool/keymap_native_checks.swift > "$check_dir/main.swift"
xcrun swiftc -swift-version 5 -module-cache-path "$check_dir/module-cache" \
  "$check_dir/main.swift" -o "$check_dir/check-keymap"
"$check_dir/check-keymap" "$check_dir/bindings.json"
HARNESS_TITLEBAR_KEYMAP_FIXTURE="$check_dir/bindings.json" \
  bash tool/check_swarm_titlebar.sh "$flutter_sdk" --window-layout
