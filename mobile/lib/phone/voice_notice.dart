/// The one line voice input shows when it cannot do what was asked.
///
/// Worded for the person, keyed on the plugin's `error_*` codes — which are
/// not meant for display and differ between iOS and Android.
abstract final class VoiceNotice {
  static const unavailable =
      'Voice input is off. Allow Harness the microphone and speech recognition in Settings, or use the keyboard.';

  static const notSent =
      "Not sent — this terminal isn't taking input right now.";

  static const couldNotStart =
      "Voice input couldn't start. Tap the mic to try again.";

  /// Whether [code] means permission is missing, rather than one listen going
  /// wrong. Trying again will not help; Settings will.
  static bool isPermanent(String code) =>
      code.contains('permission') || code.contains('not_authorized');

  static String forError(String code) {
    if (isPermanent(code)) return unavailable;
    if (code.contains('no_match') || code.contains('speech_timeout')) {
      return "Didn't catch that. Tap the mic to try again.";
    }
    if (code.contains('language') || code.contains('assets_not_installed')) {
      return "This language isn't available for voice input on this phone.";
    }
    if (code.contains('network') || code.contains('server')) {
      return 'Voice input needs a connection. Tap the mic to try again.';
    }
    return 'Voice input stopped. Tap the mic to try again.';
  }
}
