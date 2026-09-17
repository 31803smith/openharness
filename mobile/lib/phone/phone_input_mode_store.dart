import 'package:flutter/foundation.dart';

import '../core/harness_file_store.dart';
import '../core/local_key_value_store.dart';

/// What a tap on a terminal brings up.
enum PhoneInputMode {
  /// Voice input with its mic button, and a Keyboard button beside it for typing. The default: on a
  /// phone, talking to an agent is quicker than thumbing a prompt.
  voice('Voice', 'Tap the terminal to talk; Keyboard is one tap away'),

  /// The software keyboard straight away, the way the phone worked before voice input.
  keyboard('Keyboard', 'Tap the terminal to type');

  const PhoneInputMode(this.label, this.detail);

  final String label;
  final String detail;

  static const fallback = voice;
}

/// The chosen [PhoneInputMode], remembered across launches.
///
/// Loaded by `loadPersistedSettings()` before the first frame, like the terminal's other
/// preferences: a terminal that opened voice input on its first tap and the keyboard on its second
/// would look like a bug rather than a late read.
class PhoneInputModeStore extends ValueNotifier<PhoneInputMode> {
  PhoneInputModeStore({LocalKeyValueStore? storage})
    : _storage = storage ?? HarnessFileStore.shared,
      super(PhoneInputMode.fallback);

  static const _key = 'phone_input_mode';

  final LocalKeyValueStore _storage;

  /// An unreadable file, or a mode name this build does not know, lands on the default.
  Future<void> load() async {
    try {
      final saved = await _storage.readMany([_key]);
      value =
          PhoneInputMode.values
              .where((mode) => mode.name == saved[_key])
              .firstOrNull ??
          PhoneInputMode.fallback;
    } catch (_) {
      value = PhoneInputMode.fallback;
    }
  }

  Future<void> set(PhoneInputMode mode) async {
    if (mode == value) return;
    value = mode;
    try {
      await _storage.write(_key, mode.name);
    } catch (_) {
      // Kept in memory for this run.
    }
  }
}

final phoneInputModeStore = PhoneInputModeStore();
