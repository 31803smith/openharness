import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:harness/widgets/terminal_composer.dart';
import 'package:harness/widgets/terminal_find_bar.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount;
import 'swarm_state_test.dart' show createApp;
import 'terminal_find_test.dart' show findField, finishFind, terminalView;

class _Connection extends WsConn {
  _Connection()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'm',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );
  final sent = <({String type, Map<String, dynamic> payload})>[];
  final input = <Uint8List>[];
  @override
  Future<bool> sendTerminalFrame(
    String type,
    Map<String, dynamic> payload,
  ) async {
    sent.add((type: type, payload: Map.of(payload)));
    return true;
  }

  @override
  Future<bool> sendTerminalBinary(Uint8List bytes) async {
    input.add(bytes);
    return true;
  }

  @override
  Future<void> forceReconnect() async {}
  Map<String, dynamic> get latestOpen =>
      sent.lastWhere((f) => f.type == 'terminal_open').payload;
}

Future<void> _ready(AppNotifier app, _Connection connection, String stream) =>
    app.handleMachineEventForTest('m', {
      'type': 'terminal_ready',
      'payload': {
        'requestId': connection.latestOpen['requestId'],
        'agentId': 'a0',
        'streamId': stream,
        'protocolVersion': 3,
      },
    });

Future<void> _screen(
  AppNotifier app,
  _Connection connection,
  String stream,
  int start,
) => app.handleTerminalBinaryForTest(
  'm',
  encodeTerminalLocal(
    TerminalBinaryFrame(
      kind: TerminalBinaryKind.keyframe,
      streamId: stream,
      seq: 0,
      compressed: false,
      cols: connection.latestOpen['cols'] as int,
      rows: connection.latestOpen['rows'] as int,
      bytes: utf8.encode(
        List.generate(200, (i) => 'Retained marker ${start + i}\r\n').join(),
      ),
    ),
  )!,
);

void main() {
  testWidgets(
    'reconnect keeps output, Find location and draft until the replacement screen',
    (tester) async {
      final connection = _Connection();
      final app = createApp(connectionForTest: (_) => connection);
      final machine = app.machineStates['m']!
        ..nodeOnline = true
        ..terminalCapabilityAvailable = true;
      final attaching = app.addAgentToSwarm('m', 'a0');
      await mount(tester, app);
      await attaching;
      final pane = app.panes.single;
      final session = pane.session!;
      const firstStream = '00000000-0000-0000-0000-000000000001';
      const nextStream = '00000000-0000-0000-0000-000000000002';
      await _ready(app, connection, firstStream);
      await _screen(app, connection, firstStream, 0);
      app.toggleComposer(pane.id);
      await tester.pump();
      final composer = find.descendant(
        of: find.byType(TerminalComposer),
        matching: find.byType(TextField),
      );
      await tester.enterText(composer, 'Unsent direction');
      final draft = tester.widget<TextField>(composer).controller!;
      draft.selection = const TextSelection.collapsed(offset: 5);
      final renderer = terminalView(tester, session);
      final scroll = renderer.widget.scrollController!;
      final lineHeight = renderer.renderTerminal.lineHeight;
      scroll.jumpTo(20.25 * lineHeight);
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyF);
      await tester.enterText(findField, 'marker');
      await finishFind(tester);
      final field = tester.widget<TextField>(findField).controller!;
      field.selection = const TextSelection.collapsed(offset: 3);
      final search = tester
          .widget<TerminalFindBar>(find.byType(TerminalFindBar))
          .search;
      final matchedRow = search.match!.begin.y;
      final matchedText = session.terminal.buffer.lines[matchedRow].getText();
      final before = session.terminal;
      final offset = scroll.offset;
      session.transportLost();
      machine.nodeOnline = false;
      app.dismissError();
      await tester.pump();
      machine.nodeOnline = true;
      final retry = app.selectAgent('m', 'a0');
      await tester.pump();
      await retry;
      expect(
        pane.session,
        same(session),
        reason: 'Reconnection preserves the owning session',
      );
      expect(session.terminal, same(before));
      expect(terminalView(tester, session), same(renderer));
      expect(scroll.offset, offset);
      expect(tester.widget<TextField>(findField).controller, same(field));
      expect(tester.widget<TextField>(composer).controller, same(draft));
      expect(tester.widget<TextField>(composer).enabled, isFalse);
      expect(session.acceptsInput, isFalse);
      await _ready(app, connection, nextStream);
      await tester.pump();
      expect(
        session.terminal,
        same(before),
        reason: 'Ready without a keyframe must not blank the screen',
      );
      expect(session.acceptsInput, isFalse);
      await _screen(app, connection, nextStream, 10);
      await tester.pump();
      await finishFind(tester);
      expect(session.status, TerminalSessionStatus.controlling);
      expect(terminalView(tester, session), same(renderer));
      final restored = tester
          .widget<TerminalFindBar>(find.byType(TerminalFindBar))
          .search;
      expect(
        session.terminal.buffer.lines[restored.match!.begin.y].getText(),
        matchedText,
      );
      expect(tester.widget<TextField>(findField).controller, same(field));
      expect(field.selection.baseOffset, 3);
      expect(draft.text, 'Unsent direction');
      expect(draft.selection.baseOffset, 5);
      expect(tester.widget<TextField>(composer).enabled, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(scroll.offset, closeTo(10.25 * lineHeight, 0.01));
      expect(connection.input, isEmpty);
      expect(connection.sent.where((f) => f.type == 'message'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      await connection.close();
    },
  );
}
