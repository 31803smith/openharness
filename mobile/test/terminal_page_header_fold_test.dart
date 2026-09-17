import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/phone/terminal_header.dart';
import 'package:harness_mobile/phone/terminal_page.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';
import 'package:xterm/xterm.dart';

import 'voice_fakes.dart';

/// Scrolling folds the header away — and that must never reach the far machine.
///
/// The header used to shrink out of the page's column and hand its height to
/// the terminal, so every fold changed the row count: a resize of the agent's
/// shell, a keyframe back, and the whole TUI redrawn, on every change of scroll
/// direction. It slides over the terminal now, which keeps one height.
void main() {
  late AppNotifier notifier;
  late TerminalSession session;
  late VoiceInputController voice;
  late ValueNotifier<String> language;
  late List<Map<String, dynamic>> resizes;

  setUp(() {
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
    );
    resizes = [];
    session = TerminalSession(
      machineId: 'm',
      agentId: 'a',
      agentName: 'Agent',
      engineId: 'claude',
      send: (type, payload) async {
        if (type == 'terminal_resize') resizes.add(payload);
        return true;
      },
      sendBinary: (_) async => true,
    );
    session.status = TerminalSessionStatus.controlling;
    session.streamId = 's';
    for (var line = 0; line < 400; line++) {
      session.terminal.write('output line $line\r\n');
    }
    notifier.adoptSessionForTest(session);
    language = ValueNotifier('en');
    voice = VoiceInputController(
      transcriber: FakeTranscriber().call,
      recorder: FakeVoiceRecorder(),
      language: language,
    );
  });

  tearDown(() {
    voice.dispose();
    language.dispose();
    // Disposes the session too: it was adopted as a pane.
    notifier.dispose();
  });

  testWidgets('folding the header leaves the terminal its size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TerminalPage(
          notifier: notifier,
          machineId: 'm',
          agentId: 'a',
          voice: voice,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.getSize(find.byType(TerminalView));
    resizes.clear();

    // Back into the scrollback, then forward again: the forward push is what
    // sends the header away.
    await tester.drag(find.byType(TerminalView), const Offset(0, 160));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.drag(find.byType(TerminalView), const Offset(0, -80));
    // The slide's ticker starts on the frame after the push, then runs out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Folded: the search bar is no longer where a tap would land on it.
    expect(find.text(TerminalHeader.searchHint).hitTestable(), findsNothing);
    expect(tester.getSize(find.byType(TerminalView)), before);
    // The slide is over; a resize owed to it would be on its way by now.
    await tester.pump(const Duration(seconds: 1));
    expect(resizes, isEmpty);
  });
}
