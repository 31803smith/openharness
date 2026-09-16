import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harness_mobile/core/harness_file_store.dart';
import 'package:harness_mobile/core/local_key_value_store.dart';

import 'voice_notice.dart';
import 'voice_speech_engine.dart';

enum VoiceInputStatus {
  /// Not hearing anything. What was heard so far stays.
  idle,

  /// Waiting on a permission prompt, or on the recognizer to begin.
  starting,
  listening,

  /// Permission refused, or no recognizer on this phone: the keyboard is the
  /// only way in until that changes.
  unavailable,
}

/// Voice input for one pager of terminal pages: whether its panel is open, what
/// has been heard, and the language it listens in.
///
/// Owned by `AgentSwipeHost`, not by a page, for the reason the keyboard is one
/// screen-wide fact in `terminal_page.dart`: swiping to the next agent must not
/// close what is open, nor drop what was said. What is SENT goes to whichever
/// page is active when Send is pressed.
class VoiceInputController extends ChangeNotifier {
  VoiceInputController({SpeechEngine? engine, LocalKeyValueStore? storage})
    : _engine = engine ?? PlatformSpeechEngine(),
      _storage = storage ?? HarnessFileStore.shared;

  static const _localeKey = 'voice_input_locale';

  final SpeechEngine _engine;
  final LocalKeyValueStore _storage;

  final ValueNotifier<bool> _open = ValueNotifier(false);
  bool _isSending = false;
  bool _prepared = false;
  bool _disposed = false;
  VoiceInputStatus _status = VoiceInputStatus.idle;
  String? _notice;
  VoiceLocales _locales = (all: const [], systemId: null);
  String? _chosenLocaleId;

  /// Words from finished listens, and the running guess of the current one.
  String _heard = '';
  String _hearing = '';

  /// Bumped by everything that abandons a listen, so a result or error still
  /// in flight from it lands nowhere — above all after Send, where a late final
  /// result would put the words just sent back in the panel.
  int _listen = 0;

  /// Whether the panel is up, as its own listenable: the terminal page watches
  /// THIS, not the controller, so words arriving several times a second repaint
  /// the panel and never rebuild the terminal above it.
  ValueListenable<bool> get openState => _open;
  bool get isOpen => _open.value;
  bool get isSending => _isSending;
  VoiceInputStatus get status => _status;
  bool get isListening =>
      _status == VoiceInputStatus.starting ||
      _status == VoiceInputStatus.listening;
  String get transcript => _joinWords(_heard, _hearing);
  String? get notice => _notice;

  /// Empty until the first listen has been allowed.
  List<VoiceLocale> get locales => _locales.all;
  String? get localeId => _chosenLocaleId ?? _locales.systemId;

  /// Opens the panel already listening — what a tap on the terminal does.
  Future<void> open() {
    _open.value = true;
    return startListening();
  }

  /// Closes the panel, discarding anything not sent.
  void close() {
    _open.value = false;
    clear();
  }

  void clear() {
    _abandonListen();
    _heard = '';
    _hearing = '';
    _setStatus(VoiceInputStatus.idle);
  }

  Future<void> toggleListening() =>
      isListening ? stopListening() : startListening();

  Future<void> startListening() async {
    if (isListening || _isSending || _disposed) return;
    _keepHearing();
    final listen = ++_listen;
    _setStatus(VoiceInputStatus.starting);
    if (!await _prepare()) {
      if (listen != _listen) return;
      _setStatus(VoiceInputStatus.unavailable, notice: VoiceNotice.unavailable);
      return;
    }
    // Closed, cleared or stopped while the permission prompt was up.
    if (listen != _listen) return;
    try {
      await _engine.listen(
        localeId: _chosenLocaleId,
        onWords: (words, isFinal) => _onWords(listen, words, isFinal),
        onStopped: () => _onStopped(listen),
        onError: (code) => _onError(listen, code),
      );
    } on Exception {
      if (listen != _listen) return;
      _setStatus(VoiceInputStatus.idle, notice: VoiceNotice.couldNotStart);
      return;
    }
    if (listen == _listen && _status == VoiceInputStatus.starting) {
      _setStatus(VoiceInputStatus.listening);
    }
  }

  /// Ends the listen but keeps its words: the final result is still to come.
  Future<void> stopListening() async {
    if (_status == VoiceInputStatus.starting) {
      _abandonListen();
    } else if (_status == VoiceInputStatus.listening) {
      unawaited(_engine.stop());
    }
    _setStatus(VoiceInputStatus.idle);
  }

  /// Hands the transcript to [deliver], and empties the panel once it is sent.
  /// Kept when delivery fails, so nothing said has to be said twice.
  Future<void> submit(Future<bool> Function(String text) deliver) async {
    final text = transcript.trim();
    if (text.isEmpty || _isSending) return;
    _abandonListen();
    _keepHearing();
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

  /// Listens in [id] from now on, on this phone and in later pagers too. A
  /// listen already running restarts in it; the words it heard stay.
  Future<void> selectLocale(String id) async {
    final wasListening = isListening;
    _abandonListen();
    _chosenLocaleId = id;
    _setStatus(VoiceInputStatus.idle);
    if (wasListening) unawaited(startListening());
    try {
      await _storage.write(_localeKey, id);
    } on Exception {
      // Still used for this pager; only remembering it failed.
    }
  }

  @override
  void dispose() {
    _abandonListen();
    _disposed = true;
    _open.dispose();
    super.dispose();
  }

  Future<bool> _prepare() async {
    if (_prepared) return true;
    if (!await _engine.prepare()) return false;
    _prepared = true;
    try {
      _locales = await _engine.locales();
      final saved = await _storage.read(_localeKey);
      if (_locales.all.any((locale) => locale.id == saved)) {
        _chosenLocaleId = saved;
      }
    } on Exception {
      // The system language still works; only the picker goes missing.
    }
    return true;
  }

  void _onWords(int listen, String words, bool isFinal) {
    if (listen != _listen) return;
    if (isFinal) {
      _heard = _joinWords(_heard, words);
      _hearing = '';
    } else {
      _hearing = words;
    }
    _notify();
  }

  void _onStopped(int listen) {
    if (listen != _listen || !isListening) return;
    _setStatus(VoiceInputStatus.idle);
  }

  void _onError(int listen, String code) {
    if (listen != _listen) return;
    _setStatus(
      VoiceNotice.isPermanent(code)
          ? VoiceInputStatus.unavailable
          : VoiceInputStatus.idle,
      notice: VoiceNotice.forError(code),
    );
  }

  /// Folds an unfinished guess into the transcript. A listen that ended with
  /// no final result — an error, a cancel — would otherwise lose it to the
  /// next listen's first guess.
  void _keepHearing() {
    _heard = transcript;
    _hearing = '';
  }

  void _abandonListen() {
    _listen++;
    if (isListening) unawaited(_engine.cancel());
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
