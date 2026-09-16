import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

import 'voice_input_controller.dart';

/// The round button voice input is started and stopped with.
///
/// While listening it breathes — a glow and a ring that swell and fade — so it
/// reads as hearing from across the screen, which is where the eyes are: on the
/// terminal, not on this button.
///
/// ⚠️ The swell is painted, never laid out. The button sits in a fixed square
/// with room for the ring already in it: a panel whose height moved with the
/// animation would resize the terminal above it, and every resize is a
/// SIGWINCH on the far machine.
class VoiceMicButton extends StatefulWidget {
  const VoiceMicButton({
    super.key,
    required this.status,
    required this.onPressed,
  });

  final VoiceInputStatus status;
  final VoidCallback onPressed;

  static const double _extent = 72;
  static const double _core = 56;

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _listening => widget.status == VoiceInputStatus.listening;

  @override
  void initState() {
    super.initState();
    _syncBreath();
  }

  @override
  void didUpdateWidget(VoiceMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncBreath();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  void _syncBreath() {
    if (_listening) {
      _breath.repeat();
      return;
    }
    _breath
      ..stop()
      ..value = 0;
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final status = widget.status;
    final lit =
        status == VoiceInputStatus.listening ||
        status == VoiceInputStatus.starting;
    final off = status == VoiceInputStatus.unavailable;
    return Semantics(
      button: true,
      label: lit ? 'Stop listening' : 'Start listening',
      child: GestureDetector(
        key: const ValueKey('voice-mic'),
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onPressed();
        },
        child: SizedBox.square(
          dimension: VoiceMicButton._extent,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_listening) _Ring(breath: _breath),
              AnimatedContainer(
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
                    color: lit
                        ? Colors.white.withValues(alpha: 0.28)
                        : AppGlass.lift,
                  ),
                  boxShadow: lit
                      ? [
                          BoxShadow(
                            color: AppPalette.accent.withValues(alpha: 0.45),
                            blurRadius: 18,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  off ? LucideIcons.micOff300 : LucideIcons.mic300,
                  size: 24,
                  color: lit
                      ? Colors.white
                      : off
                      ? AppPalette.textFaint
                      : AppPalette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ring that leaves the button while it listens.
class _Ring extends StatelessWidget {
  const _Ring({required this.breath});

  final Animation<double> breath;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: breath,
    builder: (context, _) {
      final t = Curves.easeOut.transform(breath.value);
      return Transform.scale(
        scale: 1 + 0.28 * t,
        child: Container(
          width: VoiceMicButton._core,
          height: VoiceMicButton._core,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppPalette.accent.withValues(alpha: 0.35 * (1 - t)),
          ),
        ),
      );
    },
  );
}
