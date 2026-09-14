import 'package:harness/app_shell.dart';
import 'package:harness/core/asset_owner.dart';

import 'phone/phone_shell.dart';

/// Harness for iOS and Android: a viewer onto the machines this device has
/// linked, one agent at a time.
///
/// Everything before the first frame — file logs, the crash log, the keyboard
/// config, the saved appearance — and every screen up to sign-in comes from
/// [startHarness] in `package:harness`, the same code the desktop app runs.
/// This package adds only what a phone needs that a window does not: the shell
/// in `lib/phone/`.
///
/// The app has no harness CLI beside it, so it is a VIEWER build: it holds its
/// own SSO session and terminates the end-to-end encryption to each machine
/// itself (`kViewerMode`, and `viewer/` in `package:harness`). That is decided
/// by the platform, not here — a Mac can run the same path with
/// `--dart-define=HARNESS_VIEWER_MODE=true`.
Future<void> main() {
  // `harness` is a dependency here rather than the root package, so Flutter
  // registers its assets under `packages/harness/…`. Set before the first frame.
  harnessAssetPackage = 'harness';
  return startHarness(
    authenticatedScreen: (app) => PhoneShell(notifier: app),
  );
}
