import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:harness_mobile/terminal/terminal_session.dart';

import 'voice_input_controller.dart';
import 'voice_mic_button.dart';

typedef VoiceMicAction = ({VoiceMicFace face, VoidCallback? onPressed});

/// What the mic shows and does for the voice input's state right now.
///
/// ⚠️ Tapping while the microphone is still OPENING calls it off rather than
/// sending: there is no take yet, and a send of nothing would leave the
/// recording to start behind the person's back.
VoiceMicAction voiceMicAction(
  VoiceInputController voice,
  TerminalSession session,
) {
  void send() => unawaited(voice.submit(session.sendComposerText));
  final canSend = session.acceptsInput;
  if (voice.isSending) return (face: VoiceMicFace.busy, onPressed: null);
  return switch (voice.status) {
    VoiceInputStatus.transcribing => (face: VoiceMicFace.busy, onPressed: null),
    VoiceInputStatus.starting => (
      face: VoiceMicFace.starting,
      onPressed: () => unawaited(voice.stopListening()),
    ),
    VoiceInputStatus.listening => (
      face: VoiceMicFace.listening,
      onPressed: send,
    ),
    _ when voice.transcript.isNotEmpty => (
      face: VoiceMicFace.retry,
      onPressed: canSend ? send : null,
    ),
    VoiceInputStatus.unavailable => (
      face: VoiceMicFace.off,
      onPressed: () => unawaited(voice.startListening()),
    ),
    VoiceInputStatus.idle => (
      face: VoiceMicFace.talk,
      onPressed: canSend ? () => unawaited(voice.startListening()) : null,
    ),
  };
}

/// What the mic is doing, in a word or two — null with it at rest.
String? voiceActivityLabel(VoiceInputController voice) {
  if (voice.isSending) return 'Sending…';
  return switch (voice.status) {
    VoiceInputStatus.starting => 'Starting…',
    VoiceInputStatus.listening => 'Listening…',
    VoiceInputStatus.transcribing => 'Transcribing…',
    VoiceInputStatus.idle || VoiceInputStatus.unavailable => null,
  };
}
