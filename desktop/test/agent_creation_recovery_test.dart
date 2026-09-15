import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/stats/harness_stats.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/new_agent_dialog.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_state_test.dart' show createApp;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_interactions_test.dart' show chord;

class _FolderPicker extends FileSelectorPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => '/work';
}

class _Request {
  _Request(this.type, this.payload);
  final String type;
  final Map<String, dynamic> payload;
  final reply = Completer<Map<String, dynamic>>();
  String get creationId => payload['creationId'] as String;
  void status(String state, {Map<String, dynamic>? agent}) => reply.complete({
    'creationId': creationId,
    'state': state,
    'agent': ?agent,
  });
  void created([String id = 'created']) => status(
    'created',
    agent: {'id': id, 'name': 'Recovered agent', 'engine': 'claude'},
  );
}

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
  final calls = <_Request>[];
  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) {
    if (type == 'engines_probe') return Future.value({'engines': []});
    if (type == 'codex_profiles_list') return Future.value({'profiles': []});
    final request = _Request(type, Map.of(payload));
    calls.add(request);
    return request.reply.future;
  }
}

Future<void> _timeOut(
  AppNotifier app,
  _Connection connection,
  AgentCreationAttempt attempt,
) async {
  final create = app.createAgent(
    'm',
    engine: 'claude',
    folder: '/work',
    attempt: attempt,
  );
  connection.calls.last.reply.completeError(
    const WsRequestTimeout('agent_create'),
  );
  expect(await create, contains('Check status'));
  expect(attempt.awaitingConfirmation, isTrue);
}

void main() {
  for (final change in [
    'unchanged',
    'welcome',
    'switch',
    'closed',
    'split',
    'stale split',
  ]) {
    testWidgets('find an uncertain creation through Add after $change', (
      tester,
    ) async {
      final files = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FolderPicker();
      addTearDown(() => FileSelectorPlatform.instance = files);
      final connection = _Connection();
      final app = createApp(connectionForTest: (_) => connection);
      app.stateOf('m')!.localOnly = true;
      final input = <TerminalBinaryFrame>[];
      final welcome = change == 'welcome';
      if (!welcome) app.adoptSessionForTest(terminal('a0', input));
      await mount(tester, app);
      tester.view.physicalSize = const Size(2000, 1200);
      await tester.pump();
      final original = app.activeSwarm;
      final splitting = change.contains('split');
      final search = find.byKey(const ValueKey('swarm-search-input'));
      final queryInput = welcome
          ? find.byKey(const ValueKey('swarm-welcome-search-input'))
          : search;
      if (splitting) {
        await chord(tester, LogicalKeyboardKey.keyP);
        await tester.enterText(search, '> split right');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
      } else if (!welcome) {
        await chord(tester, LogicalKeyboardKey.keyN);
      }
      await tester.enterText(queryInput, 'Agent 12');
      await tester.pump();
      if (welcome) {
        await chord(tester, LogicalKeyboardKey.keyN, shift: true);
      } else {
        await tester.tap(find.byKey(const ValueKey('swarm-search-new-agent')));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-agent-folder')));
      await tester.pumpAndSettle();
      expect(find.text('Find existing agent…'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
      await tester.pump();
      expect(find.text('Find existing agent…'), findsNothing);
      connection.calls.last.reply.completeError(
        const WsRequestTimeout('agent_create'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Find existing agent…'), findsOneWidget);
      if (change == 'switch' || change == 'closed') app.newSwarm();
      if (change == 'closed') await app.closeSwarm(original.id);
      if (change == 'stale split') {
        app.adoptSessionForTest(terminal('a1', input));
      }
      await tester.pump();
      // Check status owns focus after the timeout; Shift-Tab reaches the
      // alternative without sending the key or Enter to the terminal.
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Check status'),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      if (change == 'closed' || change == 'stale split') {
        expect(search, findsNothing);
        expect(
          find.textContaining(
            change == 'closed' ? 'swarm was closed' : 'split changed',
          ),
          findsOneWidget,
        );
        expect(original.panes.any((p) => p.agentId == 'a12'), isFalse);
      } else {
        final field = tester.widget<TextField>(search);
        expect(field.controller!.text, 'Agent 12');
        expect(field.focusNode!.hasFocus, isTrue);
        expect(app.activeSwarmId, original.id);
        expect(original.panes.map((p) => p.agentId), welcome ? [] : ['a0']);
        if (splitting) expect(find.text('Split right'), findsNWidgets(2));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          original.panes.map((p) => p.agentId),
          welcome ? ['a12'] : ['a0', 'a12'],
        );
        if (splitting) expect(original.manualLayout, isNotNull);
      }
      expect(connection.calls.map((c) => c.type), ['agent_create']);
      expect(input, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }

  test(
    'lost creation reply recovers into the original swarm and counts once',
    () async {
      final connection = _Connection();
      final app = createApp(connectionForTest: (_) => connection);
      addTearDown(app.dispose);
      final destination = app.activeSwarm;
      final attempt = AgentCreationAttempt();
      final before = harnessStats.summary.agentsSpawned;
      await _timeOut(app, connection, attempt);
      app.newSwarm(name: 'Another task');
      final recover = app.createAgent(
        'm',
        engine: 'claude',
        folder: '/work',
        attempt: attempt,
      );
      expect(connection.calls.last.type, 'agent_create_status');
      expect(
        connection.calls.last.creationId,
        connection.calls.first.creationId,
      );
      connection.calls.last.created();
      expect(await recover, isNull);
      expect(attempt.awaitingConfirmation, isFalse);
      expect(destination.panes.single.agentId, 'created');
      expect(app.activeSwarm.panes, isEmpty);
      expect(harnessStats.summary.agentsSpawned, before + 1);
      // Reusing the completed intent does not count or apply it a second time.
      expect(
        await app.createAgent(
          'm',
          engine: 'claude',
          folder: '/work',
          attempt: attempt,
        ),
        isNull,
      );
      expect(connection.calls, hasLength(2));
      expect(harnessStats.summary.agentsSpawned, before + 1);
    },
  );

  test('concurrent submits share one request; a deliberate fresh intent gets a new id', () async {
    final connection = _Connection();
    final app = createApp(connectionForTest: (_) => connection);
    addTearDown(app.dispose);
    final attempt = AgentCreationAttempt();
    final first = app.createAgent(
      'm',
      engine: 'claude',
      folder: '/work',
      attempt: attempt,
    );
    final duplicate = app.createAgent(
      'm',
      engine: 'claude',
      folder: '/work',
      attempt: attempt,
    );
    expect(connection.calls, hasLength(1));
    connection.calls.single.created();
    expect(await first, isNull);
    expect(await duplicate, isNull);
    final fresh = app.createAgent(
      'm',
      engine: 'claude',
      folder: '/work',
      attempt: AgentCreationAttempt(),
    );
    expect(
      connection.calls.last.creationId,
      isNot(connection.calls.first.creationId),
    );
    connection.calls.last.created('new-intent');
    expect(await fresh, isNull);
  });

  for (final result in [
    'unsupported',
    'timeout',
    'disconnect',
    'pending',
    'unconfirmed',
    'missing',
    'wrong receipt',
    'malformed',
  ]) {
    test('$result never turns a status check into another launch', () async {
      final connection = _Connection();
      final app = createApp(connectionForTest: (_) => connection);
      addTearDown(app.dispose);
      final attempt = AgentCreationAttempt();
      await _timeOut(app, connection, attempt);
      final recover = app.createAgent(
        'm',
        engine: 'claude',
        folder: '/work',
        attempt: attempt,
      );
      final check = connection.calls.last;
      switch (result) {
        case 'unsupported':
          check.reply.completeError(
            const WsRequestFailure(
              responseType: 'agent_create_status_result',
              code: 'UNSUPPORTED',
            ),
          );
        case 'timeout':
          check.reply.completeError(
            const WsRequestTimeout('agent_create_status'),
          );
        case 'disconnect':
          check.reply.completeError(StateError('fixture disconnected'));
        case 'wrong receipt':
          check.reply.complete({
            'creationId': 'not-this-creation',
            'state': 'missing',
          });
        case 'malformed':
          check.status('created', agent: {});
        default:
          check.status(result);
      }
      expect(await recover, isNotNull);
      expect(attempt.awaitingConfirmation, isTrue);
      expect(connection.calls.map((c) => c.type), [
        'agent_create',
        'agent_create_status',
      ]);
      expect(app.panes, isEmpty);
    });
  }

  test(
    'changing launch choices cannot redirect an uncertain request',
    () async {
      final connection = _Connection();
      final app = createApp(connectionForTest: (_) => connection);
      addTearDown(app.dispose);
      final attempt = AgentCreationAttempt();
      await _timeOut(app, connection, attempt);
      expect(
        await app.createAgent(
          'm',
          engine: 'codex',
          folder: '/different',
          attempt: attempt,
        ),
        contains('original request'),
      );
      expect(connection.calls, hasLength(1));
      expect(attempt.awaitingConfirmation, isTrue);
    },
  );

  for (final state in ['failed', 'unavailable']) {
    test(
      'a recorded $state outcome ends recovery without another launch',
      () async {
        final connection = _Connection();
        final app = createApp(connectionForTest: (_) => connection);
        addTearDown(app.dispose);
        final attempt = AgentCreationAttempt();
        await _timeOut(app, connection, attempt);
        final recover = app.createAgent(
          'm',
          engine: 'claude',
          folder: '/work',
          attempt: attempt,
        );
        final request = connection.calls.last;
        request.reply.complete({
          'creationId': request.creationId,
          'state': state,
          'failure': {'code': 'CWD_NOT_FOUND'},
        });
        expect(
          await recover,
          contains(
            state == 'failed' ? 'Choose another folder' : 'no longer available',
          ),
        );
        expect(attempt.awaitingConfirmation, isFalse);
        expect(connection.calls, hasLength(2));
      },
    );
  }

  test('closing the original swarm does not block recovery or add into a different swarm', () async {
    final connection = _Connection();
    final app = createApp(connectionForTest: (_) => connection);
    addTearDown(app.dispose);
    final original = app.activeSwarmId;
    final attempt = AgentCreationAttempt();
    await _timeOut(app, connection, attempt);
    app.newSwarm(name: 'Other');
    await app.closeSwarm(original);
    final recover = app.createAgent(
      'm',
      engine: 'claude',
      folder: '/work',
      attempt: attempt,
    );
    connection.calls.last.created();
    expect(await recover, isNull);
    expect(app.panes, isEmpty);
    expect(
      app.stateOf('m')!.agents.any((agent) => agent.id == 'created'),
      isTrue,
    );
    expect(app.lastError, contains('Find it with Add agent'));
  });

  testWidgets(
    'timeout keeps choices and keyboard focus on Check status, then opens the recovered agent',
    (tester) async {
      final connection = _Connection();
      final app = createApp(connectionForTest: (_) => connection);
      app.stateOf('m')!.localOnly = true;
      await tester.binding.setSurfaceSize(const Size(960, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showNewAgentDialog(
                  context,
                  app,
                  'm',
                  source: 'test',
                  initialFolder: '/work',
                  initialEngineProbe: Future.value(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
      await tester.pump();
      connection.calls.last.reply.completeError(
        const WsRequestTimeout('agent_create'),
      );
      await tester.pumpAndSettle();
      expect(find.text('/work'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Create agent'), findsNothing);
      final action = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Check status'),
      );
      expect(action.focusNode!.hasFocus, isTrue);
      expect(find.text('Close'), findsOneWidget);
      // The original settings remain locked while the request is uncertain.
      await tester.tap(find.text('Codex'), warnIfMissed: false);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(connection.calls.map((c) => c.type), [
        'agent_create',
        'agent_create_status',
      ]);
      connection.calls.last.created();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.panes.single.agentId, 'created');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
