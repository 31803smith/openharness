import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/core/project_folder.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/widgets/new_agent_dialog.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show terminal;

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
  final calls =
      <(String, Map<String, dynamic>, Completer<Map<String, dynamic>>)>[];
  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) {
    if (type != 'agent_create' && type != 'agent_create_status') {
      return Future.value(<String, dynamic>{});
    }
    final result = Completer<Map<String, dynamic>>();
    calls.add((type, payload, result));
    return result.future;
  }

  void fail({String? folder}) {
    final (_, payload, result) = calls.last;
    result.complete({
      'creationId': payload['creationId'],
      'state': 'failed',
      'preparedFolder': ?folder,
      'failure': {'code': 'TMUX_UNAVAILABLE'},
    });
  }
}

class _App extends AppNotifier {
  _App(_Connection connection, {required bool local})
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        connectionForTest: (_) => connection,
      ) {
    const machine = Machine(
      machineId: 'm',
      name: 'Studio',
      authMode: MachineAuthMode.remote,
    );
    machineStates['m'] = MachineState(machine)..localOnly = local;
  }
  final prepared = <ProjectFolderRequest>[];
  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}
  @override
  Future<String> prepareLocalProjectFolder(ProjectFolderRequest request) async {
    prepared.add(request);
    return '/local/Harness Projects/project-test';
  }
}

Future<void> _mount(
  WidgetTester tester,
  _App app, {
  bool composer = false,
}) async {
  await app.agentPreference.select('claude');
  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: composer
            ? Center(
                child: SizedBox(
                  width: 760,
                  child: NewAgentComposer(
                    notifier: app,
                    machineId: 'm',
                    swarmId: app.activeSwarmId,
                    onFinished: () {},
                    onBusyChanged: (_) {},
                    onDismiss: () {},
                  ),
                ),
              )
            : Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showNewAgentDialog(context, app, 'm', source: 'test'),
                  child: const Text('Open'),
                ),
              ),
      ),
    ),
  );
  if (!composer) await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final inline in [false, true]) {
    testWidgets(
      'shared creation preserves its destination and blocks duplicate launch (inline=$inline)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1200, 900);
        addTearDown(tester.view.reset);
        final connection = _Connection();
        final app = _App(connection, local: true);
        await app.agentPreference.select('claude');
        if (!inline) app.adoptSessionForTest(terminal('a0', []));
        final original = app.activeSwarmId;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          app.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            home: SwarmScreen(notifier: app, nativeTabs: false),
          ),
        );
        if (!inline) await chord(tester, LogicalKeyboardKey.keyR);
        await tester.pumpAndSettle();
        final composer = find.byType(NewAgentComposer);
        final split = tester.widget<NewAgentComposer>(composer).split;
        expect(split, inline ? isNull : isNotNull);
        expect(tester.widget<NewAgentComposer>(composer).swarmId, original);
        final submit = find.byKey(const ValueKey('create-agent-submit'));
        await tester.tap(submit);
        await tester.pump();
        expect(connection.calls, hasLength(1));
        final creationId = connection.calls.single.$2['creationId'];
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await chord(tester, LogicalKeyboardKey.keyT);
        await tester.tapAt(const Offset(10, 400));
        await tester.pump();
        expect(composer, findsOneWidget);
        expect(app.activeSwarmId, original);
        expect(tester.widget<NewAgentComposer>(composer).split, same(split));
        expect(connection.calls, hasLength(1));
        connection.calls.single.$3.completeError(
          const WsRequestTimeout('agent_create'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Check status'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(composer, findsOneWidget);
        await tester.tap(submit);
        await tester.pump();
        expect(connection.calls.last.$1, 'agent_create_status');
        expect(connection.calls.last.$2, {'creationId': creationId});
        connection.calls.last.$3.complete({
          'creationId': creationId,
          'state': 'created',
          'agent': {
            'id': 'created',
            'name': 'Created agent',
            'engine': 'claude',
          },
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(composer, findsNothing);
        expect(app.activeSwarmId, original);
        expect(app.panes, hasLength(inline ? 1 : 2));
        expect(app.focusedPane?.agentId, 'created');
      },
    );
  }

  for (final composer in [false, true]) {
    for (final local in [true, false]) {
      testWidgets(
        'New prepares only on the selected machine (local=$local, composer=$composer)',
        (tester) async {
          final connection = _Connection();
          final app = _App(connection, local: local);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            app.dispose();
          });
          await _mount(tester, app, composer: composer);
          expect(app.prepared, isEmpty);
          expect(connection.calls, isEmpty);
          if (!composer) {
            await tester.tap(
              find.byKey(const ValueKey('new-agent-folder-newProject')),
            );
          } else {
            expect(find.text('New project'), findsOneWidget);
          }
          await tester.pumpAndSettle();
          expect(
            app.prepared,
            isEmpty,
            reason: 'Selecting New does not create folders',
          );
          await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
          await tester.pump();
          final (_, payload, _) = connection.calls.single;
          if (local) {
            expect(app.prepared, hasLength(1));
            expect(payload['cwd'], '/local/Harness Projects/project-test');
            expect(
              payload.containsKey('projectSource'),
              isFalse,
              reason: 'Current local CLIs retain the existing cwd protocol',
            );
          } else {
            expect(app.prepared, isEmpty);
            expect(payload['projectSource'], 'new');
            expect(
              payload.containsKey('cwd'),
              isFalse,
              reason: 'An older remote CLI must refuse instead of starting in the wrong folder',
            );
          }
          connection.fail(
            folder: local ? null : '/remote/Harness Projects/project-test',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
          await tester.pump();
          expect(
            connection.calls.last.$2['cwd'],
            '${local ? '/local' : '/remote'}/Harness Projects/project-test',
          );
          expect(
            connection.calls.last.$2.containsKey('projectSource'),
            isFalse,
          );
          expect(app.prepared.length, local ? 1 : 0);
          connection.fail();
          await tester.pumpAndSettle();
        },
      );
    }

    testWidgets(
      'Remote keeps its URL and status retries never clone again (composer=$composer)',
      (tester) async {
        final connection = _Connection();
        final app = _App(connection, local: false);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          app.dispose();
        });
        await _mount(tester, app, composer: composer);
        if (composer) {
          await tester.tap(
            find.byKey(const ValueKey('agent-composer-project')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remote repository…'));
        } else {
          await tester.tap(
            find.byKey(const ValueKey('new-agent-folder-remote')),
          );
        }
        await tester.pumpAndSettle();
        final field = find.byKey(const ValueKey('new-agent-repository'));
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('create-agent-submit')),
              )
              .onPressed,
          isNull,
        );
        await tester.enterText(field, 'owner/repo');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
        await tester.pump();
        final (_, payload, result) = connection.calls.single;
        expect(payload['projectSource'], 'remote');
        expect(payload['repositoryUrl'], 'https://github.com/owner/repo.git');
        expect(app.prepared, isEmpty);
        result.completeError(const WsRequestTimeout('agent_create'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
        await tester.pump();
        expect(connection.calls.last.$1, 'agent_create_status');
        expect(connection.calls.last.$2, {'creationId': payload['creationId']});
        connection.fail();
        await tester.pumpAndSettle();
      },
    );
  }
}
