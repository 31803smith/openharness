import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/voice_input_controller.dart';
import 'package:harness_mobile/phone/voice_notice.dart';

import 'voice_fakes.dart';

void main() {
  late FakeVoiceRecorder recorder;
  late FakeTranscriber backend;
  late MemoryKeyValueStore storage;
  late VoiceInputController voice;

  VoiceInputController controller({List<Locale> locales = const []}) =>
      VoiceInputController(
        transcriber: backend.call,
        recorder: recorder,
        storage: storage,
        preferredLocales: locales,
      );

  setUp(() {
    recorder = FakeVoiceRecorder();
    backend = FakeTranscriber();
    storage = MemoryKeyValueStore();
    voice = controller();
  });

  tearDown(() => voice.dispose());

  test('opening is recording: the panel is up and the mic is on', () async {
    await voice.open();

    expect(voice.isOpen, isTrue);
    expect(voice.status, VoiceInputStatus.listening);
    expect(recorder.recording, isTrue);
  });

  test('stopping sends the take to the backend and keeps its words', () async {
    backend.replies.add('fix the failing test');
    await voice.open();

    await voice.stopListening();

    expect(backend.calls.single.lang, 'en');
    expect(voice.transcript, 'fix the failing test');
    expect(voice.status, VoiceInputStatus.idle);
  });

  test(
    'the words wait for the backend: nothing shows mid-transcription',
    () async {
      backend.pending = Completer<String>();
      await voice.open();

      final stopping = voice.stopListening();
      await Future<void>.delayed(Duration.zero);
      expect(voice.status, VoiceInputStatus.transcribing);
      expect(voice.transcript, isEmpty);

      backend.pending!.complete('run the tests');
      await stopping;
      expect(voice.transcript, 'run the tests');
    },
  );

  test('a second take adds to what the first one heard', () async {
    backend.replies.addAll(['run the tests', 'then commit']);
    await voice.open();
    await voice.toggleListening();

    await voice.toggleListening();
    await voice.toggleListening();

    expect(voice.transcript, 'run the tests then commit');
  });

  test('a refused microphone says so, and the next open asks again', () async {
    recorder.permitted = false;
    await voice.open();

    expect(voice.status, VoiceInputStatus.unavailable);
    expect(voice.notice, VoiceNotice.unavailable);

    recorder.permitted = true;
    voice.close();
    await voice.open();
    expect(voice.status, VoiceInputStatus.listening);
  });

  test('closing while the permission prompt is up records nothing', () async {
    recorder.pendingPermission = Completer<bool>();
    final opening = voice.open();
    expect(voice.status, VoiceInputStatus.starting);

    voice.close();
    recorder.pendingPermission!.complete(true);
    await opening;

    expect(recorder.starts, 0);
    expect(voice.status, VoiceInputStatus.idle);
  });

  test('a failed transcription says so and adds nothing', () async {
    backend.fails = true;
    await voice.open();

    await voice.stopListening();

    expect(voice.transcript, isEmpty);
    expect(voice.notice, VoiceNotice.notTranscribed);
  });

  test('an empty transcript comes back as a notice, not a message', () async {
    await voice.open();

    await voice.stopListening();

    expect(voice.transcript, isEmpty);
    expect(voice.notice, VoiceNotice.nothingHeard);
  });

  test('a silent microphone is said so, and nothing is uploaded', () async {
    recorder.captured = (
      wav: Uint8List(44),
      length: const Duration(seconds: 3),
      peak: 0,
    );
    await voice.open();

    await voice.stopListening();

    expect(backend.calls, isEmpty);
    expect(voice.notice, VoiceNotice.noSound);
  });

  test('a take with no audio at all is said so too', () async {
    recorder.captured = null;
    await voice.open();

    await voice.stopListening();

    expect(backend.calls, isEmpty);
    expect(voice.notice, VoiceNotice.noSound);
  });

  test('send hands over everything heard and empties the panel', () async {
    backend.replies.add('open a PR');
    await voice.open();
    await voice.stopListening();

    final delivered = <String>[];
    await voice.submit((text) async {
      delivered.add(text);
      return true;
    });

    expect(delivered, ['open a PR']);
    expect(voice.transcript, isEmpty);
  });

  test('send mid-sentence ends the take and sends it with the rest', () async {
    backend.replies.addAll(['open a PR', 'for this branch']);
    await voice.open();
    await voice.stopListening();
    await voice.startListening();

    final delivered = <String>[];
    await voice.submit((text) async {
      delivered.add(text);
      return true;
    });

    expect(recorder.stops, 2);
    expect(delivered, ['open a PR for this branch']);
  });

  test('a take that fails mid-send sends none of the message', () async {
    backend.replies.add('delete the');
    await voice.open();
    await voice.stopListening();
    await voice.startListening();
    backend.fails = true;

    var delivered = false;
    await voice.submit((_) async => delivered = true);

    expect(delivered, isFalse);
    expect(voice.transcript, 'delete the');
    expect(voice.notice, VoiceNotice.notTranscribed);
  });

  test('a send that fails keeps the words for another try', () async {
    backend.replies.add('deploy');
    await voice.open();
    await voice.stopListening();

    await voice.submit((_) async => false);

    expect(voice.transcript, 'deploy');
    expect(voice.notice, VoiceNotice.notSent);
    expect(voice.isSending, isFalse);
  });

  test('closing mid-transcription drops the words when they arrive', () async {
    backend.pending = Completer<String>();
    await voice.open();
    final stopping = voice.stopListening();
    await Future<void>.delayed(Duration.zero);

    voice.close();
    backend.pending!.complete('never mind');
    await stopping;

    expect(voice.isOpen, isFalse);
    expect(voice.transcript, isEmpty);
  });

  test('closing while recording throws the recording away', () async {
    await voice.open();

    voice.close();

    expect(recorder.cancels, 1);
    expect(backend.calls, isEmpty);
  });

  test(
    'handing over to the keyboard transcribes the take in progress',
    () async {
      backend.replies.addAll(['rename the', 'module']);
      await voice.open();
      await voice.stopListening();
      await voice.startListening();

      expect(await voice.takeTranscript(), 'rename the module');
      expect(voice.transcript, isEmpty);
    },
  );

  test("the phone's language is the default, when the backend serves it", () {
    final vietnamese = controller(locales: const [Locale('vi', 'VN')]);
    final german = controller(locales: const [Locale('de'), Locale('fr')]);
    addTearDown(vietnamese.dispose);
    addTearDown(german.dispose);

    expect(vietnamese.language, 'vi');
    expect(german.language, 'fr');
  });

  test(
    'a chosen language is used, remembered, and restored next time',
    () async {
      await voice.selectLanguage('vi');
      backend.replies.add('xin chào');
      await voice.open();
      await voice.stopListening();

      expect(backend.calls.single.lang, 'vi');
      expect(storage.values['voice_input_language'], 'vi');

      final later = controller();
      addTearDown(later.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(later.language, 'vi');
    },
  );

  test('a language the backend does not serve is refused', () async {
    await voice.selectLanguage('de');

    expect(voice.language, 'en');
  });
}
