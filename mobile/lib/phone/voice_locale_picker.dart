import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'phone_sheet.dart';
import 'voice_input_controller.dart';
import 'voice_speech_engine.dart';

/// The chip's short name for a recognizer locale: `vi-VN` and `vi_VN` are both
/// `VI`.
String voiceLocaleLabel(String? id) {
  if (id == null || id.isEmpty) return '';
  return id.split(RegExp('[-_]')).first.toUpperCase();
}

/// The recognizer's locales with the phone's own languages first.
///
/// A recognizer offers sixty-odd, alphabetically; the two a person actually
/// talks in — the ones in the phone's language settings — would otherwise sit
/// somewhere in the middle. The rest keep the recognizer's order.
List<VoiceLocale> orderVoiceLocales(
  List<VoiceLocale> all,
  List<Locale> preferred,
) {
  final languages = [for (final locale in preferred) locale.languageCode];
  int rank(VoiceLocale locale) {
    final index = languages.indexOf(voiceLocaleLabel(locale.id).toLowerCase());
    return index < 0 ? languages.length : index;
  }

  final indexed = all.indexed.toList()
    ..sort((a, b) {
      final byLanguage = rank(a.$2).compareTo(rank(b.$2));
      return byLanguage != 0 ? byLanguage : a.$1.compareTo(b.$1);
    });
  return [for (final (_, locale) in indexed) locale];
}

/// Picks the language voice input listens in.
Future<void> showVoiceLocalePicker(
  BuildContext context,
  VoiceInputController voice,
) {
  final current = voice.localeId;
  final locales = orderVoiceLocales(
    voice.locales,
    PlatformDispatcher.instance.locales,
  );
  return showPhoneSheet(
    context,
    title: 'Voice input language',
    actions: [
      for (final locale in locales)
        PhoneSheetAction(
          icon: locale.id == current
              ? LucideIcons.check300
              : LucideIcons.languages300,
          label: locale.name,
          onTap: () => unawaited(voice.selectLocale(locale.id)),
        ),
    ],
  );
}
