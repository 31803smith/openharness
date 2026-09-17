import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'phone_sheet.dart';

typedef VoiceLanguage = ({String code, String name});

/// The languages `/api/voice/stt` transcribes, each named in itself.
///
/// ⚠️ A twin of `VOICE_WAV_LANGS` in the backend's `lib/deepgramWav.ts`. A code
/// the backend does not serve is not refused there — it is silently transcribed
/// as English — so a language added on one side belongs on the other.
const voiceLanguages = <VoiceLanguage>[
  (code: 'en', name: 'English'),
  (code: 'vi', name: 'Tiếng Việt'),
  (code: 'es', name: 'Español'),
  (code: 'fr', name: 'Français'),
  (code: 'ja', name: '日本語'),
  (code: 'it', name: 'Italiano'),
];

bool isVoiceLanguage(String? code) =>
    voiceLanguages.any((language) => language.code == code);

/// The first of the phone's own languages the backend serves, or English.
String defaultVoiceLanguage(List<Locale> preferred) {
  for (final locale in preferred) {
    if (isVoiceLanguage(locale.languageCode)) return locale.languageCode;
  }
  return 'en';
}

/// Picks the language voice input is transcribed in.
Future<void> showVoiceLanguagePicker(
  BuildContext context, {
  required String current,
  required ValueChanged<String> onSelected,
}) => showPhoneSheet(
  context,
  title: 'Voice input language',
  actions: [
    for (final language in voiceLanguages)
      PhoneSheetAction(
        icon: language.code == current
            ? LucideIcons.check300
            : LucideIcons.languages300,
        label: language.name,
        onTap: () => onSelected(language.code),
      ),
  ],
);
