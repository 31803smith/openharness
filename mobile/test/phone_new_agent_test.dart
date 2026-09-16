import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/phone/agents_tab.dart';
import 'package:harness_mobile/phone/new_agent_page.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/ws/ws_conn.dart';

/// A machine that answers every question with nothing.
class _Conn extends WsConn {
  _Conn()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'ready',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async => {};
}

/// A machine that is answering, and one that is not.
///
/// The second is the whole point of the picker's filter: an agent cannot be created on a machine
/// that has not listed its folders or named its engines, so it must not be offered as a host.
AppNotifier _app({required bool anyReady}) {
  final app = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
    // The form asks the machine for its engines and Codex profiles as it opens.
    connectionForTest: (_) => _Conn(),
  );
  const ready = Machine(
    machineId: 'ready',
    authMode: MachineAuthMode.remote,
    name: 'Studio',
  );
  const sleeping = Machine(
    machineId: 'sleeping',
    authMode: MachineAuthMode.remote,
    name: 'Laptop',
  );
  app.machines = [ready, sleeping];
  app.machineStates['ready'] = MachineState(ready)
    ..nodeOnline = anyReady
    ..connectionStatus = ConnectionStatus.connected
    ..agentLoadStatus = AgentLoadStatus.loaded;
  // Harness is not running there: offline, whatever the socket says.
  app.machineStates['sleeping'] = MachineState(sleeping)
    ..nodeOnline = false
    ..connectionStatus = ConnectionStatus.connected
    ..agentLoadStatus = AgentLoadStatus.loaded;
  return app;
}

Future<void> _pump(WidgetTester tester, AppNotifier app) async {
  await tester.pumpWidget(MaterialApp(home: AgentsTab(notifier: app)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'the + opens the form on the first machine answering, and offers no other',
    (tester) async {
      final app = _app(anyReady: true);
      addTearDown(app.dispose);
      await _pump(tester, app);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // ⚠️ Scoped to the form. Both machines also name themselves in the
      // filter bar behind it, so an unscoped finder sees every machine twice
      // and reads the offline one as offered when it is not.
      Finder inForm(String text) => find.descendant(
        of: find.byType(NewAgentPage),
        matching: find.text(text),
      );

      expect(inForm('Studio'), findsOneWidget);
      expect(
        inForm('Laptop'),
        findsNothing,
        reason: 'an offline machine cannot host a new agent',
      );
    },
  );

  testWidgets('no + at all while nothing can host an agent', (tester) async {
    final app = _app(anyReady: false);
    addTearDown(app.dispose);
    await _pump(tester, app);

    // Absent, not disabled: the empty state already says to open the Machines
    // tab, and a button whose only outcome is that same explanation is worse
    // than no button.
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
