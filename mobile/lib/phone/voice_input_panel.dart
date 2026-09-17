import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

import 'voice_input_controller.dart';
import 'voice_language.dart';
import 'voice_mic_button.dart';
import 'voice_panel_parts.dart';

/// What a tap on the terminal opens: talk to the agent, read back what was
/// heard, send it — or hand over to the keyboard.
///
/// Words arrive when a take ENDS, not while it is being spoken: they come from
/// the backend's `/api/voice/stt`, which transcribes a finished recording. Send
/// works mid-take for that reason — it ends the take and sends what it heard.
///
/// Opening it records nothing: the mic button starts a take.
///
/// It sits where the keyboard would, alone: [TerminalKeyBar] belongs to the
/// keyboard, so this panel carries its own `⌄`.
///
/// ⚠️ **One fixed height, whatever it says.** The transcript scrolls inside a
/// box of its own rather than growing the panel: this panel's top edge is the
/// terminal's bottom edge, so a panel that grew by a line per sentence would
/// resize the remote shell once per sentence.
class VoiceInputPanel extends StatelessWidget {
  const VoiceInputPanel({
    super.key,
    required this.voice,
    required this.canSend,
    required this.onSend,
    required this.onUseKeyboard,
    required this.onDismiss,
  });

  final VoiceInputController voice;

  /// False while the stream is not accepting input. Recording still works —
  /// what was said waits for Send.
  final bool canSend;
  final VoidCallback onSend;

  /// Closes this panel for the keyboard, carrying what was heard with it.
  final VoidCallback onUseKeyboard;

  /// Puts the panel away, and what was not sent with it.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final status = voice.status;
        return ExcludeFocus(
          // Same reason as the key bar's: nothing here may take focus from the
          // terminal the keyboard button is about to hand it to.
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppPalette.panelBg,
              border: Border(top: BorderSide(color: AppGlass.hair)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: MediaQuery.withNoTextScaling(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusRow(voice: voice, onDismiss: onDismiss),
                    _Transcript(voice: voice),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        VoicePanelAction(
                          key: const ValueKey('voice-keyboard'),
                          icon: LucideIcons.keyboard300,
                          label: 'Keyboard',
                          onTap: onUseKeyboard,
                        ),
                        const Spacer(),
                        VoiceMicButton(
                          status: status,
                          onPressed: voice.toggleListening,
                        ),
                        const Spacer(),
                        VoicePanelAction(
                          key: const ValueKey('voice-send'),
                          icon: LucideIcons.arrowUp300,
                          label: 'Send',
                          emphasized: true,
                          // Live with nothing said too: Send is then Enter
                          // for what is already in the prompt — see
                          // `TerminalInputDock`. Dead only while a take is
                          // opening or its words are still on the way.
                          onTap:
                              canSend &&
                                  !voice.isSending &&
                                  status != VoiceInputStatus.starting &&
                                  status != VoiceInputStatus.transcribing
                              ? onSend
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Language, what the recognizer is doing, the way to start over and the way
/// out.
class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.voice, required this.onDismiss});

  final VoiceInputController voice;
  final VoidCallback onDismiss;

  String get _label => switch (voice.status) {
    VoiceInputStatus.starting => 'Starting…',
    VoiceInputStatus.listening => 'Listening…',
    VoiceInputStatus.transcribing => 'Transcribing…',
    VoiceInputStatus.unavailable => 'Voice input is off',
    VoiceInputStatus.idle when voice.isSending => 'Sending…',
    VoiceInputStatus.idle => 'Tap the mic to talk',
  };

  @override
  Widget build(BuildContext context) {
    // With words on screen the transcript box has no room for a notice, so a
    // failed Send says so here instead.
    final notice = voice.transcript.isNotEmpty ? voice.notice : null;
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          VoiceLanguageChip(
            label: voice.language.toUpperCase(),
            onTap: () => showVoiceLanguagePicker(
              context,
              current: voice.language,
              onSelected: voice.selectLanguage,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notice ?? _label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: notice != null
                    ? AppPalette.warn
                    : AppPalette.textSecondary,
              ),
            ),
          ),
          if (voice.transcript.isNotEmpty)
            VoicePanelIconButton(
              key: const ValueKey('voice-clear'),
              icon: LucideIcons.x300,
              semanticLabel: 'Clear',
              onTap: voice.clear,
            ),
          VoicePanelIconButton(
            key: const ValueKey('voice-hide'),
            icon: LucideIcons.chevronDown300,
            semanticLabel: 'Hide voice input',
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}

/// What was heard, newest words kept in view; the notice when there are none.
class _Transcript extends StatelessWidget {
  const _Transcript({required this.voice});

  final VoiceInputController voice;

  static const double _height = 58;

  @override
  Widget build(BuildContext context) {
    final words = voice.transcript;
    final notice = voice.notice;
    final showsWords = words.isNotEmpty;
    return SizedBox(
      height: _height,
      width: double.infinity,
      child: SingleChildScrollView(
        // Reversed so the latest words are the ones on screen as they arrive.
        reverse: true,
        child: Text(
          showsWords ? words : notice ?? '',
          style: TextStyle(
            fontSize: showsWords ? 16 : 13,
            height: 1.35,
            color: showsWords ? AppPalette.textPrimary : AppPalette.warn,
          ),
        ),
      ),
    );
  }
}
