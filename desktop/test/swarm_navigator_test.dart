import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/state/swarm_search.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/swarm_navigator.dart';
import 'package:harness/widgets/swarm_switcher.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

void main() {
  testWidgets('swarm parents appear once above their indented agents', (
    tester,
  ) async {
    final app = createApp();
    final pane = app.adoptSessionForTest(terminal('a0', []));
    final populated = app.activeSwarm;
    app.renameSwarm(populated.id, 'Release');
    app.newSwarm(name: 'Empty');
    final empty = app.activeSwarm;
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyP);
    final navigator = find.byType(SwarmNavigator);
    final parent = find.byKey(ValueKey(swarmDestinationId(populated.id)));
    final child = find.byKey(ValueKey(agentLocationId(populated.id, pane.id)));
    final emptyParent = find.byKey(ValueKey(swarmDestinationId(empty.id)));
    expect(
      find.descendant(of: navigator, matching: find.text('Release')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigator, matching: find.text('Empty')),
      findsOneWidget,
    );
    expect(
      tester.getRect(parent).bottom,
      lessThanOrEqualTo(tester.getRect(child).top),
    );
    final parentPadding =
        tester.widget<ListTile>(parent).contentPadding! as EdgeInsets;
    final childPadding =
        tester.widget<ListTile>(child).contentPadding! as EdgeInsets;
    expect(childPadding.left, greaterThan(parentPadding.left));
    await tester.tap(parent);
    await tester.pump();
    expect(app.activeSwarm, same(populated));
    await chord(tester, LogicalKeyboardKey.keyP);
    await tester.tap(emptyParent);
    await tester.pump();
    expect(app.activeSwarm, same(empty));
    expect(app.panes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  test('each membership is an exact destination, never an implicit add or fallback', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final pane = app.adoptSessionForTest(terminal('a0', []));
    final first = app.activeSwarm;
    app.renameSwarm(first.id, 'Release');
    app.newSwarm(name: 'Review');
    final second = app.activeSwarm;
    await app.addAgentToSwarm('m', 'a0');
    app.newSwarm(name: 'Research');
    final third = app.activeSwarm;
    await app.addAgentToSwarm('m', 'a0');
    final search = SwarmSearchController(app, [], navigating: true);
    addTearDown(search.dispose);
    search.setQuery('Agent 0');
    expect(search.rows.map((r) => r.swarmId).toSet(), {
      first.id,
      second.id,
      third.id,
    });
    expect(search.rows.map((r) => r.id).toSet(), hasLength(6));
    expect(search.selected?.agentId, 'a0');
    expect(search.previewVisible, isFalse);
    final exact = search.rows.singleWhere(
      (r) => r.swarmId == second.id && r.agentId != null,
    );
    expect(search.canAdd(exact), isFalse);
    expect(
      await activateSwarmDestination(app, exact, destinationSwarmId: third.id),
      isTrue,
    );
    expect(
      app.activeSwarmId,
      second.id,
      reason: 'The active swarm also contains this agent',
    );
    expect(app.focusedPane, same(pane));
    expect(first.panes, [pane]);
    expect(second.panes, [pane]);
    expect(third.panes, [pane]);
    await app.closeSwarm(second.id);
    final active = app.activeSwarmId;
    expect(
      await activateSwarmDestination(app, exact, destinationSwarmId: first.id),
      isFalse,
    );
    expect(
      app.activeSwarmId,
      active,
      reason: 'A removed location cannot redirect to another membership',
    );
    search.setQuery('Agent 69');
    expect(
      search.rows,
      isEmpty,
      reason: 'Discovered agents without a view belong to Add',
    );
    expect(search.submit(), isNull);
  });

  test('location search uses only its own swarm context and output reuses the catalog', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final session = terminal('a0', []);
    app.adoptSessionForTest(session);
    app.renameSwarm(app.activeSwarmId, 'Release');
    app.newSwarm(name: 'Research');
    await app.addAgentToSwarm('m', 'a0');
    final catalog = SwarmLocationCatalog();
    final first = catalog.read(app, []);
    session.terminal.write('More output\r\n');
    app.dismissError();
    expect(catalog.read(app, []), same(first));
    final rows = rankSwarmLocations(first, 'Agent 0 Research');
    expect(rows, hasLength(2));
    expect(rows.first.isSwarm, isTrue);
    expect(rows.last.swarmName, 'Research');
  });

  test(
    'locations refresh discovered context and retain offline views',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final session = terminal('a0', []);
      final pane = app.adoptSessionForTest(session);
      final catalog = SwarmLocationCatalog();
      final first = catalog.read(app, []);
      final machine = app.machineStates['m']!;
      machine.agents = const [
        Agent(
          id: 'a0',
          name: 'Changed title',
          engine: 'hermes',
          terminalAvailable: true,
          project: AgentProject(name: 'Updated project', cwd: '/work/updated'),
        ),
      ];
      final updated = catalog.read(app, []);
      expect(updated, isNot(same(first)));
      final changed = rankSwarmLocations(updated, 'Changed updated hermes');
      expect(changed, hasLength(2));
      expect(changed.first.isSwarm, isTrue);
      expect(changed.last.paneId, pane.id);
      expect(changed.last.detail, contains('Updated project'));
      app.machineStates.clear();
      final retained = catalog
          .read(app, [])
          .singleWhere((r) => r.paneId != null);
      expect(retained.title, session.agentName);
      expect(retained.machineLabel, 'm');
      expect(retained.engine, session.engineId);
      expect(
        await activateSwarmDestination(
          app,
          retained,
          destinationSwarmId: app.activeSwarmId,
        ),
        isTrue,
      );
      expect(app.focusedPane, same(pane));
    },
  );

  testWidgets(
    'navigation offers three locations and sends the next key only to the chosen agent',
    (tester) async {
      final app = createApp();
      final input = <TerminalBinaryFrame>[];
      final pane = app.adoptSessionForTest(terminal('a0', input));
      final first = app.activeSwarm;
      app.renameSwarm(first.id, 'Release');
      app.newSwarm(name: 'Review');
      final second = app.activeSwarm;
      await app.addAgentToSwarm('m', 'a0');
      app.newSwarm(name: 'Research');
      final third = app.activeSwarm;
      await app.addAgentToSwarm('m', 'a0');
      app.machineStates['m']!.nodeOnline = true;
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyP);
      final field = find.byKey(const ValueKey('swarm-search-input'));
      await tester.enterText(field, 'Agent 0');
      await tester.pump();
      expect(find.byType(SwarmNavigator), findsOneWidget);
      expect(find.byType(SwarmSearchResults), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SwarmNavigator),
          matching: find.text('Release'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SwarmNavigator),
          matching: find.text('Review'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SwarmNavigator),
          matching: find.text('Research'),
        ),
        findsOneWidget,
      );
      final pickerRect = tester.getRect(
        find.byKey(const ValueKey('swarm-search-results')),
      );
      await tester.tap(
        find.byKey(ValueKey(agentLocationId(second.id, pane.id))),
      );
      await tester.pump();
      expect(app.activeSwarm, same(second));
      expect(input, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
      expect(input.single.bytes, [27, 91, 68]);
      expect(first.panes, [pane]);
      expect(third.panes, [pane]);
      await tester.tap(find.byKey(const ValueKey('swarm-add-agent-button')));
      await tester.pump();
      expect(find.byType(SwarmNavigator), findsNothing);
      expect(find.byType(SwarmSearchResults), findsOneWidget);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('swarm-search-results')))
            .width,
        greaterThan(pickerRect.width),
      );
      expect(find.text('New agent'), findsOneWidget);
      await tester.enterText(field, 'Agent 0');
      await tester.pump();
      expect(find.text('In this swarm'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(second.panes, [pane]);
      expect(find.byType(SwarmSearchResults), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'an unmatched navigation query can enter Add without losing the query or changing membership',
    (tester) async {
      final app = createApp();
      final pane = app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyP);
      final input = find.byKey(const ValueKey('swarm-search-input'));
      await tester.enterText(input, 'Agent 69');
      await tester.pump();
      expect(find.textContaining('No matching open agents'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('navigation-add-agent')));
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, 'Agent 69');
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isTrue);
      expect(app.panes, [pane]);
      expect(find.text('New agent'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swarm-search-preview')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
