import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/terminal_pane.dart';
import 'package:harness/ws/ws_conn.dart';

const _machine = Machine(
  machineId: 'm',
  name: 'Fixture computer',
  authMode: MachineAuthMode.remote,
  status: 'online',
);

const _agents = {
  'agents': [
    {
      'id': 'a',
      'name': 'Fixture agent',
      'engine': 'codex',
      'terminal': {
        'runtimes': [
          {'backend': 'tmux', 'paneId': '%1'},
        ],
      },
    },
  ],
};
const _capabilities = {
  'protocolVersion': 3,
  'backend': 'tmux',
  'available': true,
};

class _Connection extends WsConn {
  _Connection()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'm',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  final calls = <String>[];
  final agents = <Completer<Map<String, dynamic>>>[];
  final capabilities = <Completer<Map<String, dynamic>>>[];
  final timeouts = <String, Duration>{};
  final sent = <String>[];
  Completer<void>? readiness;

  @override
  Future<void> waitUntilReady({required Duration timeout}) async {
    await readiness?.future;
  }

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) {
    calls.add(type);
    timeouts[type] = timeout;
    final response = Completer<Map<String, dynamic>>();
    switch (type) {
      case 'agents_list':
        agents.add(response);
      case 'terminal_capabilities':
        capabilities.add(response);
      default:
        throw StateError('Unexpected request: $type');
    }
    return response.future;
  }

  @override
  Future<bool> sendTerminalFrame(
    String type,
    Map<String, dynamic> payload,
  ) async {
    sent.add(type);
    return true;
  }
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppNotifier app;
  late MachineState machine;
  late _Connection connection;

  setUp(() {
    connection = _Connection();
    app = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      connectionForTest: (_) => connection,
    )..status = AppStatus.authenticated;
    machine = MachineState(_machine)..nodeOnline = true;
    app.machines = [_machine];
    app.machineStates['m'] = machine;
  });
  tearDown(() => app.dispose());

  test('agent inventory and capabilities are requested together', () async {
    final load = app.reloadMachineData('m');
    await _tick();
    final capabilitiesStarted = connection.capabilities.isNotEmpty;
    connection.agents.single.complete(_agents);
    await _tick();
    connection.capabilities.single.complete(_capabilities);
    await load;
    expect(capabilitiesStarted, isTrue);
    expect(machine.agents.single.id, 'a');
    expect(machine.terminalCapabilityAvailable, isTrue);
  });

  test('agents become visible before a slow capability response', () async {
    var sawAgents = false;
    app.addListener(() {
      if (machine.agents.isNotEmpty) sawAgents = true;
    });
    final load = app.reloadMachineData('m');
    await _tick();
    connection.agents.single.complete(_agents);
    await _tick();
    final visibleBeforeCapabilities = sawAgents;
    connection.capabilities.single.complete(_capabilities);
    await load;
    expect(visibleBeforeCapabilities, isTrue);
    expect(machine.agentLoadStatus, AgentLoadStatus.loaded);
  });

  test('handshake time stays inside the existing inventory budget', () async {
    connection.readiness = Completer<void>();
    final load = app.reloadMachineData('m');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(connection.calls, isEmpty);
    connection.readiness!.complete();
    await _tick();
    expect(connection.calls, ['terminal_capabilities', 'agents_list']);
    expect(
      connection.timeouts['agents_list']!,
      lessThan(const Duration(seconds: 10)),
    );
    expect(connection.timeouts['agents_list']!, greaterThan(Duration.zero));
    expect(
      connection.timeouts['terminal_capabilities'],
      const Duration(seconds: 8),
    );
    connection.agents.single.complete(_agents);
    connection.capabilities.single.complete(_capabilities);
    await load;
  });

  test('repeated reloads share both pending discovery requests', () async {
    final first = app.reloadMachineData('m');
    final second = app.reloadMachineData('m');
    await _tick();
    expect(connection.agents, hasLength(1));
    expect(connection.capabilities, hasLength(1));
    connection.agents.single.complete(_agents);
    connection.capabilities.single.complete(_capabilities);
    await Future.wait([first, second]);
    expect(machine.agentsLoadInFlight, isNull);
    expect(machine.terminalCapabilityLoadInFlight, isNull);
  });

  for (final agentsFirst in [true, false]) {
    test(
      'restored agent attaches once with ${agentsFirst ? 'agents' : 'capabilities'} first',
      () async {
        final pane = TerminalPane(id: 99, machineId: 'm', agentId: 'a');
        app.activeSwarm.panes.add(pane);
        final focus = app.focusedPaneId;
        final load = app.reloadMachineData('m');
        await _tick();
        if (agentsFirst) {
          connection.agents.single.complete(_agents);
        } else {
          connection.capabilities.single.complete(_capabilities);
        }
        await _tick();
        expect(pane.session, isNull);
        if (agentsFirst) {
          connection.capabilities.single.complete(_capabilities);
        } else {
          connection.agents.single.complete(_agents);
        }
        await load;
        await _tick();
        expect(pane.session, isNotNull);
        pane.session!.reportViewport(100, 30);
        await _tick();
        expect(
          connection.sent.where((type) => type == 'terminal_open'),
          hasLength(1),
        );
        expect(app.focusedPaneId, focus);
        expect(app.panes.single, same(pane));
      },
    );
  }

  test('unavailable capabilities leave discovered agents visible without attaching', () async {
    final pane = TerminalPane(id: 99, machineId: 'm', agentId: 'a');
    app.activeSwarm.panes.add(pane);
    final load = app.reloadMachineData('m');
    await _tick();
    connection.capabilities.single.completeError(StateError('Unsupported'));
    connection.agents.single.complete(_agents);
    await load;
    expect(machine.agents.single.id, 'a');
    expect(machine.agentLoadStatus, AgentLoadStatus.loaded);
    expect(machine.terminalCapabilityAvailable, isFalse);
    expect(machine.terminalCapabilityError, isNotNull);
    expect(pane.session, isNull);
    expect(connection.sent, isEmpty);
  });

  test(
    'inventory failure can retry while sharing the pending capability request',
    () async {
      final failed = app.reloadMachineData('m');
      await _tick();
      connection.agents.single.completeError(
        StateError('Inventory unavailable'),
      );
      await failed;
      expect(machine.agentsLoadError, contains('Inventory unavailable'));
      final retry = app.reloadMachineData('m');
      await _tick();
      expect(connection.capabilities, hasLength(1));
      expect(connection.agents, hasLength(2));
      connection.capabilities.single.complete(_capabilities);
      connection.agents.last.complete(_agents);
      await retry;
      expect(machine.agentsLoadError, isNull);
      expect(machine.terminalCapabilityAvailable, isTrue);
    },
  );

  test('a removed machine cannot send requests after late readiness', () async {
    connection.readiness = Completer<void>();
    final load = app.reloadMachineData('m');
    await _tick();
    app.machineStates.clear();
    connection.readiness!.complete();
    await load;
    expect(connection.calls, isEmpty);
    expect(app.panes, isEmpty);
  });
}
