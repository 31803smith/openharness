import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/terminal/terminal_binary.dart';

import 'swarm_state_test.dart' show createApp;
import 'swarm_screen_test.dart' show terminal;

void main() {
  testWidgets('tab navigation does not resend the agent inventory', (
    tester,
  ) async {
    const channel = MethodChannel('harness/swarm_tabs');
    final messages = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      messages.add(call);
      return true;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final app = createApp();
    final machine = app.machineStates['m']!;
    machine.agents = [
      for (var i = 0; i < 512; i++)
        Agent(id: 'a$i', name: 'Agent $i', terminalAvailable: true),
    ];
    final first = app.activeSwarmId;
    app.adoptSessionForTest(terminal('a0', []));
    app.newSwarm(name: 'Second');
    final second = app.activeSwarmId;
    final projects = SwarmProjectStore();
    await tester.pumpWidget(
      MaterialApp(
        home: SwarmScreen(
          notifier: app,
          nativeTabs: true,
          projectStore: projects,
        ),
      ),
    );
    await tester.pump();
    List<List> inventories() => [
      for (final call in messages)
        if (call.arguments case {'machines': final List machines}) machines,
    ];
    expect((inventories().last.single as Map)['agents'], hasLength(512));
    messages.clear();
    for (var i = 0; i < 3; i++) {
      app.selectSwarm(first);
      await tester.pump();
      app.selectSwarm(second);
      await tester.pump();
    }
    expect(messages.where((call) => call.method == 'update'), isNotEmpty);
    expect(inventories(), isEmpty);

    // Changing one visible name still refreshes the menu, including when the
    // inventory list itself is retained by discovery.
    messages.clear();
    machine.agents[1] = machine.agents[1].copyWith(name: 'Renamed agent');
    app.notifyListeners();
    await tester.pump();
    expect(inventories(), hasLength(1));
    final refreshed = inventories().single.single as Map;
    expect((refreshed['agents'] as List)[1]['title'], 'Renamed agent');
    messages.clear();
    app.notifyListeners();
    await tester.pump();
    expect(inventories(), isEmpty);

    machine.agents[1] = const Agent(id: 'a1', name: 'Renamed agent');
    app.notifyListeners();
    await tester.pump();
    Map renamed() =>
        ((inventories().last.single as Map)['agents'] as List)[1] as Map;
    expect(renamed()['canOpen'], isFalse);
    final retained = app.adoptSessionForTest(terminal('a1', []));
    app.notifyListeners();
    await tester.pump();
    expect(renamed()['canOpen'], isTrue);
    await app.closePane(retained.id);
    await tester.pump();
    expect(renamed()['canOpen'], isFalse);

    await tester.pumpWidget(const SizedBox());
    expect(inventories().last, isEmpty);
    app.dispose();
    projects.dispose();
  });

  testWidgets(
    'machine submenu lists cached agents and opens an exact existing view',
    (tester) async {
      const channel = MethodChannel('harness/swarm_tabs');
      final messenger = tester.binding.defaultBinaryMessenger;
      final messages = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        messages.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final app = createApp();
      final input = <TerminalBinaryFrame>[];
      final original = app.activeSwarmId;
      final pane = app.adoptSessionForTest(terminal('a0', input));
      app.newSwarm(name: 'Second');
      final projects = SwarmProjectStore();
      await tester.pumpWidget(
        MaterialApp(
          home: SwarmScreen(
            notifier: app,
            nativeTabs: true,
            projectStore: projects,
          ),
        ),
      );
      await tester.pump();
      final snapshot =
          messages.lastWhere((c) => c.method == 'machinesState').arguments
              as Map;
      final machine = (snapshot['machines'] as List).single as Map;
      expect(machine['agentCount'], 70);
      final rows = machine['agents'] as List;
      expect(rows.first['id'], 'a0');
      expect(rows.first['title'], 'Agent 0');
      expect(rows.first['canOpen'], isTrue);
      final reply = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('machineAgent', {'machineId': 'm', 'agentId': 'a0'}),
        ),
        (_) => reply.complete(),
      );
      await tester.pumpAndSettle();
      await reply.future;
      expect(app.activeSwarmId, original);
      expect(app.focusedPane, same(pane));
      expect(input, isEmpty);
      final stale = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('machineAgent', {
            'machineId': 'm',
            'agentId': 'removed',
          }),
        ),
        (_) => stale.complete(),
      );
      await tester.pumpAndSettle();
      await stale.future;
      expect(app.focusedPane, same(pane));
      expect(app.swarms, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      projects.dispose();
    },
  );
}
