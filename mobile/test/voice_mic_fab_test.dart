import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/phone/voice_mic_fab.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';

import 'voice_fakes.dart';

/// The mic over the terminal, held to talk: press to record, release to send the
/// take as a turn, slide off to throw it away.
void main() {
  late FakeVoiceRecorder recorder;
  late FakeTranscriber backend;
  late ValueNotifier<String> language;
  late VoiceInputController voice;
  late TerminalSession session;
  late List<(String, Map<String, dynamic>)> frames;

  final mic = find.byKey(const ValueKey('voice-mic'));

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
    session = TerminalSession(
      machineId: 'm',
      agentId: 'a',
      agentName: 'Agent',
      engineId: 'claude',
      send: (type, payload) async {
        frames.add((type, payload));
        return true;
      },
      sendBinary: (_) async => true,
    );
    session.status = TerminalSessionStatus.controlling;
    session.streamId = 's';
  });

  tearDown(() {
    voice.dispose();
    language.dispose();
    session.dispose();
  });

  Widget fab() =>
      VoiceMicFab(voice: voice, session: session, onSlipChanged: (_) {});

  Future<void> pumpFab(WidgetTester tester, {Widget? around}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: around ?? Center(child: fab())),
        ),
      );

  List<Object?> sentTurns() => [
    for (final (type, payload) in frames)
      if (type == 'message') payload['content'],
  ];

  testWidgets('hold to talk, release to send it as a turn', (tester) async {
    await pumpFab(tester);
    backend.replies.add('summarise the diff');

    final thumb = await tester.startGesture(tester.getCenter(mic));
    await tester.pump();
    expect(voice.status, VoiceInputStatus.listening);

    await thumb.up();
    await tester.pumpAndSettle();

    // The composer's frame, not typed bytes — the machine owns the Enter.
    expect(sentTurns(), ['summarise the diff']);
    expect(voice.isIdle, isTrue);
  });

  testWidgets('sliding off before letting go throws the take away', (
    tester,
  ) async {
    await pumpFab(tester);
    backend.replies.add('never mind');

    final thumb = await tester.startGesture(tester.getCenter(mic));
    await tester.pump();
    await thumb.moveBy(const Offset(0, -300));
    await tester.pump();
    await thumb.up();
    await tester.pumpAndSettle();

    expect(recorder.cancels, 1);
    expect(frames, isEmpty);
  });

  testWidgets('no talking while the terminal takes no input', (tester) async {
    session.status = TerminalSessionStatus.takenOver;
    await pumpFab(tester);

    final thumb = await tester.startGesture(tester.getCenter(mic));
    await tester.pump();
    await thumb.up();
    await tester.pumpAndSettle();

    expect(recorder.starts, 0);
    expect(frames, isEmpty);
  });

  testWidgets('a thumb drifting sideways mid-take does not swipe the pager', (
    tester,
  ) async {
    final pager = PageController();
    addTearDown(pager.dispose);
    await pumpFab(
      tester,
      around: PageView(
        controller: pager,
        children: [
          Center(child: fab()),
          const SizedBox.expand(),
        ],
      ),
    );

    final thumb = await tester.startGesture(tester.getCenter(mic));
    await tester.pump();
    // Past half the page: a pager that had the thumb would settle on the next
    // agent rather than snap back.
    for (var step = 0; step < 6; step++) {
      await thumb.moveBy(const Offset(-100, 0));
      await tester.pump();
    }
    await thumb.up();
    await tester.pumpAndSettle();

    expect(pager.page, 0);
  });

  testWidgets('a second finger does not end the first one\'s take', (
    tester,
  ) async {
    await pumpFab(tester);
    backend.replies.add('ship it');

    final first = await tester.startGesture(tester.getCenter(mic));
    await tester.pump();
    final second = await tester.startGesture(tester.getCenter(mic), pointer: 7);
    await second.up();
    // `pump`, not `pumpAndSettle`: the listening ring never settles, and running
    // the clock out would end the take on its own five-minute limit.
    await tester.pump(const Duration(milliseconds: 100));
    expect(voice.status, VoiceInputStatus.listening);
    expect(frames, isEmpty);

    await first.up();
    await tester.pumpAndSettle();

    expect(sentTurns(), ['ship it']);
  });

  testWidgets('a hold whose mic leaves the screen is cancelled', (
    tester,
  ) async {
    final shown = ValueNotifier(true);
    addTearDown(shown.dispose);
    await pumpFab(
      tester,
      around: ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (context, on, _) =>
            Center(child: on ? fab() : const SizedBox.shrink()),
      ),
    );

    final thumb = await tester.startGesture(tester.getCenter(mic));
    await tester.pump();
    expect(voice.status, VoiceInputStatus.listening);

    // The keyboard coming up, say — the page drops the mic under the thumb.
    shown.value = false;
    await tester.pumpAndSettle();

    expect(recorder.cancels, 1);
    expect(voice.isIdle, isTrue);
    await thumb.up();
    await tester.pumpAndSettle();
    expect(frames, isEmpty);
  });
}
