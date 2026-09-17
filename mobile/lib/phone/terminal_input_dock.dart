import 'package:flutter/material.dart';

import 'package:harness_mobile/terminal/terminal_session.dart';

import 'terminal_key_bar.dart';

/// The bottom of a terminal page while the keyboard is up: [TerminalKeyBar] over
/// it, following the session's input state. Nothing while it is down — the foot
/// row with the mic is the page's then.
class TerminalInputDock extends StatelessWidget {
  const TerminalInputDock({
    super.key,
    required this.session,
    required this.keyboardUp,
    required this.onDismiss,
    this.onPickImage,
    this.onTakePhoto,
  });

  final TerminalSession session;

  /// The software keyboard is up, or has been asked for and is on its way.
  final bool keyboardUp;

  /// `⌄` on the key bar: puts the keyboard away.
  final VoidCallback onDismiss;
  final VoidCallback? onPickImage;
  final VoidCallback? onTakePhoto;

  @override
  Widget build(BuildContext context) {
    if (!keyboardUp) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => TerminalKeyBar(
        terminal: session.terminal,
        enabled: session.acceptsInput,
        onDismissKeyboard: onDismiss,
        onPickImage: onPickImage,
        onTakePhoto: onTakePhoto,
      ),
    );
  }
}
