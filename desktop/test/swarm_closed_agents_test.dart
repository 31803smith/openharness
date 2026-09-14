import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/terminal/terminal_session.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

void main() {
  test(
    'History interleaves closed agents and swarms with captured identities',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      app.machineStates['m']!.agents = [
        const Agent(
          id: 'a0',
          name: 'Planning',
          engine: 'claude',
          terminalAvailable: true,
        ),
      ];
      app.renameSwarm(app.activeSwarmId, 'Work');
      await app.addAgentToSwarm('m', 'a0');
      await app.closePane(app.focusedPaneId!);
      final agentId = app.closedHistory.single.historyId;
      await app.closeSwarm(app.activeSwarmId);
      final swarmId = app.closedHistory.first.historyId;
      expect(app.closedHistory.map((e) => e.runtimeType), [
        ClosedSwarm,
        ClosedAgent,
      ]);
      // Discovery can disappear without losing the closed agent's name/icon.
      app.machineStates.clear();
      final rows = closedWorkDestinations(app);
      expect(rows.map((e) => e.id), [swarmId, agentId]);
      expect(rows.last.title, 'Planning');
      expect(rows.last.engine, 'claude');
      expect(rows.last.agentId, 'a0');
      expect(rows.last.detail, contains('Test host · Work'));
      expect(rows.first.isSwarm, isTrue);
      expect(rows.last.isSwarm, isFalse);
    },
  );

  test(
    'reopening a shared agent restores its slot and keeps the live terminal',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final first = app.adoptSessionForTest(terminal('a0', []));
      final shared = app.adoptSessionForTest(terminal('a1', []));
      final last = app.adoptSessionForTest(terminal('a2', []));
      final work = app.activeSwarm;
      app.focusPane(shared.id);
      app.togglePinPane(shared.id);
      app.toggleZoomPane();
      app.newSwarm(name: 'Other');
      await app.addAgentToSwarm('m', 'a1');
      final other = app.activeSwarm;
      app.selectSwarm(work.id);
      await app.closePane(shared.id);
      expect(work.panes, [first, last]);
      expect(other.panes.single, same(shared));
      app.selectSwarm(other.id);
      app.toggleComposer(shared.id);
      expect(app.reopenClosed(), isTrue);
      expect(app.activeSwarm, same(work));
      expect(work.panes, [first, shared, last]);
      expect(app.focusedPaneId, shared.id);
      expect(app.zoomedPaneId, shared.id);
      expect(app.isPanePinned(shared), isTrue);
      expect(shared.composerVisible, isTrue);
      expect(other.panes.single.session, same(shared.session));
      expect(app.closedHistory, isEmpty);
    },
  );

  test('a closed parent gets a swarm when its agent alone is reopened', () async {
    final app = createApp();
    addTearDown(app.dispose);
    app.renameSwarm(app.activeSwarmId, 'Workshop');
    final origin = app.activeSwarmId;
    await app.addAgentToSwarm('m', 'a0');
    await app.addAgentToSwarm('m', 'a1');
    await app.closePane(app.panes.first.id);
    final closure = app.closedHistory.single.historyId;
    await app.closeSwarm(origin);
    expect(app.reopenClosed(historyId: closure), isTrue);
    expect(app.activeSwarmId, origin);
    expect(app.activeSwarm.name, 'Workshop');
    expect(app.panes.single.agentId, 'a0');
    expect(app.closedHistory.single, isA<ClosedSwarm>());
    expect(app.reopenClosed(historyId: closure), isFalse);
    // Restoring the separately closed group cannot duplicate a Swarm identity.
    expect(app.reopenClosed(), isTrue);
    expect(app.panes.single.agentId, 'a1');
    expect(app.swarms.map((s) => s.id).toSet().length, app.swarms.length);
  });

  test(
    'agent recovery can fit at the tab limit when swarm recovery cannot',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      await app.addAgentToSwarm('m', 'a0');
      final origin = app.activeSwarmId;
      await app.closePane(app.focusedPaneId!);
      final agentId = app.closedHistory.single.historyId;
      app.newSwarm(name: 'Closed group');
      await app.closeSwarm(app.activeSwarmId);
      while (app.swarms.length < AppNotifier.maxSwarms) {
        app.newSwarm();
      }
      expect(app.canReopenLastClosed, isFalse);
      expect(app.canReopenClosed(agentId), isTrue);
      expect(app.reopenClosed(historyId: agentId), isTrue);
      expect(app.activeSwarmId, origin);
      expect(app.panes.single.agentId, 'a0');
      expect(app.swarms, hasLength(AppNotifier.maxSwarms));
    },
  );

  test(
    'a full destination retains its closed agent until there is room',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      await app.addAgentToSwarm('m', 'a0');
      await app.closePane(app.focusedPaneId!);
      final id = app.closedHistory.single.historyId;
      for (var i = 1; i <= AppNotifier.maxPanes; i++) {
        await app.addAgentToSwarm('m', 'a$i');
      }
      expect(app.canReopenClosed(id), isFalse);
      expect(app.reopenClosed(historyId: id), isFalse);
      expect(app.closedHistory.single.historyId, id);
      await app.closePane(app.panes.first.id);
      expect(app.reopenClosed(historyId: id), isTrue);
      expect(app.panes, hasLength(AppNotifier.maxPanes));
      expect(app.focusedPane!.agentId, 'a0');
    },
  );

  test(
    'manually re-added agents are focused without duplicating membership',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      await app.addAgentToSwarm('m', 'a0');
      await app.closePane(app.focusedPaneId!);
      await app.addAgentToSwarm('m', 'a0');
      final reopened = app.panes.single;
      expect(app.reopenClosed(), isTrue);
      expect(app.panes.single, same(reopened));
      expect(app.closedHistory, isEmpty);
    },
  );

  test('rapid close/reopen cannot reclaim the closing controller', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final closed = Completer<bool>();
    final sent = <String>[];
    final session =
        TerminalSession(
            machineId: 'm',
            agentId: 'a0',
            agentName: 'Work',
            engineId: 'codex',
            send: (type, _) {
              sent.add(type);
              return type == 'terminal_close'
                  ? closed.future
                  : Future.value(true);
            },
            sendBinary: (_) async => true,
          )
          ..streamId = 'closing-stream'
          ..status = TerminalSessionStatus.controlling;
    final old = app.adoptSessionForTest(session);
    final closing = app.closePane(old.id);
    expect(app.reopenClosed(), isTrue);
    final restored = app.panes.single;
    expect(restored, isNot(same(old)));
    expect(restored.session, isNull);
    closed.complete(true);
    await closing;
    expect(app.panes.single, same(restored));
    expect(sent, ['terminal_close']);
  });

  test(
    'the combined history stays bounded without retaining sessions',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      for (var i = 0; i < 30; i++) {
        await app.addAgentToSwarm('m', 'a0');
        await app.closePane(app.focusedPaneId!);
        app.renameSwarm(app.activeSwarmId, 'Work $i');
        await app.closeSwarm(app.activeSwarmId);
      }
      expect(app.closedHistory, hasLength(AppNotifier.maxClosedSwarms));
      expect(app.closedHistory.whereType<ClosedAgent>(), hasLength(12));
      expect(app.closedSwarms, hasLength(12));
      expect(app.allPanes, isEmpty);
    },
  );

  testWidgets('Cmd-Shift-T restores the last removed agent', (tester) async {
    final app = createApp();
    app.adoptSessionForTest(terminal('a0', []));
    final origin = app.activeSwarm;
    await mount(tester, app);
    await app.closePane(app.focusedPaneId!);
    await tester.pump();
    await chord(tester, LogicalKeyboardKey.keyT, shift: true);
    expect(app.activeSwarm, same(origin));
    expect(app.panes.single.agentId, 'a0');
    expect(app.closedHistory, isEmpty);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
