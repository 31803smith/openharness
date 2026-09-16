import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:harness_mobile/core/local_key_value_store.dart';
import 'package:harness_mobile/phone/voice_speech_engine.dart';

/// A recognizer the test speaks for: [say] and [finish] stand in for a person
/// talking, [fail] for the OS giving up.
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine({this.allowed = true});

  bool allowed;
  VoiceLocales available = (
    all: const [
      (id: 'en-US', name: 'English'),
      (id: 'vi-VN', name: 'Tiếng Việt'),
    ],
    systemId: 'en-US',
  );

  /// Held open to keep a listen in `starting`, like a permission prompt does.
  Completer<bool>? pendingPrepare;

  int prepares = 0;
  int stops = 0;
  int cancels = 0;
  final List<String?> listenedIn = [];

  void Function(String words, bool isFinal)? _onWords;
  VoidCallback? _onStopped;
  ValueChanged<String>? _onError;

  @override
  Future<bool> prepare() {
    prepares++;
    return pendingPrepare?.future ?? Future.value(allowed);
  }

  @override
  Future<void> listen({
    required String? localeId,
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onStopped,
    required ValueChanged<String> onError,
  }) async {
    listenedIn.add(localeId);
    _onWords = onWords;
    _onStopped = onStopped;
    _onError = onError;
  }

  void say(String words) => _onWords?.call(words, false);

  void finish(String words) {
    _onWords?.call(words, true);
    _onStopped?.call();
  }

  void fail(String code) => _onError?.call(code);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<VoiceLocales> locales() async => available;
}

class MemoryKeyValueStore implements LocalKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
