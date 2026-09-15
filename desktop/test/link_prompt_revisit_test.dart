// A dismissed link prompt opens again when asked for.
//
// Reported from the desk: on the welcome's Machines list, "Link required" popped once, and after
// Cancel a second click did nothing at all. Cancel marks the machine dismissed so the reactive gates
// stop insisting; the dialog's own "still needed?" check read that mark and closed itself on the
// first frame. The row stayed dead for the rest of the run.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/state/app_state.dart';

void main() {
  test('revisiting clears the dismissal so the prompt can show again', () {
    final app = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    expect(app.isLinkPromptDismissed('m1'), isFalse);
    app.dismissLinkPrompt('m1');
    expect(app.isLinkPromptDismissed('m1'), isTrue);
    app.revisitLinkPrompt('m1');
    expect(app.isLinkPromptDismissed('m1'), isFalse);
    // Idempotent both ways: a second revisit is not an error and notifies nobody.
    var notified = 0;
    app.addListener(() => notified++);
    app.revisitLinkPrompt('m1');
    expect(notified, 0);
    app.dispose();
  });
}
