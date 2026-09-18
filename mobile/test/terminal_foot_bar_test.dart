import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/phone_status.dart';
import 'package:harness_mobile/phone/terminal_foot_bar.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/phone/voice_mic_action.dart';
import 'package:harness_mobile/phone/voice_notice.dart';

import 'voice_fakes.dart';

/// The row under the terminal: who the agent is while nothing is being said,
/// and what the mic is doing while something is. The mic itself floats over the
/// terminal (`voice_mic_fab_test.dart`); this row carries the words it has
/// nowhere to put.
void main() {
  late FakeVoiceRecorder recorder;
  late FakeTranscriber backend;
  late ValueNotifier<String> language;
  late VoiceInputController voice;

  const live = (label: 'Live', tone: PhoneTone.good);
  final dismiss = find.byKey(const ValueKey('voice-cancel'));

  setUp(() {
    recorder = FakeVoiceRecorder();
    backend = FakeTranscriber();
    language = ValueNotifier('en');
    voice = VoiceInputController(
      transcriber: backend.call,
      recorder: recorder,
      language: language,
    );
  });

  tearDown(() {
    voice.dispose();
    language.dispose();
  });

  Future<void> pumpBar(WidgetTester tester, {bool slippedOff = false}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TerminalFootBar(
                name: 'MacBookPro2021.local',
                status: live,
                voice: voice,
                agent: null,
                slippedOff: slippedOff,
              ),
            ),
          ),
        ),
      );

  testWidgets('at rest it names the machine and its state', (tester) async {
    await pumpBar(tester);

    expect(find.text('MacBookPro2021.local'), findsOneWidget);
    expect(find.text('Live'), findsOneWidget);
    expect(dismiss, findsNothing);
  });

  testWidgets('while recording it says what the mic is doing', (tester) async {
    await pumpBar(tester);

    await voice.startListening();
    await tester.pumpAndSettle();

    expect(find.text(voiceActivityLabel(voice)!), findsOneWidget);
    expect(find.text('MacBookPro2021.local'), findsNothing);
    voice.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('a hold dragged off the mic says letting go cancels', (
    tester,
  ) async {
    await pumpBar(tester, slippedOff: true);
    await tester.pumpAndSettle();

    expect(find.text('Release to cancel'), findsOneWidget);
  });

  testWidgets('a failed send says so, and × puts the row back', (tester) async {
    await pumpBar(tester);
    backend.replies.add('deploy');
    await voice.startListening();
    await voice.stopListening();
    await voice.submit((_) async => false);
    await tester.pumpAndSettle();

    expect(find.text(VoiceNotice.notSent), findsOneWidget);

    // On the glyph: the target only answers inside the row's own 24×18 slot —
    // hit testing stops at a parent's bounds, whatever the OverflowBox draws.
    await tester.tap(find.descendant(of: dismiss, matching: find.byType(Icon)));
    await tester.pumpAndSettle();

    expect(voice.transcript, isEmpty);
    expect(find.text('MacBookPro2021.local'), findsOneWidget);
  });

  testWidgets('the height holds still whatever the row says', (tester) async {
    await pumpBar(tester);
    final atRest = tester.getSize(find.byType(TerminalFootBar));

    await voice.startListening();
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(TerminalFootBar)), atRest);
    voice.clear();
    await tester.pumpAndSettle();
  });
}
