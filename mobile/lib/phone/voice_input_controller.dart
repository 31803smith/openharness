import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harness_mobile/logging/app_log.dart';

import 'voice_language_store.dart';
import 'voice_notice.dart';
import 'voice_recorder.dart';

/// Turns one WAV recording into the words in it — `ApiClient.transcribeVoice`.
typedef VoiceTranscriber = Future<String> Function(Uint8List wav, String lang);

enum VoiceInputStatus {
  /// Not recording. What was heard so far stays.
  idle,

  /// Waiting on the microphone permission prompt, or the microphone opening.
  starting,

  /// Recording.
  listening,

  /// The recording is with the backend, and its words are not back yet.
  transcribing,

  /// The microphone was refused: the keyboard is the only way in until the
  /// person allows it in Settings.
  unavailable,
}

/// Voice input for one pager of terminal pages: what is being recorded, and what
/// has been heard and not yet sent.
///
/// Record, then transcribe — the dial's shape, and the backend's: its
/// `/api/voice/stt` takes a finished recording and answers with its words, so
/// nothing appears while someone is still talking. Each take's words join the
/// transcript when it ends.
///
/// Owned by `AgentSwipeHost`, not by a page, for the reason the keyboard is one
/// screen-wide fact in `terminal_page.dart`: swiping to the next agent must not
/// drop what was said. What is SENT goes to whichever page's mic is pressed.
class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required this.transcriber,
    VoiceRecorder? recorder,
    ValueListenable<String>? language,
  }) : _recorder = recorder ?? MicVoiceRecorder(),
       _language = language ?? voiceLanguageStore;

  /// Below this, a take is silence rather than quiet speech: digital zero, or
  /// the hiss of an input nobody is speaking into. Speech peaks in the
  /// thousands. Caught here, it is a clear notice instead of an upload that
  /// comes back empty and reads as "didn't catch that".
  static const silencePeak = 64;

  /// The longest one take runs before it ends by itself. The backend takes
  /// 25 MB; five minutes of 16 kHz mono is under 10.
  static const maxTake = Duration(minutes: 5);

  final VoiceTranscriber transcriber;
  final VoiceRecorder _recorder;

  /// A code from `voiceLanguages`, read when a take is transcribed — so a language picked
  /// mid-take is the one that take is heard in.
  final ValueListenable<String> _language;

  VoiceInputStatus _status = VoiceInputStatus.idle;
  String _heard = '';
  String? _notice;
  bool _isSending = false;
  bool _disposed = false;
  Timer? _takeLimit;

  /// Bumped by everything that abandons a take, so a recording or a
  /// transcription still in flight from it lands nowhere — above all after
  /// [clear], where words arriving late would bring back what was dropped.
  int _take = 0;

  bool get isSending => _isSending;
  VoiceInputStatus get status => _status;
  String get transcript => _heard;
  String? get notice => _notice;

  /// Nothing being recorded, heard or sent — the mic at rest. A refused
  /// microphone is at rest too: nothing is in flight.
  bool get isIdle =>
      (_status == VoiceInputStatus.idle ||
          _status == VoiceInputStatus.unavailable) &&
      _heard.isEmpty &&
      !_isSending;

  /// Drops the take in progress, the words held from a send that failed, and
  /// the notice. A send already on its way is not recalled.
  void clear() {
    _abandonTake();
    _heard = '';
    _setStatus(VoiceInputStatus.idle);
  }

  Future<void> startListening() async {
    if (_isSending || _disposed) return;
    if (_status != VoiceInputStatus.idle &&
        _status != VoiceInputStatus.unavailable) {
      return;
    }
    final take = ++_take;
    _setStatus(VoiceInputStatus.starting);
    if (!await _micAllowed()) {
      if (take != _take) return;
      _setStatus(VoiceInputStatus.unavailable, notice: VoiceNotice.unavailable);
      return;
    }
    // Closed, cleared or stopped while the permission prompt was up.
    if (take != _take) return;
    try {
      await _recorder.start();
    } on Exception {
      if (take != _take) return;
      _setStatus(VoiceInputStatus.idle, notice: VoiceNotice.couldNotStart);
      return;
    }
    if (take != _take) {
      unawaited(_recorder.cancel());
      return;
    }
    _takeLimit = Timer(maxTake, () => unawaited(stopListening()));
    _setStatus(VoiceInputStatus.listening);
  }

  /// Ends the take and transcribes it.
  Future<void> stopListening() async {
    if (_status == VoiceInputStatus.starting) {
      _abandonTake();
      _setStatus(VoiceInputStatus.idle);
      return;
    }
    if (_status == VoiceInputStatus.listening) await _transcribeTake();
  }

  /// Sends everything heard, and empties the transcript once it is sent — kept
  /// when delivery fails, so nothing said has to be said twice.
  ///
  /// Send while still talking ends the take first: one tap finishes the
  /// sentence and sends it. A take that comes back as nothing sends nothing,
  /// rather than the half of the message that was heard before it.
  Future<void> submit(Future<bool> Function(String text) deliver) async {
    if (_isSending || _status == VoiceInputStatus.transcribing) return;
    if (_status == VoiceInputStatus.listening && !await _transcribeTake()) {
      return;
    }
    final text = transcript.trim();
    if (text.isEmpty || _isSending) return;
    _isSending = true;
    _setStatus(VoiceInputStatus.idle);
    var sent = false;
    try {
      sent = await deliver(text);
    } on Exception {
      // Reported below exactly like a refusal: the words stay, Send stays live.
    }
    _isSending = false;
    if (sent) _heard = '';
    _setStatus(
      VoiceInputStatus.idle,
      notice: sent ? null : VoiceNotice.notSent,
    );
  }

  /// Everything heard — the take still being recorded included, once it is
  /// transcribed — emptied out of here, for the keyboard to carry on from.
  ///
  /// Nothing while a send is on its way: those words are already the message,
  /// and handing them to the keyboard too would put them in the prompt twice.
  Future<String> takeTranscript() async {
    if (_isSending) return '';
    if (_status == VoiceInputStatus.listening) await _transcribeTake();
    final text = transcript;
    clear();
    return text;
  }

  @override
  void dispose() {
    _abandonTake();
    _disposed = true;
    unawaited(_recorder.dispose());
    super.dispose();
  }

  /// True when the take's words, if any, joined the transcript.
  Future<bool> _transcribeTake() async {
    final take = _take;
    _takeLimit?.cancel();
    _setStatus(VoiceInputStatus.transcribing);
    try {
      final recording = await _recorder.stop();
      if (take != _take) return false;
      appLog.info(
        'voice',
        recording == null
            ? 'take: no audio captured'
            : 'take: ${recording.length.inMilliseconds}ms '
                  '${recording.wav.length}B peak=${recording.peak}',
      );
      if (recording == null || recording.peak < silencePeak) {
        _setStatus(VoiceInputStatus.idle, notice: VoiceNotice.noSound);
        return false;
      }
      final language = _language.value;
      final words = await transcriber(recording.wav, language);
      // The count, never the words: a transcript is what someone said.
      appLog.info('voice', 'stt[$language]: ${words.length} chars');
      if (take != _take) return false;
      _heard = _joinWords(_heard, words);
      _setStatus(
        VoiceInputStatus.idle,
        notice: words.isEmpty ? VoiceNotice.nothingHeard : null,
      );
      return words.isNotEmpty;
    } on Exception catch (error) {
      appLog.warn('voice', 'stt[${_language.value}] failed', error: error);
      if (take == _take) {
        _setStatus(VoiceInputStatus.idle, notice: VoiceNotice.notTranscribed);
      }
      return false;
    }
  }

  Future<bool> _micAllowed() async {
    try {
      return await _recorder.allowed();
    } on Exception {
      return false;
    }
  }

  void _abandonTake() {
    _take++;
    _takeLimit?.cancel();
    if (_status == VoiceInputStatus.starting ||
        _status == VoiceInputStatus.listening) {
      unawaited(_recorder.cancel());
    }
  }

  void _setStatus(VoiceInputStatus status, {String? notice}) {
    _status = status;
    _notice = notice;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

String _joinWords(String first, String second) =>
    [first.trim(), second.trim()].where((part) => part.isNotEmpty).join(' ');
