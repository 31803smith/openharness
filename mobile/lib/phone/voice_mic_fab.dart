import 'dart:async';

import 'package:flutter/material.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';

import 'voice_language_store.dart';
import 'voice_input_controller.dart';
import 'voice_mic_action.dart';
import 'voice_mic_button.dart';
import 'voice_mic_mode.dart';

/// The mic, floating over the terminal's bottom right corner.
///
/// ⚠️ **Floating rather than in a row, and that is what the row below it pays
/// for.** The foot bar used to hold this button, which set its height at 56 —
/// and that row's top edge is the terminal's bottom edge, so every point of it
/// was a point taken off the remote shell. Lifting the mic out of the layout let
/// the row shrink to one line of text; the button now costs the terminal nothing
/// but the corner it covers.
///
/// ⚠️ **The corner, deliberately — not centred, and not over the middle.** A
/// terminal's newest output is the line being read, and it runs left to right:
/// the right end of the last few lines is the least of it.
///
/// ⚠️ **The `×` is NOT here.** It lives at the end of the foot row's line, next
/// to the words it dismisses — see `terminal_foot_bar.dart`. Stacked over this
/// button it floated in the middle of the terminal with nothing beside it, a
/// glyph on its own over streaming output that read as a rendering fault.
class VoiceMicFab extends StatefulWidget {
  const VoiceMicFab({
    super.key,
    required this.voice,
    required this.session,
    required this.onSlipChanged,
  });

  final VoiceInputController voice;
  final TerminalSession session;

  /// The thumb crossed in or out of the button mid-hold. The foot bar is what
  /// says "Release to cancel" — this button is under a thumb and cannot.
  final ValueChanged<bool> onSlipChanged;

  /// What the whole floating cluster asks of the corner it sits in.
  ///
  /// Bigger than [VoiceMicButton.extent] because the mic's hit area spills past
  /// its slot: this is what the page keeps clear of anything else tappable.
  static const double extent = VoiceMicButton.touchExtent;

  /// How far the cluster sits from the screen's right edge and from the foot row
  /// under it.
  static const double inset = 8;

  @override
  State<VoiceMicFab> createState() => _VoiceMicFabState();
}

class _VoiceMicFabState extends State<VoiceMicFab> {
  VoiceInputController get voice => widget.voice;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([voice, widget.session]),
      builder: (context, _) => _mic(context),
    );
  }

  Widget _mic(BuildContext context) {
    final action = voiceMicAction(voice, widget.session);
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
      onSlipChanged: widget.onSlipChanged,
    );
  }
}
