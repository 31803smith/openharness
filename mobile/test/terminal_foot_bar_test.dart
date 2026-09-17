import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/phone_status.dart';
import 'package:harness_mobile/phone/terminal_foot_bar.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/phone/voice_notice.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRecorder recorder;
  late FakeTranscriber backend;
  late ValueNotifier<String> language;
  late VoiceInputController voice;
  late TerminalSession session;
  late List<(String, Map<String, dynamic>)> frames;

  const live = (label: 'Live', tone: PhoneTone.good);
  final mic = find.byKey(const ValueKey('voice-mic'));
  final cancel = find.byKey(const ValueKey('voice-cancel'));

  setUp(() {
    recorder = FakeVoiceRecorder();
    backend = FakeTranscriber();
    language = ValueNotifier('en');
    voice = VoiceInputController(
      transcriber: backend.call,
      recorder: recorder,
      language: language,
    );
    frames = [];
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
            sendBinary: (_) async => true,
          )
          ..status = TerminalSessionStatus.controlling
          ..streamId = 's';
  });

  tearDown(() {
    voice.dispose();
    language.dispose();
    session.dispose();
  });

  Future<void> pumpBar(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: TerminalFootBar(
            name: 'MacBookPro2021.local',
            status: live,
            voice: voice,
            session: session,
          ),
        ),
      ),
    ),
  );

  testWidgets('at rest it is the machine, its state, and one mic', (
    tester,
  ) async {
    await pumpBar(tester);

    expect(find.text('MacBookPro2021.local'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(mic, findsOneWidget);
    expect(cancel, findsNothing);
    expect(recorder.starts, 0);
  });

  testWidgets('tap to talk, tap again to send it as a turn', (tester) async {
    await pumpBar(tester);
    backend.replies.add('summarise the diff');

    await tester.tap(mic);
    await tester.pump();
    expect(voice.status, VoiceInputStatus.listening);
    expect(find.text('Listening…'), findsOneWidget);

    await tester.tap(mic);
    await tester.pumpAndSettle();

    // The composer's frame, not typed bytes — the machine owns the Enter.
    expect(frames, hasLength(1));
    expect(frames.single.$1, 'message');
    expect(frames.single.$2['content'], 'summarise the diff');
    expect(voice.isIdle, isTrue);
    expect(find.text('MacBookPro2021.local'), findsOneWidget);
  });

  testWidgets('the height holds still whatever the row says', (tester) async {
    await pumpBar(tester);
    final atRest = tester.getSize(find.byType(TerminalFootBar));

    await tester.tap(mic);
    await tester.pump();

    expect(tester.getSize(find.byType(TerminalFootBar)), atRest);
    voice.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('× throws a take away and sends nothing', (tester) async {
    await pumpBar(tester);
    await tester.tap(mic);
    await tester.pump();

    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(recorder.cancels, 1);
    expect(frames, isEmpty);
    expect(cancel, findsNothing);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('a failed send keeps the words, and the mic sends them again', (
    tester,
  ) async {
    session.status = TerminalSessionStatus.takenOver;
    await pumpBar(tester);
    backend.replies.add('deploy');
    await voice.startListening();
    await tester.pump();

    await tester.tap(mic);
    await tester.pumpAndSettle();
    expect(frames, isEmpty);
    expect(find.text(VoiceNotice.notSent), findsOneWidget);
    expect(voice.transcript, 'deploy');

    session.status = TerminalSessionStatus.controlling;
    await pumpBar(tester);
    await tester.tap(mic);
    await tester.pumpAndSettle();

    expect(frames.single.$2['content'], 'deploy');
  });

  testWidgets('no talking while the terminal takes no input', (tester) async {
    session.status = TerminalSessionStatus.takenOver;
    await pumpBar(tester);

    await tester.tap(mic, warnIfMissed: false);
    await tester.pump();

    expect(recorder.starts, 0);
  });
}
