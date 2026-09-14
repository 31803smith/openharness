import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import '../swarm_screen_test.dart' show mount, terminal;
import '../swarm_state_test.dart' show createApp;
import 'swarm_benchmark.dart' show distribution;

/// Measures parsing and Flutter rendering of already-decoded streamed text.
/// No sockets, real sessions, native input or display timing are involved.
void main() {
  for (final count in [16, 48]) {
    testWidgets('background output with $count retained terminals', (
      tester,
    ) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      for (var i = 0; i < count; i++) {
        if (i > 0 && i % 4 == 0) app.newSwarm();
        final session = terminal('a$i', []);
        session.terminal.write(
          List.generate(1000, (line) => 'History line $line\r\n').join(),
        );
        app.adoptSessionForTest(session);
      }
      await mount(tester, app);
      for (var i = 0; i < count ~/ 4; i++) {
        app.stepSwarm(1);
        await tester.pump();
      }
      final visible = app.panes.map((pane) => pane.session!.terminal).toSet();
      final views = tester
          .stateList<TerminalViewState>(
            find.byType(TerminalView, skipOffstage: false),
          )
          .toList();
      final hidden = views
          .where((view) => !visible.contains(view.widget.terminal))
          .toList();
      expect(views, hasLength(count));
      expect(hidden, hasLength(count - 4));
      for (final scope in ['hidden', 'all']) {
        final destinations = scope == 'hidden' ? hidden : views;
        void writeBurst() {
          for (final view in destinations) {
            for (var packet = 0; packet < 4; packet++) {
              // Repaint one row to hold scrollback size constant.
              view.widget.terminal.write('\r\x1b[2KAgent update $packet');
            }
          }
        }

        for (var warmup = 0; warmup < 20; warmup++) {
          writeBurst();
          await tester.pump();
        }
        writeBurst();
        final dirty = hidden
            .where((view) => view.renderTerminal.debugNeedsLayout)
            .length;
        final scheduled = tester.binding.hasScheduledFrame;
        await tester.pump();
        final times = <int>[];
        for (var sample = 0; sample < 60; sample++) {
          final watch = Stopwatch()..start();
          writeBurst();
          await tester.pump();
          times.add(watch.elapsedMicroseconds);
        }
        debugPrint(
          'TERMINAL_BACKGROUND_BENCH ${jsonEncode({'kind': 'headless_debug_cpu', 'retainedTerminals': count, 'hiddenTerminals': hidden.length, 'scope': scope, 'updatesPerTerminalPerSample': 4, 'hiddenRenderersNeedingLayout': dirty, 'scheduledFrame': scheduled, 'outputAndFrame': distribution(times)})}',
        );
      }
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
}
