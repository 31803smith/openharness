
import 'app_shell.dart';
import 'screens/swarm_screen.dart';

/// Harness for macOS, Linux and Windows: a swarm of terminal panes in one
/// window. Everything before the first frame, and every screen up to sign-in,
/// is [startHarness] — shared with `../mobile`, which mounts a phone shell here
/// instead.
Future<void> main() => startHarness(
  authenticatedScreen: (app) => SwarmScreen(notifier: app),
);
