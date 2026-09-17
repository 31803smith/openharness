import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/phone/agent_index.dart';
import 'package:harness_mobile/phone/agent_neighbour_warmer.dart';
import 'package:harness_mobile/phone/agent_swipe.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';
import 'package:harness_mobile/ws/ws_conn.dart';

/// A machine that accepts every terminal frame and remembers what it was sent.
class _Conn extends WsConn {
  _Conn()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'm',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  final List<(String, Map<String, dynamic>)> frames = [];

  List<Map<String, dynamic>> get opens => [
    for (final (type, payload) in frames)
      if (type == 'terminal_open') payload,
  ];

  @override
  Future<bool> sendTerminalFrame(
    String type,
    Map<String, dynamic> payload,
  ) async {
    frames.add((type, payload));
    return true;
  }

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async => {};
}

const _agentIds = ['a', 'b', 'c', 'd'];

AppNotifier _app(_Conn conn, {bool online = true}) {
  final app = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
    connectionForTest: (_) => conn,
  );
  const machine = Machine(
    machineId: 'm',
    authMode: MachineAuthMode.remote,
    name: 'Test host',
  );
  app.machines = [machine];
  app.machineStates['m'] = MachineState(machine)
    ..nodeOnline = online
    ..connectionStatus = ConnectionStatus.connected
    ..agentLoadStatus = AgentLoadStatus.loaded
    ..terminalCapabilityAvailable = true
    ..activeAgentId = 'a'
    ..agents = [
      for (final id in _agentIds)
        Agent(
          id: id,
          name: id,
          engine: 'claude',
          project: const AgentProject(name: 'work', cwd: '/work'),
          terminalAvailable: true,
        ),
    ];
  return app;
}

/// The agent on screen, live at a phone's size.
TerminalSession _live(AppNotifier app, String agentId) {
  final session = TerminalSession(
    machineId: 'm',
    agentId: agentId,
    agentName: agentId,
    engineId: 'claude',
    send: (_, _) async => true,
    sendBinary: (_) async => true,
  );
  app.adoptSessionForTest(session);
  _goLive(session);
  return session;
}

/// What a keyframe arriving does to a session, without a machine to send one: controlling, at the
/// phone's size, and the notifier told — which is the signal the pager waits on.
void _goLive(TerminalSession session) {
  session
    ..status = TerminalSessionStatus.controlling
    ..streamId = 'stream-${session.agentId}'
    ..cols = 46
    ..rows = 38
    ..renameAgent('${session.agentName} (live)');
}

void main() {
  group('preattachAgent', () {
    test('opens the stream at the size given, and selects nothing', () async {
      final conn = _Conn();
      final app = _app(conn);
      addTearDown(app.dispose);
      _live(app, 'a');
      final focused = app.focusedPaneId;

      await app.preattachAgent('m', 'b', cols: 46, rows: 38);

      expect(conn.opens.single['agentId'], 'b');
      expect(conn.opens.single['cols'], 46);
      expect(conn.opens.single['rows'], 38);
      expect(app.paneOfAgent('m', 'b')?.session, isNotNull);
      expect(
        app.focusedPaneId,
        focused,
        reason: 'focus stays on the agent read',
      );
      expect(app.stateOf('m')?.activeAgentId, 'a');
    });

    test('a pane already streaming is left alone', () async {
      final conn = _Conn();
      final app = _app(conn);
      addTearDown(app.dispose);

      await app.preattachAgent('m', 'b', cols: 46, rows: 38);
      await app.preattachAgent('m', 'b', cols: 46, rows: 38);

      expect(conn.opens, hasLength(1));
    });

    test('an agent that cannot be attached gets no pane', () async {
      final conn = _Conn();
      final app = _app(conn, online: false);
      addTearDown(app.dispose);

      await app.preattachAgent('m', 'b', cols: 46, rows: 38);

      expect(app.paneOfAgent('m', 'b'), isNull);
      expect(conn.opens, isEmpty);
    });
  });

  group('the pager', () {
    Future<(AppNotifier, _Conn)> pumpPager(WidgetTester tester) async {
      final conn = _Conn();
      final app = _app(conn);
      addTearDown(app.dispose);
      final list = AgentSwipeList([
        for (final agent in app.stateOf('m')!.agents)
          AgentEntry(machine: app.stateOf('m')!, agent: agent),
      ]);
      _live(app, 'b');
      await tester.pumpWidget(
        MaterialApp(
          home: AgentSwipeHost(
            notifier: app,
            machineId: 'm',
            agentId: 'b',
            neighbours: list,
          ),
        ),
      );
      await tester.pump();
      return (app, conn);
    }

    testWidgets('opens the agents either side once the one on screen is live', (
      tester,
    ) async {
      final (app, conn) = await pumpPager(tester);
      expect(conn.opens, isEmpty, reason: 'not before the landed page settles');

      await tester.pump(AgentNeighbourWarmer.delay);
      await tester.pump();

      expect(
        {for (final open in conn.opens) open['agentId']},
        {'a', 'c'},
        reason: 'the pages one swipe left and one swipe right',
      );
      expect(app.stateOf('m')?.activeAgentId, 'a', reason: 'nothing selected');
    });

    testWidgets('closes what falls out of the window as the pager moves', (
      tester,
    ) async {
      final (app, _) = await pumpPager(tester);
      await tester.pump(AgentNeighbourWarmer.delay);
      await tester.pump();
      expect(app.paneOfAgent('m', 'a'), isNotNull);

      // One swipe right: from b to c, whose neighbours are b and d.
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      // c was warmed; its keyframe lands.
      _goLive(app.paneOfAgent('m', 'c')!.session!);
      await tester.pump(AgentNeighbourWarmer.delay);
      await tester.pump();

      expect(app.paneOfAgent('m', 'a'), isNull, reason: 'two swipes away now');
      expect(app.paneOfAgent('m', 'd')?.session, isNotNull);
    });
  });
}
