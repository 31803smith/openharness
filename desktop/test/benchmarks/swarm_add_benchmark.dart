// Run explicitly with --concurrency=1 after other builds and tests finish.
// Measures Flutter event handling and frame-pump CPU, not native/display latency.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/swarm_search_input.dart';

import '../swarm_screen_test.dart' show mount, terminal;
import '../swarm_state_test.dart' show createApp;
import 'swarm_benchmark.dart' show distribution;

void main() {
  testWidgets('Add picker keyboard and frame CPU with 2000 discovered agents', (
    tester,
  ) async {
    final app = createApp();
    final input = <TerminalBinaryFrame>[];
    app.machineStates['m']!
      ..nodeOnline = true
      ..agents = [
        for (var i = 0; i < 2000; i++)
          Agent(
            id: 'a$i',
            name: 'Agent ${i.toString().padLeft(4, '0')}',
            engine: 'codex',
            terminalAvailable: true,
            project: AgentProject(
              name: 'Project ${i % 50}',
              cwd: '/work/project-${i % 50}',
              branch: 'main',
            ),
          ),
      ];
    for (final i in [0, 1, 2, 3, 1999]) {
      if (i == 1999) app.newSwarm(name: 'Current work');
      final session = terminal('a$i', input);
      session.terminal.write(
        List.generate(
          1000,
          (row) =>
              '$row  Recent work on agent $i. Useful context for choosing.\r\n',
        ).join(),
      );
      app.adoptSessionForTest(session);
    }
    final target = app.activeSwarm;
    final panes = [...target.panes];
    const native = MethodChannel('harness/swarm_tabs');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(native, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(native, null));
    await mount(tester, app, nativeTabs: true);

    var openDispatchMicros = 0;
    var openFrameMicros = 0;
    Future<void> open() async {
      final watch = Stopwatch()..start();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      openDispatchMicros = watch.elapsedMicroseconds;
      watch.reset();
      await tester.pump();
      openFrameMicros = watch.elapsedMicroseconds;
    }

    Future<void> close() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<Map<String, num>> measure(
      Future<void> Function(int) action, {
      Future<void> Function()? after,
    }) async {
      final times = <int>[];
      for (var i = -20; i < 100; i++) {
        final watch = Stopwatch()..start();
        await action(i + 20);
        watch.stop();
        if (i >= 0) times.add(watch.elapsedMicroseconds);
        await after?.call();
      }
      return distribution(times);
    }

    Future<Map<String, int>> rebuilds(Future<void> Function() action) async {
      final counts = <String, int>{};
      debugOnRebuildDirtyWidget = (element, _) {
        final type = element.widget.runtimeType.toString();
        counts.update(type, (value) => value + 1, ifAbsent: () => 1);
      };
      try {
        await action();
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      return counts;
    }

    final dispatchTimes = <int>[];
    final frameTimes = <int>[];
    final opening = await measure((i) async {
      await open();
      if (i >= 20) {
        dispatchTimes.add(openDispatchMicros);
        frameTimes.add(openFrameMicros);
      }
    }, after: close);
    final openingRebuilds = await rebuilds(open);
    final closingRebuilds = await rebuilds(close);
    await open();
    final field = find.byKey(const ValueKey('swarm-search-input'));
    final controller = tester
        .widget<SwarmSearchInput>(
          find.ancestor(of: field, matching: find.byType(SwarmSearchInput)),
        )
        .search!;
    const queries = ['Agent 0', 'Agent 00', 'Agent 000', 'Agent 0000'];
    Future<void> query(int i) async {
      await tester.enterText(field, queries[i % queries.length]);
      await tester.pump();
    }

    final typing = await measure(query);
    await query(0);
    final typingRebuilds = await rebuilds(() => query(1));
    expect(controller.selected!.agentId, 'a0');

    Future<void> arrow() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }

    final arrows = await measure((_) => arrow());
    final arrowRebuilds = await rebuilds(arrow);
    expect(controller.cursor, greaterThan(0));
    expect(input, isEmpty);
    expect(app.activeSwarm, same(target));
    expect(target.panes, panes);
    expect(tester.takeException(), isNull);
    debugPrint(
      'SWARM_BENCH ${jsonEncode({'kind': 'headless_debug_cpu', 'operation': 'add_picker_frame', 'agents': 2000, 'machines': 1, 'projects': 50, 'retainedTerminals': 5, 'scrollbackLinesPerTerminal': 1000, 'viewport': '1280x800', 'nativeBridge': 'stubbed', 'openAndFrame': opening, 'openDispatch': distribution(dispatchTimes), 'openFrame': distribution(frameTimes), 'queryAndFrame': typing, 'arrowAndFrame': arrows, 'openingRebuilds': openingRebuilds, 'closingRebuilds': closingRebuilds, 'queryRebuilds': typingRebuilds, 'arrowRebuilds': arrowRebuilds})}',
    );
    await close();
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
