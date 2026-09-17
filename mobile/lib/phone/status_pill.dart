import 'package:flutter/material.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

import 'phone_status.dart';

/// The palette colour a [PhoneTone] draws in.
Color phoneToneColor(PhoneTone tone) => switch (tone) {
  PhoneTone.good => AppPalette.online,
  PhoneTone.busy => AppPalette.accent,
  PhoneTone.attention => AppPalette.warn,
  PhoneTone.bad => AppPalette.offline,
  PhoneTone.quiet => AppPalette.textFaint,
};

/// A status line: a dot — a small spinner while something is under way — and its label.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.summary, this.fontSize = 13});

  final PhoneSummary summary;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final color = phoneToneColor(summary.tone);
    final quiet = summary.tone == PhoneTone.quiet;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(summary: summary),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            summary.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: quiet ? AppPalette.textSecondary : color,
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// The status without its words: a dot in the tone's colour, or a small spinner while something is
/// under way. For a place with no room for a label — the terminal header, beside the agent's name.
///
/// The label is still there for a screen reader, and as a long-press tooltip, so a colour is never
/// the only way to learn what it means.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.summary, this.ring});

  final PhoneSummary summary;

  /// A cut-out ring in this colour around the dot, for a dot laid OVER something — a badge on a
  /// mark, the way presence sits on an avatar. It should be the colour behind the mark, so the dot
  /// reads as notched into it rather than stuck on top.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final color = phoneToneColor(summary.tone);
    final ring = this.ring;
    Widget dot = SizedBox.square(
      dimension: 10,
      child: summary.tone == PhoneTone.busy
          ? CircularProgressIndicator(strokeWidth: 1.6, color: color)
          : Center(
              child: DecoratedBox(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 8),
              ),
            ),
    );
    if (ring != null) {
      dot = DecoratedBox(
        decoration: BoxDecoration(color: ring, shape: BoxShape.circle),
        child: Padding(padding: const EdgeInsets.all(2), child: dot),
      );
    }
    return Tooltip(
      message: summary.label,
      child: Semantics(label: summary.label, child: dot),
    );
  }
}
