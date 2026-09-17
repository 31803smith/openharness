import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';

import 'phone_status.dart';
import 'status_pill.dart';
import 'voice_input_controller.dart';
import 'voice_language_store.dart';
import 'voice_mic_action.dart';
import 'voice_mic_button.dart';
import 'voice_mic_mode.dart';

/// The foot of a terminal page, one row: which computer the agent runs on,
/// whether it is still answering, and the mic.
///
/// Voice is this one button and nothing else — no panel. Tap to talk, tap again
/// to send; the row's left half says what the mic is doing while it is doing it,
/// and goes back to the machine when it is done. A tap on the terminal instead
/// raises the keyboard with what was said typed into the prompt, which is how a
/// sentence is corrected before it goes.
///
/// ⚠️ **One fixed height, whatever it says.** This row's top edge is the
/// terminal's bottom edge: a row that grew for a two-line notice, or that lost
/// its mic while a pane attached, would resize the remote shell under it.
class TerminalFootBar extends StatefulWidget {
  const TerminalFootBar({
    super.key,
    required this.name,
    required this.status,
    required this.voice,
    required this.session,
  });

  final String name;

  /// Null while the header's reclaim button is saying the state instead — see
  /// the call site. The row then carries the machine alone, at the same height.
  final PhoneSummary? status;

  final VoiceInputController voice;

  /// Null while the pane is still attaching: there is nothing to talk to yet,
  /// and the mic is not drawn.
  final TerminalSession? session;

  static const double height = VoiceMicButton.extent + 4;

  @override
  State<TerminalFootBar> createState() => _TerminalFootBarState();
}

class _TerminalFootBarState extends State<TerminalFootBar> {
  /// Whether a hold in progress has been dragged off the mic, so letting go
  /// would cancel. Held here rather than read from the controller because it is
  /// a fact about the FINGER, which no amount of voice state can answer.
  ///
  /// [VoiceMicMode.tapToToggle] leaves it false forever — that mode has no hold
  /// to slide out of.
  bool _slippedOff = false;

  String get name => widget.name;
  PhoneSummary? get status => widget.status;
  VoiceInputController get voice => widget.voice;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final session = widget.session;
    // Nothing to say — the machine has not loaded, the header is carrying the
    // state, and there is no pane to talk to. Draw no row rather than an empty
    // one holding its height open under the terminal.
    if (name.isEmpty && status == null && session == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: TerminalFootBar.height,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: ListenableBuilder(
          listenable: Listenable.merge([voice, session]),
          builder: (context, _) => Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  layoutBuilder: _alignStart,
                  child: _voiceLine(voice, _slippedOff) ?? _machineLine(),
                ),
              ),
              if (session != null) ...[
                if (_showsDismiss) ...[
                  _DismissButton(onTap: voice.clear),
                  // ⚠️ **Clearance, not styling.** The mic's hit area overflows
                  // its slot by [VoiceMicButton.touchOverhang] on each side, and
                  // it is painted after this button — so without a gap at least
                  // that wide its overhang lies on top of the `×`, and a press
                  // aimed at Cancel starts a recording instead.
                  const SizedBox(width: VoiceMicButton.touchOverhang),
                ],
                _mic(context, session),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the `×` beside the mic is drawn.
  ///
  /// ⚠️ **Never while a take is being recorded in hold-to-talk, and that is a
  /// layout bug rather than a preference.** This `×` appears to the LEFT of the
  /// mic, so drawing it shifts the mic sideways — and in hold mode the thumb is
  /// pressed on the mic at exactly that moment. The button would slide out from
  /// under the finger mid-sentence, the finger would land outside its new
  /// bounds, and the take would read as "slid off to cancel" and be thrown away
  /// on release.
  ///
  /// It is not needed there either: releasing off the button is the cancel, and
  /// the recording cannot outlast the thumb. What remains is what the gesture
  /// cannot reach — words held from a failed send, and notices — which is also
  /// the only state hold mode leaves standing after the finger is up.
  bool get _showsDismiss {
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

  Widget _machineLine() =>
      _MachineLine(key: const ValueKey('machine'), name: name, status: status);

  VoiceMicButton _mic(BuildContext context, TerminalSession session) {
    final action = voiceMicAction(voice, session);
    return VoiceMicButton(
      face: action.face,
      onPressed: action.onPressed,
      // ⚠️ No language shortcut in hold-to-talk: press-and-hold is what records
      // there, and a picker opening out of a held mic would fire in the middle
      // of every sentence. Settings ▸ Voice language is the way to it.
      onLongPress: micHoldsToTalk
          ? null
          : () => unawaited(showVoiceLanguagePicker(context)),
      onHoldStart: action.onHoldStart,
      onHoldFinish: action.onHoldFinish,
      onSlipChanged: (off) {
        if (!mounted || off == _slippedOff) return;
        setState(() => _slippedOff = off);
      },
    );
  }
}

/// What the row's left half says instead of the machine while voice is in use —
/// a notice first, since it is the one thing here that asks to be read. Null
/// with the mic at rest.
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
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 12,
      height: 1.3,
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

/// The machine and its state, as one sentence — *on that machine, live*.
///
/// ⚠️ The name is what yields when the row is narrow. A truncated state word
/// is the bug this layout was moved out of the header to avoid — "Taken over"
/// ellipsed to "Ta…" there — so [StatusPill] keeps its intrinsic width and the
/// [Flexible] is on the name alone. A machine called "Macbook Pro của Phát"
/// loses its tail; "Disconnected" never does.
class _MachineLine extends StatelessWidget {
  const _MachineLine({super.key, required this.name, required this.status});

  final String name;
  final PhoneSummary? status;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    return Row(
      children: [
        if (name.isNotEmpty)
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (name.isNotEmpty && status != null)
          // A separator the eye passes over rather than reads: the two halves
          // are one sentence, and a heavier mark between them made the row
          // look like two controls.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              '·',
              style: TextStyle(color: AppPalette.textFaint, fontSize: 12),
            ),
          ),
        if (status != null) StatusPill(fontSize: 12, summary: status),
      ],
    );
  }
}

/// `×` beside the mic while there is something to drop: a take being recorded,
/// words held from a failed send, or a notice. Gone again at rest.
class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Cancel',
    child: GestureDetector(
      key: const ValueKey('voice-cancel'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // ⚠️ **44, not [VoiceMicButton.extent], and the two parted company when
      // the mic grew.** The mic's hit area now spills well past its own slot to
      // give a held thumb room; this sits immediately to its left, so a target
      // that grew alongside it would put the two in the same place and a press
      // meant for the mic would land on Cancel. 44 is iOS's minimum and as much
      // as this button needs — it is tapped deliberately, never held.
      child: SizedBox.square(
        dimension: 44,
        child: Icon(
          LucideIcons.x300,
          size: 17,
          color: AppPalette.textSecondary,
        ),
      ),
    ),
  );
}
