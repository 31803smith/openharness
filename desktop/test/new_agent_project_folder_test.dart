import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/core/project_folder.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/new_agent_dialog.dart';
import 'package:harness/ws/ws_conn.dart';

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

Future<void> mount(WidgetTester tester, _App app) async {
  await app.agentPreference.select('claude');
  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showNewAgentDialog(context, app, 'm', source: 'test'),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final local in [true, false]) {
    testWidgets('New prepares only on the selected machine (local=$local)', (
      tester,
    ) async {
      final connection = _Connection();
      final app = _App(connection, local: local);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
      await mount(tester, app);
      expect(app.prepared, isEmpty);
      expect(connection.calls, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('new-agent-folder-newProject')),
      );
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
      expect(connection.calls.last.$2.containsKey('projectSource'), isFalse);
      expect(app.prepared.length, local ? 1 : 0);
      connection.fail();
      await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'Remote uses its inline URL and status retries never clone again',
    (tester) async {
      final connection = _Connection();
      final app = _App(connection, local: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
      await mount(tester, app);
      await tester.tap(find.byKey(const ValueKey('new-agent-folder-remote')));
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
