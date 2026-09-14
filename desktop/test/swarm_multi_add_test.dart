import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/state/swarm_search.dart';
import 'package:harness/terminal/terminal_binary.dart';

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
    await chord(tester, LogicalKeyboardKey.keyN);
    final field = find.byKey(const ValueKey('swarm-search-input'));
    final create = find.byKey(const ValueKey('swarm-search-new-agent'));
    expect(field, findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.getRect(create).center.dy,
      closeTo(tester.getRect(field).center.dy, 1),
    );
    expect(tester.getRect(create).width, greaterThanOrEqualTo(148));
    expect(app.panes, [pane]);
    await chord(tester, LogicalKeyboardKey.keyN, shift: true);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Create agent'), findsOneWidget);
    expect(app.panes, [pane]);
    expect(input, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  test(
    'selection survives queries and adds exact runtimes to its captured swarm',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final input = <TerminalBinaryFrame>[];
      final first = app.adoptSessionForTest(terminal('a0', input));
      final second = app.adoptSessionForTest(terminal('a1', input));
      final source = app.activeSwarm;
      app.newSwarm(name: 'Review');
      final target = app.activeSwarm;
      final search = SwarmSearchController(app, [], adding: true);
      addTearDown(search.dispose);
      search.setQuery('Agent 0');
      search.toggle();
      search.setQuery('Agent 1');
      search.toggle();
      search.setQuery('nothing matches this');
      expect(search.rows, isEmpty);
      expect(search.checked.map((row) => row.agentId), ['a0', 'a1']);
      expect(target.panes, isEmpty);
      expect(search.canAccept, isTrue);
      final selection = search.submit()!;
      app.selectSwarm(source.id);
      expect(
        await activateSwarmSearchSelection(
          app,
          selection,
          destinationSwarmId: search.targetId,
        ),
        isTrue,
      );
      expect(app.activeSwarm, same(source));
      expect(target.panes, [first, second]);
      expect(source.panes, [first, second]);
      expect(input, isEmpty);
      expect(
        search.checked,
        isEmpty,
        reason: 'Added memberships leave the selection',
      );
    },
  );

  test(
    'a stale selection cannot partially add its remaining available agents',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final target = app.activeSwarm;
      final search = SwarmSearchController(app, [], adding: true);
      addTearDown(search.dispose);
      search.setQuery('Agent 0');
      search.toggle();
      search.setQuery('Agent 1');
      search.toggle();
      final chosen = search.submit()!;
      app.machineStates['m']!.agents.removeWhere((agent) => agent.id == 'a1');
      app.dismissError();
      expect(search.checkedCount, 2);
      expect(search.canAccept, isFalse);
      expect(search.unavailableMessage, contains('unavailable'));
      expect(
        await activateSwarmSearchSelection(
          app,
          chosen,
          destinationSwarmId: target.id,
        ),
        isFalse,
      );
      expect(target.panes, isEmpty);
      search.removeChecked(agentDestinationId('m', 'a1'));
      expect(search.canAccept, isTrue);
      expect(search.submit()!.agents.single.agentId, 'a0');
    },
  );

  test(
    'capacity changes are validated for the entire selection before adding',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final search = SwarmSearchController(app, [], adding: true);
      addTearDown(search.dispose);
      search.setQuery('Agent 68');
      search.toggle();
      search.setQuery('Agent 69');
      search.toggle();
      final chosen = search.submit()!;
      for (var i = 0; i < AppNotifier.maxPanes - 1; i++) {
        app.adoptSessionForTest(terminal('a$i', []));
      }
      app.dismissError();
      expect(search.capacity, 1);
      expect(search.canAccept, isFalse);
      expect(
        await activateSwarmSearchSelection(
          app,
          chosen,
          destinationSwarmId: search.targetId,
        ),
        isFalse,
      );
      expect(app.panes, hasLength(AppNotifier.maxPanes - 1));
      expect(
        app.panes.any((pane) => pane.agentId == 'a68' || pane.agentId == 'a69'),
        isFalse,
      );
      search.clearChecked();
      search.toggle();
      expect(search.checkedCount, 1);
      search.setQuery('Agent 68');
      expect(search.canToggle(search.selected!), isFalse);
    },
  );

  test('group and individual selections deduplicate by machine and agent', () {
    final app = createApp();
    addTearDown(app.dispose);
    app.adoptSessionForTest(terminal('a0', []));
    app.adoptSessionForTest(terminal('a1', []));
    final source = app.activeSwarm;
    app.newSwarm();
    final search = SwarmSearchController(app, [], adding: true);
    addTearDown(search.dispose);
    search.setQuery('Agent 0');
    search.toggle();
    search.setQuery('');
    final group = search.rows.singleWhere(
      (row) => row.id == swarmDestinationId(source.id),
    );
    search.toggle(group);
    expect(search.checked.map((row) => row.agentId), ['a0', 'a1']);
    expect(search.isChecked(group), isTrue);
    search.toggle(group);
    expect(search.checked, isEmpty);
    expect(app.panes, isEmpty);
  });

  testWidgets('checkbox and keyboard selection share one list across queries', (
    tester,
  ) async {
    final app = createApp();
    final input = <TerminalBinaryFrame>[];
    final first = app.adoptSessionForTest(terminal('a0', input));
    final second = app.adoptSessionForTest(terminal('a1', input));
    final source = app.activeSwarm;
    app.newSwarm();
    final target = app.activeSwarm;
    await mount(tester, app);
    await tester.tap(find.byKey(const ValueKey('swarm-add-agent-button')));
    await tester.pump();
    final field = find.byKey(const ValueKey('swarm-search-input'));
    await tester.enterText(field, 'Agent 0');
    await tester.pump();
    expect(find.byKey(const ValueKey('swarm-row-action')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swarm-search-new-agent')),
      findsOneWidget,
    );
    expect(
      tester.widget(find.byKey(const ValueKey('swarm-search-new-agent'))),
      isA<FilledButton>(),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    expect(target.panes, isEmpty);
    await tester.enterText(field, 'Agent 1');
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('select:${agentDestinationId('m', 'a1')}')),
    );
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    await tester.tap(find.byTooltip('Remove Agent 0'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.enterText(field, 'Agent 0');
    await tester.pump();
    await tester.tap(
      find.byKey(ValueKey('select:${agentDestinationId('m', 'a0')}')),
    );
    await tester.pump();
    await tester.enterText(field, 'no results here');
    await tester.pump();
    expect(find.text('Add 2 agents'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(target.panes, [second, first]);
    expect(source.panes, [first, second]);
    expect(app.activeSwarm, same(target));
    expect(input, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
