import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/voice_locale_picker.dart';

void main() {
  test('the chip names the language, whichever separator the OS uses', () {
    expect(voiceLocaleLabel('vi-VN'), 'VI');
    expect(voiceLocaleLabel('en_US'), 'EN');
    expect(voiceLocaleLabel(null), isEmpty);
  });

  test("the phone's own languages come first, in its order", () {
    const all = [
      (id: 'de-DE', name: 'Deutsch'),
      (id: 'en-GB', name: 'English (UK)'),
      (id: 'en-US', name: 'English (US)'),
      (id: 'fr-FR', name: 'Français'),
      (id: 'vi-VN', name: 'Tiếng Việt'),
    ];

    final ordered = orderVoiceLocales(all, const [
      Locale('vi', 'VN'),
      Locale('en', 'US'),
    ]);

    expect(
      [for (final locale in ordered) locale.id],
      ['vi-VN', 'en-GB', 'en-US', 'de-DE', 'fr-FR'],
    );
  });
}
