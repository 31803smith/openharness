import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/settings/settings_screen.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:xterm/xterm.dart';

import 'swarm_screen_test.dart' show terminal;
import 'swarm_state_test.dart' show createApp;
import 'swarm_switcher_test.dart' show jumpField;

void main() {
  test(
    'recent menus retain snapshots through output and refresh live identities',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final history = SwarmNavigationHistory();
      app.addListener(() => history.record(app));
      final first = app.adoptSessionForTest(terminal('a0', []));
      history.record(app);
      app.adoptSessionForTest(terminal('a1', []));
      history.record(app);
      final before = history.menuDestinations(app);
      expect(before.first.agentId, 'a1');
      for (var i = 0; i < 100; i++) {
        app.dismissError();
        expect(history.menuDestinations(app), same(before));
      }
      app.machineStates['m']!.agents = [
        const Agent(id: 'a0', name: 'Renamed agent', terminalAvailable: true),
        const Agent(id: 'a1', name: 'Agent 1', terminalAvailable: true),
      ];
      app.renameSwarm(app.activeSwarmId, 'Renamed Swarm');
      final renamed = history.menuDestinations(app);
      expect(
        renamed.firstWhere((e) => e.agentId == 'a0').title,
        'Renamed agent',
      );
      expect(renamed.firstWhere((e) => e.isSwarm).title, 'Renamed Swarm');
      app.machineStates['m']!.nodeOnline = false;
      expect(history.menuDestinations(app).first.detail, contains('Offline'));
      await app.closePane(first.id);
      expect(
        history.menuDestinations(app).where((e) => e.agentId == 'a0'),
        isEmpty,
      );
      expect(history.recent, contains(agentDestinationId('m', 'a0')));
    },
  );

  testWidgets(
    'native History focuses its agent, refuses stale entries and respects Settings',
    (tester) async {
      const channel = MethodChannel('harness/swarm_tabs');
      final messenger = tester.binding.defaultBinaryMessenger;
      final updates = <Map>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'update') updates.add(call.arguments as Map);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      Future<void> native(String method, [Map<String, Object?>? args]) {
        final done = Completer<void>();
        messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, args),
          ),
          (_) => done.complete(),
        );
        return done.future;
      }

      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final input = <TerminalBinaryFrame>[];
      final firstSession = terminal('a0', input);
      final first = app.adoptSessionForTest(firstSession);
      final otherInput = <TerminalBinaryFrame>[];
      final second = app.adoptSessionForTest(terminal('a1', otherInput));
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
      app.focusPane(first.id);
      app.focusPane(second.id);
      await tester.pump();
      final id = agentDestinationId('m', 'a0');
      final row = (updates.last['history'] as List).cast<Map>().firstWhere(
        (row) => row['id'] == id,
      );
      expect(row['title'], 'Agent 0 — Test host');
      final before = updates.length;
      for (var i = 0; i < 20; i++) {
        app.dismissError();
      }
      await tester.pump();
      expect(
        updates.length,
        before,
        reason: 'Output/state churn emits no unchanged native menu update',
      );
      await native('historyDestination', {'id': id});
      await tester.pump();
      expect(app.focusedPaneId, first.id);
      final focused = tester.widget<TerminalView>(
        find.byWidgetPredicate(
          (w) =>
              w is TerminalView && identical(w.terminal, firstSession.terminal),
        ),
      );
      expect(focused.focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
      expect(input.single.bytes, [27, 91, 68]);
      expect(otherInput, isEmpty);

      final settings = native('settings');
      await tester.pump();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await native('historyDestination', {'id': agentDestinationId('m', 'a1')});
      await native('jump');
      await native('newAgent');
      await native('linkMachine');
      await native('addProject');
      expect(app.focusedPaneId, first.id);
      expect(jumpField, findsNothing);
      Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
      await tester.pump();
      await settings;

      // Native Command-P reaches the same picker even when the terminal owns focus.
      final jumping = native('jump');
      await tester.pump();
      expect(jumpField, findsOneWidget);
      await tester.enterText(jumpField, 'Agent 1');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await jumping;
      expect(app.focusedPaneId, second.id);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
      expect(otherInput.single.bytes, [27, 91, 68]);

      await app.closePane(first.id);
      await tester.pump();
      await native('historyDestination', {'id': id});
      await tester.pump();
      expect(app.panes, [
        second,
      ], reason: 'Stale history cannot recreate a closed view');
      expect(app.focusedPaneId, second.id);
      await tester.pumpWidget(const SizedBox());
      projects.dispose();
      app.dispose();
    },
  );
}
