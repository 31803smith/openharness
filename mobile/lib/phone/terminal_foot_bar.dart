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
class TerminalFootBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final session = this.session;
    // Nothing to say — the machine has not loaded, the header is carrying the
    // state, and there is no pane to talk to. Draw no row rather than an empty
    // one holding its height open under the terminal.
    if (name.isEmpty && status == null && session == null) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
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
                  child: _voiceLine(voice) ?? _machineLine(),
                ),
              ),
              if (session != null) ...[
                if ((!voice.isIdle && !voice.isSending) || voice.notice != null)
                  _DismissButton(onTap: voice.clear),
                _mic(context, session),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _machineLine() =>
      _MachineLine(key: const ValueKey('machine'), name: name, status: status);

  VoiceMicButton _mic(BuildContext context, TerminalSession session) {
    final action = voiceMicAction(voice, session);
    return VoiceMicButton(
      face: action.face,
      onPressed: action.onPressed,
      onLongPress: () => unawaited(showVoiceLanguagePicker(context)),
    );
  }
}

/// What the row's left half says instead of the machine while voice is in use —
/// a notice first, since it is the one thing here that asks to be read. Null
/// with the mic at rest.
Widget? _voiceLine(VoiceInputController voice) {
  final notice = voice.notice;
  final label = notice ?? voiceActivityLabel(voice);
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
      color: notice != null ? AppPalette.warn : AppPalette.accent,
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
      child: SizedBox.square(
        dimension: VoiceMicButton.extent,
        child: Icon(
          LucideIcons.x300,
          size: 16,
          color: AppPalette.textSecondary,
        ),
      ),
    ),
  );
}
