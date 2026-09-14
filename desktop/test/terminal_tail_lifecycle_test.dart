import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/pane_preset.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/terminal/terminal_font_store.dart';
import 'package:harness/terminal/terminal_session.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;
import 'terminal_find_test.dart' show terminalView;

Future<void> snapshot(
  TerminalSession session,
  int seq,
  int lines,
) => session.handleBinary(
  TerminalBinaryFrame(
    kind: TerminalBinaryKind.keyframe,
    streamId: session.streamId!,
    seq: seq,
    cols: 100,
    rows: 40,
    compressed: false,
    bytes: utf8.encode(
      '${List.generate(lines, (i) => 'History line $i\r\n').join()}LATEST OUTPUT',
    ),
  ),
);

void atBottom(WidgetTester tester, TerminalSession session) {
  final view = terminalView(tester, session);
  final position = view.widget.scrollController!.position;
  expect(position.maxScrollExtent, greaterThan(1000));
  expect(
    position.pixels,
    closeTo(position.maxScrollExtent, 0.5),
    reason: '${session.agentId} should show its latest output',
  );
  final cursor = view.renderTerminal.cursorOffset;
  expect(cursor.dy, greaterThanOrEqualTo(0));
  expect(cursor.dy, lessThan(view.renderTerminal.size.height));
}

void main() {
  testWidgets(
    'returning to live output before a layout follows the new extent',
    (tester) async {
      final app = createApp();
      final session = terminal('a0', []);
      await snapshot(session, 0, 800);
      app.adoptSessionForTest(session);
      await mount(tester, app);
      terminalView(tester, session).widget.scrollController!.jumpTo(100);
      await tester.pump();
      session.terminal.write('\r\n${'Burst output\r\n' * 200}LATEST');
      // Input and output can arrive between frames. The old extent is stale.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      atBottom(tester, session);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  for (final local in [true, false]) {
    testWidgets(
      'all delayed ${local ? 'local' : 'remote'} panes start at bottom',
      (tester) async {
        final app = createApp();
        app.stateOf('m')!.localOnly = local;
        final sessions = [for (var i = 0; i < 3; i++) terminal('a$i', [])];
        for (final session in sessions) {
          app.adoptSessionForTest(session);
        }
        await mount(tester, app);
        for (var i = 0; i < sessions.length; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          await snapshot(sessions[i], 0, 600 + i * 100);
          await tester.pump();
          atBottom(tester, sessions[i]);
        }
        // A resize response can replace every snapshot before the next frame.
        tester.view.physicalSize = const Size(860, 520);
        for (final session in sessions) {
          await snapshot(session, 1, 1100);
        }
        await tester.pump();
        for (final session in sessions) {
          atBottom(tester, session);
        }
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'adding a retained pane to a new harness reveals the latest output',
    (tester) async {
      final app = createApp();
      final session = terminal('a0', []);
      await snapshot(session, 0, 900);
      app.adoptSessionForTest(session);
      await mount(tester, app);
      final view = terminalView(tester, session);
      view.widget.scrollController!.jumpTo(100);
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyT);
      await tester.enterText(
        find.byKey(const ValueKey('swarm-search-input')),
        'Agent 0',
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(terminalView(tester, session), same(view));
      atBottom(tester, session);
      // Shared panes can remain visible with exactly the same geometry while
      // switching harnesses, so visibility/size alone cannot detect a reveal.
      view.widget.scrollController!.jumpTo(100);
      await tester.pump();
      app.selectSwarm(app.swarms.first.id);
      await tester.pump();
      expect(terminalView(tester, session), same(view));
      atBottom(tester, session);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'relayout, adding, zoom and returning reveal the tail of every pane',
    (tester) async {
      final app = createApp();
      final sessions = [terminal('a0', []), terminal('a1', [])];
      for (final session in sessions) {
        await snapshot(session, 0, 800);
        app.adoptSessionForTest(session);
      }
      await mount(tester, app);
      void scrollUp() {
        for (final session in sessions) {
          terminalView(tester, session).widget.scrollController!.jumpTo(100);
        }
      }

      scrollUp();
      await tester.pump();
      app.setPreset(2, PanePreset.rows);
      await tester.pump();
      for (final session in sessions) {
        atBottom(tester, session);
      }
      scrollUp();
      final third = terminal('a2', []);
      await snapshot(third, 0, 1200);
      app.adoptSessionForTest(third);
      sessions.add(third);
      await tester.pump();
      for (final session in sessions) {
        atBottom(tester, session);
      }
      scrollUp();
      app.toggleZoomPane();
      await tester.pump();
      atBottom(tester, third);
      app.toggleZoomPane();
      await tester.pump();
      for (final session in sessions) {
        atBottom(tester, session);
      }
      scrollUp();
      final original = app.activeSwarmId;
      app.newSwarm();
      await tester.pump();
      for (final session in sessions) {
        session.terminal.write('\r\n${'Hidden output\r\n' * 200}LATEST');
      }
      app.selectSwarm(original);
      await tester.pump();
      for (final session in sessions) {
        atBottom(tester, session);
      }
      final font = terminalFontStore.value;
      addTearDown(() => terminalFontStore.value = font);
      scrollUp();
      terminalFontStore.value = font.copyWith(fontSize: font.fontSize + 2);
      await tester.pump();
      for (final session in sessions) {
        atBottom(tester, session);
      }
      // Ordinary output must still allow deliberate reading within this view.
      final reading = terminalView(tester, third).widget.scrollController!;
      reading.jumpTo(100);
      await tester.pump();
      third.terminal.write('\r\nMore output');
      await tester.pump();
      expect(reading.offset, 100);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
