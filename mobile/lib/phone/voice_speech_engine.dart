import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// One language the recognizer can listen in, as the OS names it.
typedef VoiceLocale = ({String id, String name});

/// The recognizer's languages, and the one it uses when none is named.
typedef VoiceLocales = ({List<VoiceLocale> all, String? systemId});

/// The speech recognizer behind [VoiceInputController], as the four things the
/// phone asks of it.
///
/// A seam rather than `SpeechToText` itself: the plugin is a platform-channel
/// singleton, so a widget test that reached it would hang on a method call no
/// engine answers.
abstract interface class SpeechEngine {
  /// Asks for the microphone and speech permissions the first time it runs.
  /// False when either is refused, or the device has no recognizer at all.
  Future<bool> prepare();

  /// Starts one listen. [onWords] gets the running guess and, last, the final
  /// one; [onStopped] fires once the recognizer has stopped hearing, and
  /// [onError] carries the plugin's `error_*` code. Throws when the listen
  /// cannot start.
  Future<void> listen({
    required String? localeId,
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onStopped,
    required ValueChanged<String> onError,
  });

  /// Ends the listen and lets the final result arrive.
  Future<void> stop();

  /// Ends the listen with no final result.
  Future<void> cancel();

  /// Only meaningful after [prepare] has returned true.
  Future<VoiceLocales> locales();
}

/// [SpeechEngine] over the OS recognizer: Speech on iOS, SpeechRecognizer on
/// Android.
class PlatformSpeechEngine implements SpeechEngine {
  final SpeechToText _speech = SpeechToText();

  /// A silence this long ends the listen. Long enough to think mid-sentence;
  /// Android may still cut it shorter, which the plugin cannot override.
  static const _pauseFor = Duration(seconds: 4);

  /// Both OSes stop a recognition near a minute on their own.
  static const _listenFor = Duration(minutes: 1);

  @override
  Future<bool> prepare() async {
    try {
      return await _speech.initialize(
        options: [SpeechToText.androidNoBluetooth],
      );
    } on Exception {
      return false;
    }
  }

  @override
  Future<void> listen({
    required String? localeId,
    required void Function(String words, bool isFinal) onWords,
    required VoidCallback onStopped,
    required ValueChanged<String> onError,
  }) async {
    // ⚠️ Assigned before EVERY listen, not handed to `initialize`. The plugin
    // is one instance for the whole app and `initialize` returns early once it
    // has worked, so listeners given to it would stay those of the first
    // controller ever made — a pager long since disposed.
    _speech
      ..statusListener = (status) {
        if (status != SpeechToText.listeningStatus) onStopped();
      }
      ..errorListener = (error) => onError(error.errorMsg);
    await _speech.listen(
      onResult: (result) => onWords(result.recognizedWords, result.finalResult),
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        autoPunctuation: true,
        cancelOnError: true,
        localeId: localeId,
        pauseFor: _pauseFor,
        listenFor: _listenFor,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();

  @override
  Future<VoiceLocales> locales() async {
    final all = await _speech.locales();
    final system = await _speech.systemLocale();
    return (
      all: [for (final locale in all) (id: locale.localeId, name: locale.name)],
      systemId: system?.localeId,
    );
  }
}
