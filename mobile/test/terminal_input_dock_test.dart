import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/terminal_input_dock.dart';
import 'package:harness_mobile/phone/terminal_key_bar.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/phone/voice_input_panel.dart';
import 'package:harness_mobile/terminal/terminal_binary.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRecorder recorder;
  late FakeTranscriber backend;
  late VoiceInputController voice;
  late TerminalSession session;
  late List<(String, Map<String, dynamic>)> frames;
  late List<TerminalBinaryFrame> keystrokes;
  late int dismissals;
  late int keyboardRequests;

  setUp(() {
    recorder = FakeVoiceRecorder();
    backend = FakeTranscriber();
    voice = VoiceInputController(
      transcriber: backend.call,
      recorder: recorder,
      storage: MemoryKeyValueStore(),
      preferredLocales: const [],
    );
    frames = [];
    keystrokes = [];
    dismissals = 0;
    keyboardRequests = 0;
    session =
        TerminalSession(
            machineId: 'm',
            agentId: 'a',
            agentName: 'Agent',
            engineId: 'claude',
            send: (type, payload) async {
              frames.add((type, payload));
              return true;
            },
            sendBinary: (frame) async {
              keystrokes.add(frame);
              return true;
            },
          )
          ..status = TerminalSessionStatus.controlling
          ..streamId = 's';
  });

  tearDown(() {
    voice.dispose();
    session.dispose();
  });

  Future<void> pumpDock(WidgetTester tester, {bool keyboardUp = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: TerminalInputDock(
                session: session,
                voice: voice,
                keyboardUp: keyboardUp,
                onDismiss: () => dismissals++,
                onUseKeyboard: () => keyboardRequests++,
              ),
            ),
          ),
        ),
      );

  testWidgets('nothing is drawn while no input is up', (tester) async {
    await pumpDock(tester);

    expect(find.byType(TerminalKeyBar), findsNothing);
    expect(find.byType(VoiceInputPanel), findsNothing);
  });

  testWidgets('the keyboard gets the key bar alone', (tester) async {
    await pumpDock(tester, keyboardUp: true);

    expect(find.byType(TerminalKeyBar), findsOneWidget);
    expect(find.byType(VoiceInputPanel), findsNothing);
  });

  testWidgets('voice input takes the key bar\'s place, and Send makes a turn', (
    tester,
  ) async {
    await pumpDock(tester);
    voice.open();
    await tester.pump();

    expect(find.byType(TerminalKeyBar), findsNothing);
    expect(find.byType(VoiceInputPanel), findsOneWidget);
    // Open is not recording: the mic waits to be pressed.
    expect(find.text('Tap the mic to talk'), findsOneWidget);
    expect(recorder.starts, 0);

    backend.replies.add('summarise the diff');
    await tester.tap(find.byKey(const ValueKey('voice-mic')));
    await tester.pump();
    expect(find.text('Listening…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('voice-mic')));
    await tester.pump();
    expect(find.text('summarise the diff'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-send')));
    await tester.pumpAndSettle();

    // The composer's frame, not typed bytes — the machine owns the Enter.
    expect(frames, hasLength(1));
    expect(frames.single.$1, 'message');
    expect(frames.single.$2['content'], 'summarise the diff');
    expect(find.text('summarise the diff'), findsNothing);
  });

  testWidgets('Send is dead while the terminal takes no input', (tester) async {
    session.status = TerminalSessionStatus.takenOver;
    await pumpDock(tester);
    backend.replies.add('hello');
    voice.open();
    await voice.startListening();
    await voice.stopListening();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('voice-send')));
    await tester.pump();

    expect(frames, isEmpty);
    expect(voice.transcript, 'hello');
  });

  testWidgets('Keyboard and ⌄ hand back to the page', (tester) async {
    await pumpDock(tester);
    voice.open();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('voice-keyboard')));
    await tester.tap(find.byKey(const ValueKey('voice-hide')));

    expect(keyboardRequests, 1);
    expect(dismissals, 1);
  });

  testWidgets('with nothing said, Send is Enter for what the prompt holds', (
    tester,
  ) async {
    await pumpDock(tester);
    voice.open();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('voice-send')));
    await tester.pump();
    // The input path queues its send on a future chain the fake clock does not
    // drain; a real turn of the event loop does.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(frames, isEmpty, reason: 'no message: nothing was said');
    expect(
      keystrokes
          .where((frame) => frame.kind == TerminalBinaryKind.input)
          .expand((frame) => frame.bytes),
      [13],
    );
  });

  testWidgets('Send mid-sentence finishes the take and sends it', (
    tester,
  ) async {
    backend.replies.add('ship it');
    await pumpDock(tester);
    voice.open();
    await voice.startListening();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('voice-send')));
    await tester.pumpAndSettle();

    expect(recorder.stops, 1);
    expect(frames.single.$2['content'], 'ship it');
  });

  testWidgets('the language chip names the language takes are sent in', (
    tester,
  ) async {
    await pumpDock(tester);
    voice.open();
    await tester.pump();
    expect(find.text('EN'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('voice-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();

    expect(find.text('VI'), findsOneWidget);
    expect(voice.language, 'vi');
  });

  testWidgets('the mic stops a take and starts the next', (tester) async {
    await pumpDock(tester);
    voice.open();
    await voice.startListening();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('voice-mic')));
    await tester.pump();
    expect(voice.status, VoiceInputStatus.idle);
    expect(recorder.stops, 1);

    await tester.tap(find.byKey(const ValueKey('voice-mic')));
    await tester.pump();
    expect(voice.status, VoiceInputStatus.listening);
    // Stopped here, not left breathing: the ring repeats forever.
    voice.close();
    await tester.pumpAndSettle();
  });
}
