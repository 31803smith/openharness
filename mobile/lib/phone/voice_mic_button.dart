import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/pulse.dart';

import 'voice_mic_mode.dart';

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

  /// Recording with the thumb dragged off the button — letting go now throws
  /// the take away. [VoiceMicMode.holdToTalk] only.
  ///
  /// Its own face rather than a flag on [listening] because it is the opposite
  /// promise: the ring stops breathing, the fill goes to the warning colour and
  /// the glyph becomes a `×`. What is about to happen has to be readable at a
  /// glance, by someone whose thumb is covering the button.
  cancelling,
}

/// The one voice control on a terminal page — a small round button floating
/// over the terminal's bottom right corner. [VoiceMicFab] is what places it.
///
/// Two ways to work it, chosen by [voiceMicMode] and nothing else:
///
///  - [VoiceMicMode.tapToToggle] — tap to start, tap again to finish the
///    sentence and send it. The face says which tap is next: a mic, then an
///    arrow. Long-press is the language shortcut.
///  - [VoiceMicMode.holdToTalk] — the recording lasts exactly as long as the
///    thumb is down, and letting go sends. Sliding off the button first throws
///    the take away, and the face turns to a `×` to say so. No long-press:
///    that gesture is what records.
///
/// ⚠️ **The swell is painted, never laid out.** The breathing ring scales past
/// the button's box with [Clip.none] rather than growing it, so nothing around
/// the button moves while it breathes.
class VoiceMicButton extends StatefulWidget {
  const VoiceMicButton({
    super.key,
    required this.face,
    required this.onPressed,
    this.onLongPress,
    this.onHoldStart,
    this.onHoldFinish,
    this.onSlipChanged,
  });

  final VoiceMicFace face;

  /// Null draws the button dimmed and dead.
  ///
  /// In [VoiceMicMode.holdToTalk] this still decides whether the button is live
  /// — a terminal that is not taking input must not record — but it is the hold
  /// callbacks below that do the work.
  final VoidCallback? onPressed;

  /// The language picker — a shortcut to the Settings row, for someone who
  /// talks in two languages. Null in [VoiceMicMode.holdToTalk], whose press and
  /// hold belong to the recording.
  final VoidCallback? onLongPress;

  /// The thumb went down: start recording. [VoiceMicMode.holdToTalk] only.
  final VoidCallback? onHoldStart;

  /// The thumb came up. `cancelled` is true when it was dragged off the button
  /// first, which throws the take away instead of sending it.
  final void Function({required bool cancelled})? onHoldFinish;

  /// The thumb crossed in or out of the button mid-hold, so the row beside it
  /// can say what letting go will now do.
  ///
  /// The button's own face already turns to a `×`, but the thumb is ON the
  /// button and covering most of it — the words to the left are what somebody
  /// can actually read at that moment.
  final ValueChanged<bool>? onSlipChanged;

  /// The space this button asks of its parent's layout.
  ///
  /// ⚠️ **It no longer sets any row's height.** The mic floats over the terminal
  /// now (see `voice_mic_fab.dart`), so this is simply the box the `Positioned`
  /// sizes to — raising it costs the terminal nothing, and the hit area below
  /// already reaches well past it either way.
  static const double extent = 60;

  /// What the finger may actually land on.
  ///
  /// ⚠️ **Deliberately LARGER than [extent], and drawn outside the layout
  /// box.** Hold-to-talk asks for a press held through a whole sentence, so the
  /// target has to forgive a thumb that shifts while somebody talks. An
  /// [OverflowBox] is what allows a child bigger than its parent: the hit area
  /// reaches out over the terminal on every side, which has nothing tappable to
  /// collide with.
  static const double touchExtent = 84;

  /// How far the hit area spills past its slot on each side.
  ///
  /// What anything placed beside or above this button has to clear: the
  /// overhang is painted over its neighbour and would swallow the neighbour's
  /// presses. See the gap above the mic in `voice_mic_fab.dart`.
  static const double touchOverhang = (touchExtent - extent) / 2;

  /// The visible circle.
  static const double _core = 48;

  /// How far past [touchExtent] the thumb may stray and still count as "on" the
  /// button.
  ///
  /// ⚠️ Generous on purpose — a thumb resting on the circle covers most of it,
  /// and the finger's reported point wanders by several points while somebody
  /// talks. Cancelling is meant to be a deliberate move away, not something a
  /// steady hand trips over mid-sentence.
  static const double _slipMargin = 32;

  @override
  State<VoiceMicButton> createState() => _VoiceMicButtonState();
}

class _VoiceMicButtonState extends State<VoiceMicButton> {
  /// Whether the thumb is currently outside the button, with a hold in
  /// progress. Drives the [VoiceMicFace.cancelling] face.
  bool _slippedOff = false;

  bool get _live => widget.onPressed != null;

  /// What to draw: the face given, unless a hold has been dragged off the
  /// button, which only this widget knows about.
  VoiceMicFace get _face => _slippedOff && widget.face == VoiceMicFace.listening
      ? VoiceMicFace.cancelling
      : widget.face;

  bool get _lit => switch (_face) {
    VoiceMicFace.starting ||
    VoiceMicFace.listening ||
    VoiceMicFace.cancelling ||
    VoiceMicFace.retry => true,
    VoiceMicFace.talk || VoiceMicFace.busy || VoiceMicFace.off => false,
  };

  String get _semanticLabel => switch (_face) {
    VoiceMicFace.talk =>
      micHoldsToTalk ? 'Hold to talk to the agent' : 'Talk to the agent',
    VoiceMicFace.starting => 'Cancel',
    VoiceMicFace.listening =>
      micHoldsToTalk ? 'Release to send' : 'Send what was said',
    VoiceMicFace.cancelling => 'Release to cancel',
    VoiceMicFace.busy => 'Working',
    VoiceMicFace.retry => 'Send again',
    VoiceMicFace.off => 'Voice input is off',
  };

  /// Whether [point], in the hit area's own coordinates, still counts as on the
  /// button.
  ///
  /// Measured against [VoiceMicButton.touchExtent] — the box the [Listener]
  /// actually covers — rather than the row slot, because that is the box the
  /// pointer's `localPosition` is reported in.
  bool _within(Offset point) {
    const extent = VoiceMicButton.touchExtent;
    const margin = VoiceMicButton._slipMargin;
    return point.dx >= -margin &&
        point.dy >= -margin &&
        point.dx <= extent + margin &&
        point.dy <= extent + margin;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_live) return;
    _setSlipped(false);
    HapticFeedback.lightImpact();
    widget.onHoldStart?.call();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_live || widget.onHoldFinish == null) return;
    final off = !_within(event.localPosition);
    if (off == _slippedOff) return;
    // Felt as well as seen: the thumb is over the button, so the change of
    // meaning has to reach the hand that cannot see it.
    HapticFeedback.selectionClick();
    _setSlipped(off);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (widget.onHoldFinish == null) return;
    final cancelled = _slippedOff;
    _setSlipped(false);
    widget.onHoldFinish!(cancelled: cancelled);
  }

  /// The gesture was taken over by something else — a scroll that won the
  /// arena, the app going away. Treated as a cancel: a take nobody ended
  /// deliberately must not be sent.
  void _onPointerCancel(PointerCancelEvent event) {
    if (widget.onHoldFinish == null) return;
    _setSlipped(false);
    widget.onHoldFinish!(cancelled: true);
  }

  /// ⚠️ Tells the row BEFORE rebuilding itself. The listener sits in an ancestor
  /// that rebuilds this button, so calling it inside `setState` would report the
  /// change from the middle of a build.
  void _setSlipped(bool value) {
    if (value == _slippedOff) return;
    _slippedOff = value;
    widget.onSlipChanged?.call(value);
    if (mounted) setState(() {});
  }

  /// ⚠️ **The buzz that says "the microphone is open — talk now", and
  /// hold-to-talk does not work without it.** Opening the microphone is real
  /// hardware time, and a thumb that has just pressed a button is a thumb whose
  /// owner has already started the sentence: those first words land before
  /// anything is recording, and what reaches the backend is half a sentence that
  /// transcribes to nothing. The row asks them to wait; this is what releases
  /// them, felt rather than read, because their thumb is over the button and
  /// their eyes are not necessarily on the screen.
  ///
  /// Only on the way IN to listening, and only while holding — the tap mode's
  /// own press already told them the take had begun.
  @override
  void didUpdateWidget(VoiceMicButton old) {
    super.didUpdateWidget(old);
    if (!micHoldsToTalk) return;
    if (old.face != VoiceMicFace.listening &&
        widget.face == VoiceMicFace.listening) {
      HapticFeedback.mediumImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Semantics(
      button: true,
      enabled: _live,
      label: _semanticLabel,
      onLongPressHint: widget.onLongPress == null ? null : 'Choose language',
      // ⚠️ **The slot is [VoiceMicButton.extent]; the hit area inside it is the
      // larger [VoiceMicButton.touchExtent], spilling out on every side.** The
      // [OverflowBox] is what allows a child bigger than its parent without the
      // parent growing — so the row, and the terminal above it, keep their
      // heights while the finger gets a target half again as wide.
      //
      // `Clip.none` on the stack matters for the same reason: the ring already
      // paints past the core, and clipping to the slot would cut both it and
      // the overflowing hit area back to nothing.
      child: SizedBox.square(
        dimension: VoiceMicButton.extent,
        child: OverflowBox(
          maxWidth: VoiceMicButton.touchExtent,
          maxHeight: VoiceMicButton.touchExtent,
          child: _gestures(
            child: SizedBox.square(
              dimension: VoiceMicButton.touchExtent,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                opacity: _live ? 1 : 0.4,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    // ⚠️ Not while cancelling: the ring means "listening, carry
                    // on talking", and leaving it breathing under a `×` would
                    // say both things at once.
                    if (_face == VoiceMicFace.listening) const _Ring(),
                    _Core(face: _face, lit: _lit),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ⚠️ **A [Listener], not a [GestureDetector], and the difference is what
  /// makes hold-to-talk work at all.** A gesture detector's long-press only
  /// fires after the press delay, and reports a drag off the button as the
  /// press being cancelled — so recording would start a beat late and end the
  /// moment the thumb wandered. Raw pointer events start the take on the frame
  /// the finger lands and keep reporting while it moves, which is what lets the
  /// button tell "still talking" from "slid off to cancel".
  ///
  /// The tap mode keeps its [GestureDetector]: there is nothing to track
  /// between the two taps, and it comes with the tap-cancel semantics that mode
  /// wants.
  Widget _gestures({required Widget child}) {
    if (!micHoldsToTalk) {
      return GestureDetector(
        key: const ValueKey('voice-mic'),
        behavior: HitTestBehavior.opaque,
        onTap: _live
            ? () {
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        onLongPress: widget.onLongPress,
        child: child,
      );
    }
    return Listener(
      key: const ValueKey('voice-mic'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: child,
    );
  }
}

class _Core extends StatelessWidget {
  const _Core({required this.face, required this.lit});

  final VoiceMicFace face;
  final bool lit;

  /// The fill's hue. Cancelling takes the warning colour: the button is about
  /// to throw away what was just said, and that is not something the accent —
  /// which everywhere else in the app means "go" — should be saying.
  Color get _tint =>
      face == VoiceMicFace.cancelling ? AppPalette.warn : AppPalette.accent;

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
              colors: [Color.lerp(_tint, Colors.white, 0.18)!, _tint],
            )
          : null,
      color: lit ? null : AppGlass.surfaceFill,
      border: Border.all(
        color: lit ? Colors.white.withValues(alpha: 0.28) : AppGlass.lift,
      ),
      boxShadow: lit
          ? [BoxShadow(color: _tint.withValues(alpha: 0.4), blurRadius: 12)]
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
        dimension: 21,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppPalette.accent,
        ),
      );
    }
    return Icon(
      switch (face) {
        // ⚠️ In hold-to-talk the arrow would be a lie: nothing is sent by
        // pressing this, it is sent by letting go. The mic stays up for the
        // whole take and the thumb never leaves it, so there is no second press
        // for an arrow to describe.
        VoiceMicFace.listening =>
          micHoldsToTalk ? LucideIcons.mic300 : LucideIcons.arrowUp300,
        VoiceMicFace.retry => LucideIcons.arrowUp300,
        VoiceMicFace.cancelling => LucideIcons.x300,
        VoiceMicFace.off => LucideIcons.micOff300,
        VoiceMicFace.talk ||
        VoiceMicFace.starting ||
        VoiceMicFace.busy => LucideIcons.mic300,
      },
      size: 25,
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
