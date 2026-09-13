import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:xterm/xterm.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;
import 'swarm_switcher_test.dart' show jumpField;

void main() {
  test('one cached catalog searches all four objects and explicit remote project members', () {
    final app = createApp();
    addTearDown(app.dispose);
    app.renameSwarm(app.activeSwarmId, 'Morning work');
    final local = app.machineStates['m']!;
    local.agents = [
      const Agent(
        id: 'a0',
        name: 'Design',
        terminalAvailable: true,
        project: AgentProject(
          name: 'Workshop',
          cwd: '/work/workshop',
          branch: 'feature/wood',
        ),
      ),
    ];
    const remote = Machine(
      machineId: 'remote',
      name: 'iMac Home',
      authMode: MachineAuthMode.remote,
    );
    app.machineStates['remote'] = MachineState(remote)
      ..agents = [
        const Agent(id: 'chess', name: 'Chess', terminalAvailable: true),
      ];
    const projects = [
      SavedSwarmProject(
        machineId: 'm',
        path: '/work/workshop',
        name: 'Workshop',
        members: [(machineId: 'remote', agentId: 'chess')],
      ),
    ];
    final cache = SwarmSearchCatalog();
    final entries = cache.read(app, projects);
    expect(rankSwarmDestinations(entries, 'Morning').single.isSwarm, isTrue);
    expect(
      rankSwarmDestinations(entries, 'iMac Home').any((e) => e.isMachine),
      isTrue,
    );
    expect(
      rankSwarmDestinations(entries, 'Workshop').any((e) => e.isProject),
      isTrue,
    );
    expect(
      rankSwarmDestinations(entries, 'Workshop chess').single.agentId,
      'chess',
    );
    expect(rankSwarmDestinations(entries, 'wood Design').single.agentId, 'a0');
    expect(entries.singleWhere((e) => e.isProject).members, {
      agentDestinationId('m', 'a0'),
      agentDestinationId('remote', 'chess'),
    });
    app.dismissError();
    expect(cache.read(app, projects), same(entries));
    local.agents = [local.agents.single.copyWith(name: 'New design')];
    expect(cache.read(app, projects), isNot(same(entries)));
    expect(
      rankSwarmDestinations(
        cache.read(app, projects),
        'New design',
      ).single.agentId,
      'a0',
    );
  });

  test(
    'Add here reuses the exact terminal and refuses a closed destination swarm',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final session = terminal('a0', []);
      session.terminal.write('retained output');
      final shared = app.adoptSessionForTest(session);
      final original = app.activeSwarm;
      app.newSwarm(name: 'Review');
      final target = app.activeSwarm;
      final entry = swarmDestinations(app)
          .singleWhere((e) => e.agentId == 'a0');
      final choice = SwarmSearchSelection(entry, SwarmSearchAction.addHere);
      expect(
        await activateSwarmSearchSelection(
          app,
          choice,
          destinationSwarmId: target.id,
        ),
        isTrue,
      );
      expect(app.activeSwarm, same(target));
      expect(original.panes.single, same(target.panes.single));
      expect(target.panes.single, same(shared));
      expect(shared.session, same(session));
      expect(session.terminal.buffer.getText(), contains('retained output'));
      await app.closeSwarm(target.id);
      expect(
        await activateSwarmSearchSelection(
          app,
          choice,
          destinationSwarmId: target.id,
        ),
        isFalse,
      );
      expect(app.swarms, [original]);
    },
  );

  test('opening a group is explicit, uses a new swarm and opens only reviewed members', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final machine = app.machineStates['m']!;
    machine.agents = machine.agents.take(2).toList();
    final original = app.activeSwarm;
    final group = SwarmSearchCatalog()
        .read(app, [])
        .singleWhere((e) => e.isMachine);
    expect(
      await activateSwarmSearchSelection(
        app,
        SwarmSearchSelection(group),
        destinationSwarmId: original.id,
      ),
      isFalse,
    );
    expect(app.swarms, [original]);
    machine.agents = [
      ...machine.agents,
      const Agent(id: 'late', name: 'Late arrival', terminalAvailable: true),
    ];
    expect(
      await activateSwarmSearchSelection(
        app,
        SwarmSearchSelection(group, SwarmSearchAction.openGroup),
        destinationSwarmId: original.id,
      ),
      isTrue,
    );
    expect(app.swarms.length, 2);
    expect(original.panes, isEmpty);
    expect(app.activeSwarm.name, 'Test host');
    expect(app.panes.map((pane) => pane.agentId), ['a0', 'a1']);
    expect(app.allPanes.any((pane) => pane.agentId == 'late'), isFalse);
  });

  test(
    'removed group members and oversized groups cannot create a partial swarm',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final machine = app.machineStates['m']!;
      final oversized = SwarmSearchCatalog()
          .read(app, [])
          .singleWhere((e) => e.isMachine);
      expect(
        await activateSwarmSearchSelection(
          app,
          SwarmSearchSelection(oversized, SwarmSearchAction.openGroup),
          destinationSwarmId: app.activeSwarmId,
        ),
        isFalse,
      );
      machine.agents = machine.agents.take(2).toList();
      final group = SwarmSearchCatalog()
          .read(app, [])
          .singleWhere((e) => e.isMachine);
      machine.agents = machine.agents.take(1).toList();
      expect(
        await activateSwarmSearchSelection(
          app,
          SwarmSearchSelection(group, SwarmSearchAction.openGroup),
          destinationSwarmId: app.activeSwarmId,
        ),
        isFalse,
      );
      expect(app.swarms.length, 1);
      expect(app.panes, isEmpty);
    },
  );

  testWidgets(
    'browse, filter and return from a machine without opening any views',
    (tester) async {
      final app = createApp();
      await mount(tester, app);
      await tester.tap(find.text('Search…'));
      await tester.pump();
      await tester.enterText(jumpField, 'Test host');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('machine:m')));
      await tester.pump();
      expect(app.panes, isEmpty);
      expect(app.swarms.length, 1);
      final scopedField = find.byType(TextField);
      expect(
        tester.widget<TextField>(scopedField).focusNode!.hasFocus,
        isTrue,
        reason: 'Clicking a group must return the next key to its search field',
      );
      await tester.enterText(scopedField, 'Agent 19');
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Agent 19'), findsOneWidget);
      expect(find.text('Agent 0'), findsNothing);
      await tester.tap(find.byTooltip('All results'));
      await tester.pump();
      expect(tester.widget<TextField>(jumpField).controller!.text, 'Test host');
      expect(tester.widget<TextField>(jumpField).focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(app.panes, isEmpty);
      expect(find.byType(Dialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'the secondary action adds a shared view here and the first key reaches it',
    (tester) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final firstInputs = <TerminalBinaryFrame>[];
      final secondInputs = <TerminalBinaryFrame>[];
      final firstSession = terminal('a0', firstInputs);
      final shared = app.adoptSessionForTest(firstSession);
      final original = app.activeSwarm;
      app.newSwarm(name: 'Review');
      app.adoptSessionForTest(terminal('a1', secondInputs));
      final target = app.activeSwarm;
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyP);
      await tester.enterText(jumpField, 'Agent 0');
      await tester.pump();
      expect(find.text('Add to this swarm  ⌘↵'), findsOneWidget);
      await chord(tester, LogicalKeyboardKey.enter);
      expect(find.byType(Dialog), findsNothing);
      expect(app.activeSwarm, same(target));
      expect(target.panes.last, same(shared));
      expect(original.panes, [shared]);
      final view = tester.widget<TerminalView>(
        find.byWidgetPredicate(
          (w) =>
              w is TerminalView && identical(w.terminal, firstSession.terminal),
        ),
      );
      expect(view.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
      expect(firstInputs.single.bytes, [27, 91, 68]);
      expect(secondInputs, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'Return does not open a result while the search has composing text',
    (tester) async {
      final app = createApp();
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyP);
      await tester.enterText(jumpField, 'Agent 0');
      await tester.pump();
      final controller = tester.widget<TextField>(jumpField).controller!;
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 7),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
      expect(app.panes, isEmpty);
      controller.clearComposing();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.panes.single.agentId, 'a0');
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
