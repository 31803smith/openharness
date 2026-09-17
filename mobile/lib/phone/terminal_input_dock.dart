import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import 'package:harness_mobile/terminal/terminal_session.dart';

import 'terminal_key_bar.dart';
import 'voice_input_controller.dart';
import 'voice_input_panel.dart';

/// The bottom of a terminal page: [TerminalKeyBar] over the keyboard, or
/// [VoiceInputPanel] in its place.
///
/// Voice is what a tap on the terminal opens; the keyboard is what its
/// Keyboard button hands over to. One at a time, and the key bar goes with the
/// keyboard: `esc`, the arrows and the digits are keys to TYPE with, and while
/// someone is talking they are two rows of terminal the panel does not need.
class TerminalInputDock extends StatelessWidget {
  const TerminalInputDock({
    super.key,
    required this.session,
    required this.voice,
    required this.keyboardUp,
    required this.onDismiss,
    required this.onUseKeyboard,
    this.onPickImage,
    this.onTakePhoto,
  });

  final TerminalSession session;
  final VoiceInputController voice;

  /// The software keyboard is up, or has been asked for and is on its way.
  final bool keyboardUp;

  /// `⌄`, on the key bar or on the panel: puts away whichever input is up.
  final VoidCallback onDismiss;
  final VoidCallback onUseKeyboard;
  final VoidCallback? onPickImage;
  final VoidCallback? onTakePhoto;

  /// Send: what was said, or — with nothing said — what is already in the
  /// prompt.
  ///
  /// Speech goes the composer's own path, not as typed bytes: the machine
  /// injects it as one turn and owns the submit Enter — see
  /// `TerminalSession.sendComposerText`.
  ///
  /// ⚠️ With no speech, Send is Enter. The prompt can hold text this panel
  /// never saw — typed, pasted, or dictated by the keyboard's own mic before
  /// switching back — and a Send that stayed dead over it left no way to send
  /// that text short of raising the keyboard again for its return key.
  void _send() {
    if (voice.hasSpeech) {
      unawaited(voice.submit(session.sendComposerText));
      return;
    }
    session.terminal.keyInput(TerminalKey.enter);
    voice.clear();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: voice.openState,
    builder: (context, voiceOpen, _) {
      if (!keyboardUp && !voiceOpen) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: session,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (keyboardUp)
              TerminalKeyBar(
                terminal: session.terminal,
                enabled: session.acceptsInput,
                controlArmed: session.controlArmed,
                onControlToggle: session.armControl,
                onDismissKeyboard: onDismiss,
                onPickImage: onPickImage,
                onTakePhoto: onTakePhoto,
              )
            else
              VoiceInputPanel(
                voice: voice,
                canSend: session.acceptsInput,
                onSend: _send,
                onUseKeyboard: onUseKeyboard,
                onDismiss: onDismiss,
              ),
          ],
        ),
      );
    },
  );
}
