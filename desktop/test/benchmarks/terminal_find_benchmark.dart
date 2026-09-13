import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_search.dart';
import 'package:xterm/xterm.dart';

import 'swarm_benchmark.dart' show distribution;

/// Explicit, isolated event-loop timing. Includes cooperative yields but no
/// native input, compositor, sockets or real sessions.
void main() {
  test('find across 10000 retained terminal rows', () async {
    final terminal = Terminal(maxLines: 10000)..resize(120, 24);
    terminal.write(
      List.generate(
        9999,
        (i) =>
            'Build $i: ${i % 20 == 0 ? 'Error' : 'ready'} · staging project /work/harness 界🙂\r\n',
      ).join(),
    );
    final search = TerminalSearch(terminal, origin: const CellOffset(0, 9800));
    final cold = Stopwatch()..start();
    search.setQuery('error');
    await search.settled;
    cold.stop();
    expect(search.count, 500);
    final queries = <int>[];
    final updates = <int>[];
    final steps = <int>[];
    for (var i = 0; i < 40; i++) {
      final watch = Stopwatch()..start();
      search.setQuery(i.isEven ? 'staging' : 'error');
      await search.settled;
      queries.add(watch.elapsedMicroseconds);
      watch.reset();
      search.step(1);
      steps.add(watch.elapsedMicroseconds);
      watch.reset();
      terminal.write('\r\x1b[2KCurrent error $i');
      await search.settled;
      updates.add(watch.elapsedMicroseconds);
    }
    debugPrint(
      'TERMINAL_FIND_BENCH ${jsonEncode({'kind': 'headless_debug_event_loop', 'rows': terminal.lines.length, 'coldQueryMs': cold.elapsedMicroseconds / 1000, 'cachedTextQuery': distribution(queries), 'liveRowUpdate': distribution(updates), 'nextMatch': distribution(steps)})}',
    );
    search.dispose();
    expect(terminal.listeners, isEmpty);
  });
}
