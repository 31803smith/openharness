import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/state/swarm_navigation.dart';

import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;
import 'swarm_interactions_test.dart' show chord;

void main() {
  testWidgets('Command-N opens Add and Shift-Command-N creates a fresh agent', (
    tester,
  ) async {
    final app = createApp();
    final input = <TerminalBinaryFrame>[];
    final pane = app.adoptSessionForTest(terminal('a0', input));
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyO);
    final field = find.byKey(const ValueKey('swarm-search-input'));
    final create = find.byKey(const ValueKey('swarm-search-new-agent'));
    expect(field, findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.getRect(create).top,
      greaterThan(
        tester
            .getRect(find.byKey(const ValueKey('swarm-search-results')))
            .bottom,
      ),
    );
    expect(tester.getRect(create).width, greaterThanOrEqualTo(180));
    expect(
      tester.getRect(field).width,
      tester.getRect(find.byKey(const ValueKey('swarm-search-results'))).width,
    );
    expect(find.text('Find a harness'), findsOneWidget);
    expect(
      find.descendant(of: create, matching: find.text('New Harness')),
      findsOneWidget,
    );
    expect(app.panes, [pane]);
    await chord(tester, LogicalKeyboardKey.keyN);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create Harness'), findsOneWidget);
    expect(app.panes, [pane]);
    expect(input, isEmpty);
    await tester.tap(find.text('Back to Search'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  for (final activate in ['click', 'enter']) {
    testWidgets('$activate opens one existing agent immediately in this tab', (
      tester,
    ) async {
      final app = createApp();
      final input = <TerminalBinaryFrame>[];
      final existing = terminal('a0', input);
      app.adoptSessionForTest(existing);
      final source = app.activeSwarm;
      app.newSwarm();
      final target = app.activeSwarm;
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyO);
      final field = find.byKey(const ValueKey('swarm-search-input'));
      await tester.enterText(field, 'Agent 0');
      await tester.pump();
      expect(find.byType(Checkbox), findsNothing);
      expect(app.panes, isEmpty);
      expect(find.byKey(const ValueKey('swarm-row-action')), findsOneWidget);
      expect(find.text('Open Harness'), findsOneWidget);
      expect(find.byKey(const ValueKey('swarm-search-accept')), findsNothing);
      if (activate == 'click') {
        await tester.tap(find.byKey(ValueKey(agentDestinationId('m', 'a0'))));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      }
      await tester.pump();
      expect(field, findsNothing);
      expect(app.activeSwarm, same(target));
      expect(target.panes, hasLength(1));
      expect(target.panes.single.session, same(existing));
      expect(source.panes, hasLength(1));
      expect(input, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
  testWidgets(
    'a recent harness opens here and stays deduplicated across tabs',
    (tester) async {
      final app = createApp();
      final input = <TerminalBinaryFrame>[];
      final existing = terminal('a0', input);
      app.adoptSessionForTest(existing);
      app.newSwarm();
      final target = app.activeSwarm;
      await mount(tester, app);
      final recent = find.byKey(ValueKey(agentDestinationId('m', 'a0')));
      expect(recent, findsOneWidget);
      await tester.tap(recent);
      await tester.pump();
      expect(app.activeSwarm, same(target));
      expect(target.panes.single.session, same(existing));
      app.newSwarm();
      await tester.pump();
      expect(recent, findsOneWidget);
      expect(app.activeSwarm.panes, isEmpty);
      expect(input, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
