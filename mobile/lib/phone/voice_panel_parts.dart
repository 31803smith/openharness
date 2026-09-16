import 'package:flutter/material.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

/// The language voice input listens in, as a two-letter chip.
class VoiceLocaleChip extends StatelessWidget {
  const VoiceLocaleChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Voice input language, $label',
    child: GestureDetector(
      key: const ValueKey('voice-locale'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppGlass.surfaceFill,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppGlass.lift),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppPalette.textPrimary,
          ),
        ),
      ),
    ),
  );
}

/// A pill beside the mic. Null [onTap] draws it dimmed and dead.
class VoicePanelAction extends StatelessWidget {
  const VoicePanelAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final live = onTap != null;
    final filled = emphasized && live;
    final foreground = filled
        ? Colors.white
        : live
        ? AppPalette.textPrimary
        : AppPalette.textFaint;
    return Semantics(
      button: true,
      enabled: live,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: filled ? AppPalette.accent : AppGlass.surfaceFill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: filled
                  ? Colors.white.withValues(alpha: 0.2)
                  : AppGlass.lift,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A bare icon in the panel's status row: Clear, and `⌄`.
class VoicePanelIconButton extends StatelessWidget {
  const VoicePanelIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Icon(icon, size: 18, color: AppPalette.textSecondary),
      ),
    ),
  );
}
