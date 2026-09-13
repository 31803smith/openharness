import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/terminal/terminal_session.dart';

class _Peer {
  final sent = <({String type, Map<String, dynamic> payload})>[];
  final binary = <TerminalBinaryFrame>[];
  Completer<bool>? oldInput;
  Completer<bool>? oldUpload;
  late final session = TerminalSession(
    machineId: 'fixture',
    agentId: 'agent',
    agentName: 'Fixture',
    engineId: 'codex',
    send: (type, payload) {
      sent.add((type: type, payload: Map.of(payload)));
      if (type == 'terminal_chunked_upload_begin' && oldUpload != null) {
        final pending = oldUpload!;
        oldUpload = null;
        return pending.future;
      }
      return Future.value(true);
    },
    sendBinary: (frame) {
      binary.add(frame);
      if (frame.kind == TerminalBinaryKind.input && oldInput != null) {
        final pending = oldInput!;
        oldInput = null;
        return pending.future;
      }
      return Future.value(true);
    },
  );

  Future<void> ready(String stream) async {
    await session.handleFrame('terminal_ready', {
      'requestId': sent
          .lastWhere((f) => f.type == 'terminal_open')
          .payload['requestId'],
      'protocolVersion': 3,
      'agentId': 'agent',
      'streamId': stream,
    });
    await session.handleBinary(
      TerminalBinaryFrame(
        kind: TerminalBinaryKind.keyframe,
        streamId: stream,
        seq: 0,
        bytes: utf8.encode('Screen $stream'),
        compressed: false,
        cols: 80,
        rows: 24,
      ),
    );
  }
}

void main() {
  test('late output and input failure cannot repaint or freeze a replacement stream', () async {
    final peer = _Peer();
    final session = peer.session;
    addTearDown(session.dispose);
    await session.open();
    await peer.ready('old');
    final oldSend = Completer<bool>();
    peer.oldInput = oldSend;
    session.terminal.textInput('old input');
    await Future<void>.delayed(Duration.zero);
    expect(peer.binary, hasLength(1));
    final oldOutput = session.handleBinary(
      TerminalBinaryFrame(
        kind: TerminalBinaryKind.output,
        streamId: 'old',
        seq: 1,
        bytes: utf8.encode('stale repaint'),
        compressed: false,
      ),
    );
    session.transportLost();
    await session.reopen();
    await oldOutput;
    expect(session.terminal.buffer.getText(), isNot(contains('stale repaint')));
    await peer.ready('new');
    session.terminal.textInput('new input');
    await Future<void>.delayed(Duration.zero);
    expect(
      peer.binary,
      hasLength(2),
      reason: 'New input is not queued behind the old transport',
    );
    expect(peer.binary.last.streamId, 'new');
    expect(peer.binary.last.seq, 0);
    expect(utf8.decode(peer.binary.last.bytes), 'new input');
    oldSend.complete(false);
    await Future<void>.delayed(Duration.zero);
    expect(session.status, TerminalSessionStatus.controlling);
    expect(session.terminal.buffer.getText(), contains('Screen new'));
    expect(
      peer.binary,
      hasLength(2),
      reason: 'Old keystrokes are never replayed',
    );
  });

  test(
    'a late upload failure cannot cancel a new upload after reconnect',
    () async {
      final peer = _Peer();
      final session = peer.session;
      addTearDown(session.dispose);
      await session.open();
      await peer.ready('old');
      final oldBegin = Completer<bool>();
      peer.oldUpload = oldBegin;
      final oldUpload = session.pasteImage(Uint8List.fromList([1, 2]));
      session.transportLost();
      await session.reopen();
      await peer.ready('new');
      final newUpload = session.pasteImage(Uint8List.fromList([3, 4]));
      await Future<void>.delayed(Duration.zero);
      oldBegin.complete(false);
      expect(await oldUpload, isFalse);
      expect(session.uploadProgress, isNotNull);
      await session.handleFrame('terminal_chunked_upload_begin_result', {
        'streamId': 'new',
        'accepted': true,
      });
      await Future<void>.delayed(Duration.zero);
      expect(peer.binary.single.streamId, 'new');
      expect(peer.binary.single.bytes, [3, 4]);
      await session.handleFrame('terminal_paste_image_result', {
        'streamId': 'new',
      });
      expect(await newUpload, isTrue);
      expect(session.uploadProgress, isNull);
      expect(session.status, TerminalSessionStatus.controlling);
    },
  );

  test(
    'closing a pane during viewport measurement never sends a delayed open',
    () async {
      final peer = _Peer();
      final session = peer.session;
      addTearDown(session.dispose);
      final opening = session.open(waitForViewportSize: true);
      await session.close();
      session.reportViewport(100, 30);
      await opening;
      expect(peer.sent.where((f) => f.type == 'terminal_open'), isEmpty);
      expect(session.status, TerminalSessionStatus.closed);
    },
  );
}
