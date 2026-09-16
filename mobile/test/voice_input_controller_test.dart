import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/phone/voice_notice.dart';

import 'voice_fakes.dart';

void main() {
  late FakeSpeechEngine engine;
  late MemoryKeyValueStore storage;
  late VoiceInputController voice;

  setUp(() {
    engine = FakeSpeechEngine();
    storage = MemoryKeyValueStore();
    voice = VoiceInputController(engine: engine, storage: storage);
  });

  tearDown(() => voice.dispose());

  test(
    'opening is listening: the panel is up and the words arrive live',
    () async {
      await voice.open();

      expect(voice.isOpen, isTrue);
      expect(voice.status, VoiceInputStatus.listening);

      engine.say('fix the');
      expect(voice.transcript, 'fix the');

      engine.finish('fix the failing test');
      expect(voice.transcript, 'fix the failing test');
      expect(voice.status, VoiceInputStatus.idle);
    },
  );

  test('a second listen adds to what the first one heard', () async {
    await voice.open();
    engine.finish('run the tests');

    await voice.toggleListening();
    engine.say('then commit');

    expect(voice.transcript, 'run the tests then commit');
  });

  test('a guess a failed listen never finalised is kept, not lost', () async {
    await voice.open();
    engine.say('rename the');
    engine.fail('error_no_match');

    expect(voice.status, VoiceInputStatus.idle);
    expect(voice.notice, VoiceNotice.forError('error_no_match'));

    await voice.startListening();
    engine.say('module');
    expect(voice.transcript, 'rename the module');
  });

  test('a refused permission says so, and the next open asks again', () async {
    engine.allowed = false;
    await voice.open();

    expect(voice.status, VoiceInputStatus.unavailable);
    expect(voice.notice, VoiceNotice.unavailable);

    engine.allowed = true;
    voice.close();
    await voice.open();
    expect(voice.status, VoiceInputStatus.listening);
    expect(engine.prepares, 2);
  });

  test('closing while the permission prompt is up starts no listen', () async {
    engine.pendingPrepare = Completer<bool>();
    final opening = voice.open();
    expect(voice.status, VoiceInputStatus.starting);

    voice.close();
    engine.pendingPrepare!.complete(true);
    await opening;

    expect(engine.listenedIn, isEmpty);
    expect(voice.status, VoiceInputStatus.idle);
  });

  test('send hands over everything heard and empties the panel', () async {
    await voice.open();
    engine.finish('open a PR');
    await voice.startListening();
    engine.say('for this branch');

    final delivered = <String>[];
    await voice.submit((text) async {
      delivered.add(text);
      return true;
    });

    expect(delivered, ['open a PR for this branch']);
    expect(voice.transcript, isEmpty);
    expect(engine.cancels, 1);

    // The listen it cut short answers late: those words were already sent.
    engine.finish('for this branch');
    expect(voice.transcript, isEmpty);
  });

  test('a send that fails keeps the words for another try', () async {
    await voice.open();
    engine.finish('deploy');

    await voice.submit((_) async => false);

    expect(voice.transcript, 'deploy');
    expect(voice.notice, VoiceNotice.notSent);
    expect(voice.isSending, isFalse);
  });

  test('closing stops the microphone and forgets what was not sent', () async {
    await voice.open();
    engine.say('never mind');

    voice.close();

    expect(voice.isOpen, isFalse);
    expect(voice.transcript, isEmpty);
    expect(engine.cancels, 1);
  });

  test(
    'stopping keeps the listen\'s words: its final result still counts',
    () async {
      await voice.open();
      engine.say('almost');

      await voice.stopListening();
      expect(engine.stops, 1);
      engine.finish('almost done');

      expect(voice.transcript, 'almost done');
    },
  );

  test(
    'a chosen language is used, remembered, and restored next time',
    () async {
      await voice.open();
      expect(voice.localeId, 'en-US');

      await voice.selectLocale('vi-VN');

      expect(storage.values['voice_input_locale'], 'vi-VN');
      expect(engine.listenedIn.last, 'vi-VN');

      final later = VoiceInputController(
        engine: FakeSpeechEngine(),
        storage: storage,
      );
      addTearDown(later.dispose);
      await later.open();
      expect(later.localeId, 'vi-VN');
    },
  );
}
