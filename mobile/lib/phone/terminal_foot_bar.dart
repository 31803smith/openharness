import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';

import 'phone_status.dart';
import 'status_pill.dart';
import 'voice_input_controller.dart';
import 'voice_mic_action.dart';
import 'voice_mic_mode.dart';

/// The foot of a terminal page, one short row: which agent this is, on which
/// computer, and what the mic is doing while it is doing it.
///
/// ⚠️ **The mic is no longer in here.** It floats over the terminal's bottom
/// right corner instead — see `voice_mic_fab.dart` — which is what let this row
/// shrink to a line of text. What stayed is the line the mic needs somebody to
/// read: "Listening… release to send", "Didn't catch that". A floating button
/// has nowhere to put words.
///
/// ⚠️ **One fixed height, whatever it says.** This row's top edge is the
/// terminal's bottom edge: a row that grew for a two-line notice would resize
/// the remote shell under it.
class TerminalFootBar extends StatelessWidget {
  const TerminalFootBar({
    super.key,
    required this.name,
    required this.status,
    required this.voice,
    required this.agent,
    this.slippedOff = false,
  });

  /// The machine's name. Empty leaves it out.
  final String name;

  /// Null while the header's reclaim button is saying the state instead — the
  /// row then carries the identity alone, at the same height.
  final PhoneSummary? status;

  final VoiceInputController voice;

  /// The agent this terminal belongs to — its engine mark and its name are the
  /// identity this row leads with. Null while it is still loading.
  final Agent? agent;

  /// Whether a hold in progress has been dragged off the mic, so letting go
  /// would cancel. A fact about the FINGER, which only the button knows; it is
  /// passed down so this row can say what the release will now do.
  final bool slippedOff;

  /// ⚠️ Short on purpose, and the whole reason the mic left. Every point here
  /// is a point taken off the terminal above, which is then resized.
  ///
  /// ⚠️ **18 is what one line of 10.5pt text fits in, and nothing more.** The
  /// type, the engine mark and the status dot were all cut to match — a child
  /// that kept its old size would overflow rather than shrink the row, because
  /// the height is fixed above everything in it.
  ///
  /// The sums, for whoever comes to change one of these: the system face lays
  /// 10.5pt out in a line box of about 12.5, the engine mark is the tallest
  /// thing in the row at 11, and that leaves roughly 3pt of air above and below.
  /// It is tight on purpose — this row's top edge is the terminal's bottom edge
  /// — but it is tight enough that the text scale below is no longer optional.
  static const double height = 18;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return SizedBox(
      height: height,
      // ⚠️ **Text scaling is pinned here, and this row is one of the few places
      // in the app where that is right.** Its height is fixed — the terminal's
      // bottom edge sits on it — so type that grew with the system setting would
      // overflow rather than reflow, and there is no second line for it to take.
      // The words here are chrome that names the agent; the terminal above,
      // which is what somebody is actually reading, honours the setting as it
      // always did.
      child: MediaQuery.withNoTextScaling(
        child: Padding(
          // The mic floats over the terminal ABOVE this row rather than over the
          // row itself, so the right inset is only the screen's own margin — but
          // it stays generous, because the mic's hit area reaches down to within
          // a few points of this line and text running right up to it would look
          // like part of the button.
          padding: const EdgeInsets.only(left: 16, right: 16),
          child: ListenableBuilder(
            listenable: voice,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    layoutBuilder: _alignStart,
                    child:
                        _voiceLine(voice, slippedOff) ??
                        _IdentityLine(
                          key: const ValueKey('identity'),
                          name: name,
                          status: status,
                          agent: agent,
                        ),
                  ),
                ),
                // ⚠️ **At the END OF THE LINE it dismisses, not over the mic.**
                // Stacked above the floating button it sat in the middle of the
                // terminal with nothing beside it — a lone glyph over streaming
                // output, which reads as a rendering fault rather than as a
                // control. Here it is plainly the way to get rid of the words to
                // its left.
                //
                // The mic cannot be shifted by it either, which is what put it
                // over there in the first place: the mic floats and this is in
                // the layout, so they no longer share a row.
                if (_showsDismiss(voice)) _DismissButton(onTap: voice.clear),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the row says instead of the agent while voice is in use — a notice
/// first, since it is the one thing here that asks to be read. Null with the mic
/// at rest.
Widget? _voiceLine(VoiceInputController voice, bool slippedOff) {
  final notice = voice.notice;
  // ⚠️ The slip outranks the notice and the activity alike. A thumb held off
  // the button is one release away from throwing the take away, and that is the
  // only thing on this row worth the space at that moment.
  final label = slippedOff
      ? 'Release to cancel'
      : notice ?? voiceActivityLabel(voice);
  if (label == null) return null;
  return Text(
    label,
    key: ValueKey(label),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 10.5,
      height: 1.2,
      fontWeight: FontWeight.w500,
      // The warning colour for both things that are about to go wrong or go
      // away, matching the mic's own fill while it is under a slipped thumb.
      color: (slippedOff || notice != null)
          ? AppPalette.warn
          : AppPalette.accent,
    ),
  );
}

Widget _alignStart(Widget? current, List<Widget> previous) =>
    Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]);

/// Whether the `×` at the end of the row is drawn.
///
/// ⚠️ **Never while a take is being recorded in hold-to-talk.** It is not needed
/// there — releasing off the button is the cancel, and the recording cannot
/// outlast the thumb. What remains is what the gesture cannot reach: words held
/// from a failed send, and notices, which are also the only state hold mode
/// leaves standing after the finger is up.
bool _showsDismiss(VoiceInputController voice) {
  if (voice.notice != null) return true;
  if (voice.isSending) return false;
  if (micHoldsToTalk) {
    return switch (voice.status) {
      VoiceInputStatus.starting ||
      VoiceInputStatus.listening ||
      VoiceInputStatus.transcribing => false,
      VoiceInputStatus.idle ||
      VoiceInputStatus.unavailable => voice.transcript.isNotEmpty,
    };
  }
  return !voice.isIdle;
}

/// `×` at the end of the row while there is something to drop: words held from
/// a failed send, or a notice. Gone again at rest.
///
/// ⚠️ **The glyph is tiny and the target is not.** The row is 20pt tall and this
/// has to read as punctuation at the end of a sentence rather than as a button
/// competing with the mic — but 20pt of glass is not something a thumb can hit.
/// An [OverflowBox] gives it a 40pt target while the row keeps its height.
///
/// ⚠️ **The target grows DOWNWARD, never up, and that is the one thing here
/// that must not change.** The mic floats above this row at the same right-hand
/// end, its own hit area spills below its box, and it is painted after this — so
/// a target reaching up meets the mic's coming down, the mic wins, and a tap
/// meant to dismiss a notice starts a recording. Everything below this row is
/// the home indicator's margin, which has nothing to collide with.
class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onTap});

  final VoidCallback onTap;

  /// What the finger may land on, against the 18pt the row gives it.
  static const double _touch = 40;

  /// How wide the glyph's own slot is.
  ///
  /// ⚠️ **Wider than the row is tall, on purpose.** The row's height came down
  /// to 18 for the type, but the `×` is round and 18pt of width crowds it hard
  /// against the words to its left. Width costs the terminal nothing — only the
  /// height is shared with it.
  static const double _slot = 24;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Semantics(
      button: true,
      label: 'Cancel',
      child: SizedBox(
        width: _slot,
        height: TerminalFootBar.height,
        child: OverflowBox(
          maxWidth: _touch,
          maxHeight: _touch,
          // Pinned to the row's TOP edge, so the box that overflows hangs off
          // the bottom rather than straddling both sides. See the note above.
          alignment: Alignment.topCenter,
          child: GestureDetector(
            key: const ValueKey('voice-cancel'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: _touch,
              // ⚠️ **Aligned to the ROW's middle, not the target's.** The hit
              // box is 40pt pinned to an 18pt row's top edge, so its own centre
              // sits 11pt BELOW the line of text — a `Center` here drew the
              // glyph hanging off the bottom of the bar, clear of the words it
              // belongs to. The fraction puts it back on the text's centreline
              // while the target it lives in still reaches down past the row.
              child: Align(
                alignment: Alignment(0, -1 + (TerminalFootBar.height / _touch)),
                child: Icon(
                  LucideIcons.x300,
                  size: 12,
                  color: AppPalette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Who this terminal belongs to, as one line — *engine mark, agent, machine,
/// state*.
///
/// ⚠️ **The agent's name is what yields when the row is narrow, and the state
/// word never does.** A truncated "Ta…" for "Taken over" is the bug this layout
/// exists to avoid, so [StatusPill] keeps its intrinsic width and the
/// [Flexible]s are on the two names. The agent's name gets the larger share: it
/// is the thing that says WHICH terminal this is.
class _IdentityLine extends StatelessWidget {
  const _IdentityLine({
    super.key,
    required this.name,
    required this.status,
    required this.agent,
  });

  final String name;
  final PhoneSummary? status;
  final Agent? agent;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final agent = this.agent;
    return Row(
      children: [
        if (agent != null) ...[
          // ⚠️ The TALLEST thing in the row, so it is what sets the floor under
          // [TerminalFootBar.height] — not the text. Small enough to read as a
          // mark beside the name rather than as an avatar.
          EngineMark(
            engine: agent.engine,
            displayName: agent.engineDisplayName,
            size: 11,
          ),
          const SizedBox(width: 5),
          Flexible(
            flex: 3,
            child: Text(
              agent.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppPalette.textPrimary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (agent != null && name.isNotEmpty) _dot(),
        if (name.isNotEmpty)
          Flexible(
            flex: 2,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if ((agent != null || name.isNotEmpty) && status != null) _dot(),
        if (status != null)
          // The dot and its gap come down with the type: at the row's default
          // 10pt the dot was wider than the cap height beside it and read as a
          // bullet rather than as a state.
          StatusPill(fontSize: 10.5, dotSize: 8, gap: 5, summary: status),
      ],
    );
  }

  /// A separator the eye passes over rather than reads: the halves are one
  /// sentence, and a heavier mark between them made the row look like controls.
  Widget _dot() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Text(
      '·',
      // Down with everything else in the row: left at 12 it was the tallest
      // piece of type here and set the line box on its own.
      style: TextStyle(color: AppPalette.textFaint, fontSize: 10.5),
    ),
  );
}
