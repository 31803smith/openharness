import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/widgets/swarm_switcher.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

void main() {
  for (final inline in [false, true]) {
    testWidgets(
      'agent and group results use a single list without previews (inline=$inline)',
      (tester) async {
        final app = createApp();
        app.adoptSessionForTest(
          terminal('a0', [])..terminal.write('Output belongs in the terminal'),
        );
        app.newSwarm();
        await mount(tester, app);
        final field = find.byKey(
          ValueKey(
            inline ? 'swarm-welcome-search-input' : 'swarm-search-input',
          ),
        );
        if (!inline) await chord(tester, LogicalKeyboardKey.keyN);
        for (final query in ['Agent 0', 'Test host']) {
          await tester.enterText(field, query);
          await tester.pump();
          final search = tester
              .widget<SwarmSearchResults>(find.byType(SwarmSearchResults))
              .search;
          expect(search.rows, isNotEmpty);
          expect(
            find.byKey(const ValueKey('swarm-search-preview')),
            findsNothing,
          );
          expect(
            find.textContaining('Output belongs in the terminal'),
            findsNothing,
          );
          final list = tester.getRect(
            find.byKey(const ValueKey('swarm-search-result-list')),
          );
          final surface = tester.getRect(
            find.byKey(
              ValueKey(
                inline
                    ? 'swarm-welcome-search-results'
                    : 'swarm-search-results',
              ),
            ),
          );
          expect(list.width, closeTo(surface.width, 2));
        }
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
