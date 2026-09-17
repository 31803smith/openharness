import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/pulse.dart';

/// What the mic says it will do when tapped.
enum VoiceMicFace {
  /// At rest: tap to talk.
  talk,

  /// The microphone is opening: tap to call it off.
  starting,

  /// Recording: tap to send what was said. It breathes while it listens.
  listening,

  /// Transcribing or sending: nothing to tap until that is back.
  busy,

  /// A send failed and its words are held: tap to send them again.
  retry,

  /// The microphone was refused: tap to ask again.
  off,
}

/// The one voice control on a terminal page — a small round button at the foot
/// of the page, beside the machine it is talking to.
///
/// Talk and send are the same tap, walkie-talkie style: tap to start, tap again
/// to finish the sentence and send it. The face changes to say which tap is
/// next — a mic, then an arrow.
///
/// ⚠️ **The swell is painted, never laid out.** The breathing ring scales past
/// the button's box with [Clip.none] rather than growing it: this button's row
/// sits under the terminal, and a row whose height moved with the animation
/// would resize the remote shell every frame.
class VoiceMicButton extends StatelessWidget {
  const VoiceMicButton({
    super.key,
    required this.face,
    required this.onPressed,
    this.onLongPress,
  });

  final VoiceMicFace face;

  /// Null draws the button dimmed and dead.
  final VoidCallback? onPressed;

  /// The language picker — a shortcut to the Settings row, for someone who
  /// talks in two languages.
  final VoidCallback? onLongPress;

  /// The tap target: iOS's 44pt minimum, around a smaller mark.
  static const double extent = 44;
  static const double _core = 32;

  bool get _lit => switch (face) {
    VoiceMicFace.starting ||
    VoiceMicFace.listening ||
    VoiceMicFace.retry => true,
    VoiceMicFace.talk || VoiceMicFace.busy || VoiceMicFace.off => false,
  };

  String get _semanticLabel => switch (face) {
    VoiceMicFace.talk => 'Talk to the agent',
    VoiceMicFace.starting => 'Cancel',
    VoiceMicFace.listening => 'Send what was said',
    VoiceMicFace.busy => 'Working',
    VoiceMicFace.retry => 'Send again',
    VoiceMicFace.off => 'Voice input is off',
  };

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final live = onPressed != null;
    return Semantics(
      button: true,
      enabled: live,
      label: _semanticLabel,
      onLongPressHint: onLongPress == null ? null : 'Choose language',
      child: GestureDetector(
        key: const ValueKey('voice-mic'),
        behavior: HitTestBehavior.opaque,
        onTap: live
            ? () {
                HapticFeedback.lightImpact();
                onPressed!();
              }
            : null,
        onLongPress: onLongPress,
        child: SizedBox.square(
          dimension: extent,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: live ? 1 : 0.4,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                if (face == VoiceMicFace.listening) const _Ring(),
                _Core(face: face, lit: _lit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Core extends StatelessWidget {
  const _Core({required this.face, required this.lit});

  final VoiceMicFace face;
  final bool lit;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
    width: VoiceMicButton._core,
    height: VoiceMicButton._core,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: lit
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(AppPalette.accent, Colors.white, 0.18)!,
                AppPalette.accent,
              ],
            )
          : null,
      color: lit ? null : AppGlass.surfaceFill,
      border: Border.all(
        color: lit ? Colors.white.withValues(alpha: 0.28) : AppGlass.lift,
      ),
      boxShadow: lit
          ? [
              BoxShadow(
                color: AppPalette.accent.withValues(alpha: 0.4),
                blurRadius: 12,
              ),
            ]
          : null,
    ),
    child: Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        child: _Glyph(key: ValueKey(face), face: face, lit: lit),
      ),
    ),
  );
}

class _Glyph extends StatelessWidget {
  const _Glyph({super.key, required this.face, required this.lit});

  final VoiceMicFace face;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    if (face == VoiceMicFace.busy) {
      return SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: AppPalette.accent,
        ),
      );
    }
    return Icon(
      switch (face) {
        VoiceMicFace.listening || VoiceMicFace.retry => LucideIcons.arrowUp300,
        VoiceMicFace.off => LucideIcons.micOff300,
        VoiceMicFace.talk ||
        VoiceMicFace.starting ||
        VoiceMicFace.busy => LucideIcons.mic300,
      },
      size: 16,
      color: lit
          ? Colors.white
          : face == VoiceMicFace.off
          ? AppPalette.textFaint
          : AppPalette.textPrimary,
    );
  }
}

/// The glow that swells out of the button while it listens, on the app's one
/// [Pulse] — which is also what holds it still under Reduce Motion.
class _Ring extends StatelessWidget {
  const _Ring();

  @override
  Widget build(BuildContext context) => Pulse(
    duration: const Duration(milliseconds: 900),
    curve: Curves.easeOut,
    builder: (context, t, _) => Transform.scale(
      scale: 1 + 0.45 * t,
      child: Container(
        width: VoiceMicButton._core,
        height: VoiceMicButton._core,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppPalette.accent.withValues(alpha: 0.35 * (1 - t)),
        ),
      ),
    ),
  );
}
