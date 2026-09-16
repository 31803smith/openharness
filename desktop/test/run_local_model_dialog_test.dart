// The Run a local model dialog and the one action behind it: the copy, the machine line, the
// prerequisites that replace it, and what Start actually sends.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/models.dart';
import 'package:harness/settings/config_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/ws/ws_conn.dart';

class _MemoryStore implements LocalKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// A connection that answers the dialog's three reads and the create at once. Without it the
/// dialog would wait out each request's own timeout, and `pumpAndSettle` would be measuring those
/// rather than the dialog. Anything else asked of it (a terminal open after the create, say) is
/// left pending, which is what a machine that has not answered yet looks like.
class _Conn extends WsConn {
  _Conn({required this.engines, required this.gridName})
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'local',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  final List<Map<String, Object?>> engines;
  final String? gridName;

  /// Every `agent_create` payload, verbatim — the wire is what the plan specifies.
  final creates = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) {
    switch (type) {
      case 'engines_probe':
        return Future.value({'engines': engines});
      case 'grid_models_list':
        return Future.value({'gridName': gridName, 'models': <Object?>[]});
      case 'fs_list_dir':
        return Future.value({
          'path': '/home/remote',
          'entries': <Object?>[],
          'truncated': false,
        });
      case 'agent_create':
        creates.add(Map.of(payload));
        return Future.value({
          'creationId': payload['creationId'],
          'state': 'created',
          'agent': {
            'id': 'lm1',
            'name': 'Local models manager',
            'engine': 'opencode',
          },
        });
      default:
        return Completer<Map<String, dynamic>>().future;
    }
  }
}

const _installed = [
  {'engine': 'opencode', 'installed': true},
];

void main() {
  late AppNotifier notifier;
  late _Conn conn;

  void build({
    List<Map<String, Object?>> engines = _installed,
    String? gridName = 'someone-7f3a91c4',
    ConfigStore? configStore,
    bool local = true,
  }) {
    conn = _Conn(engines: engines, gridName: gridName);
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: configStore,
      connectionForTest: (_) => conn,
    )..hasNavigationRail = false;
    const machine = Machine(
      machineId: 'local',
      authMode: MachineAuthMode.remote,
      name: 'studio-7',
    );
    notifier.machines = [machine];
    notifier.machineStates['local'] = MachineState(machine)
      ..localOnly = local
      ..agentLoadStatus = AgentLoadStatus.loaded;
    if (!local) notifier.selectedMachineId = 'local';
  }

  setUp(() => build());
  tearDown(() => notifier.dispose());

  /// Mounts a door — one button that calls the action every real door calls — and presses it.
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const Key('door'),
                onPressed: () => notifier.runLocalModel(context),
                child: const Text('Run a local model'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();
  }

  final start = find.byKey(const Key('run-local-model-start'));
  final status = find.byKey(const Key('run-local-model-status'));
  String statusText(WidgetTester tester) => tester.widget<Text>(status).data!;
  bool startEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(start).onPressed != null;

  testWidgets('the copy is the plan\'s, and names no plumbing', (tester) async {
    await open(tester);

    expect(find.text('A model that lives on your machine'), findsOneWidget);
    expect(
      find.text(
        "Say what you'll use it for. Harness picks one that fits this computer, brings it down, "
        "and starts it. Once it's running, switch to it in any agent you want, right from that "
        "agent's model picker.",
      ),
      findsOneWidget,
    );
    expect(find.text("Don't show this again"), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    // The product's two rules for this dialog: never the CLI's name, never one vendor's noun for
    // a computer. The app runs on Linux too.
    expect(find.textContaining('grid'), findsNothing);
    expect(find.textContaining('this Mac'), findsNothing);
    expect(find.textContaining('!'), findsNothing);
    // No dashes of any kind in the copy: the owner's rule for this dialog.
    expect(find.textContaining('—'), findsNothing);
    expect(find.textContaining('–'), findsNothing);
    // Nothing about the machine when nothing is missing: the body is the whole message.
    expect(status, findsNothing);
  });

  testWidgets('missing opencode is said, and disables Start', (tester) async {
    build(
      engines: const [
        {'engine': 'opencode', 'installed': false},
      ],
    );
    await open(tester);

    expect(statusText(tester), 'Needs opencode on this machine first.');
    expect(find.textContaining('studio-7'), findsNothing);
    expect(startEnabled(tester), isFalse);
    await tester.tap(start, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(conn.creates, isEmpty);
  });

  testWidgets('no private grid yet sends the person back to sign in', (
    tester,
  ) async {
    // `gridName: null` is the daemon saying the backend has not minted one, which a new sign-in
    // fixes; the sentence says that and, like the picker, never says "grid".
    build(gridName: null);
    await open(tester);

    expect(statusText(tester), 'Sign in to Harness again to set this up.');
    expect(find.textContaining('grid'), findsNothing);
    expect(startEnabled(tester), isFalse);
  });

  testWidgets('Not now creates nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('run-local-model-not-now')));
    await tester.pumpAndSettle();

    expect(find.text('A model that lives on your machine'), findsNothing);
    expect(conn.creates, isEmpty);
    expect(notifier.panes, isEmpty);
  });

  testWidgets(
    'Start opens opencode in the home folder as the harness-compute agent, named',
    (tester) async {
      await open(tester);
      await tester.tap(start);
      await tester.pumpAndSettle();

      expect(find.text('A model that lives on your machine'), findsNothing);
      final payload = conn.creates.single;
      expect(payload['engine'], 'opencode');
      // The pane IS the agent (`opencode --agent harness-compute`), and is titled before opencode
      // reports a session title.
      expect(payload['agent'], 'harness-compute');
      expect(payload['name'], 'Local models manager');
      // No first message: the person opens the conversation, and the dialog says so.
      expect(payload.containsKey('prompt'), isFalse);
      // Home, not a project: a local model is not about any one repo.
      expect(payload['cwd'], Platform.environment['HOME']);
      expect(payload.containsKey('dsh'), isFalse);
      // The pane appearing IS the confirmation — created, placed and focused the way New Agent does.
      expect(notifier.panes.single.agentId, 'lm1');
      expect(notifier.focusedPane?.agentId, 'lm1');
    },
  );

  testWidgets('an ordinary create sends neither prompt, name nor agent', (
    tester,
  ) async {
    // A daemon that knows the fields refuses a prompt or an agent for an engine with no way to
    // take one, so the fields must be ABSENT — not empty — on every create that did not ask.
    await notifier.createAgent('local', engine: 'claude', folder: '/work');
    final payload = conn.creates.single;
    expect(payload.containsKey('prompt'), isFalse);
    expect(payload.containsKey('name'), isFalse);
    expect(payload.containsKey('agent'), isFalse);
  });

  testWidgets('the tick is remembered, and the next entry skips the dialog', (
    tester,
  ) async {
    final storage = _MemoryStore();
    build(configStore: ConfigStore(storage: storage));
    await open(tester);
    await tester.tap(find.byKey(const Key('run-local-model-skip')));
    await tester.pump();
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(conn.creates, hasLength(1));

    // Persisted under the plan's key, and read back by a fresh store — the choice is about the
    // person, and it has to survive a relaunch to be one.
    expect(storage.values['runLocalModel.skipDialog'], 'true');
    final reopened = ConfigStore(storage: storage);
    await reopened.load();
    expect(reopened.runLocalModelSkipDialog, isTrue);

    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();
    expect(find.text('A model that lives on your machine'), findsNothing);
    expect(conn.creates, hasLength(2));
    expect(conn.creates.last['agent'], 'harness-compute');
    expect(conn.creates.last.containsKey('prompt'), isFalse);
  });

  testWidgets('Start without the tick keeps asking', (tester) async {
    final storage = _MemoryStore();
    build(configStore: ConfigStore(storage: storage));
    await open(tester);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(storage.values.containsKey('runLocalModel.skipDialog'), isFalse);

    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();
    expect(find.text('A model that lives on your machine'), findsOneWidget);
  });

  testWidgets(
    'with no local machine the focused one is used, and its own home',
    (tester) async {
      // The app can be signed in on a computer whose own daemon is not a machine yet. The model then
      // goes where the person is looking, and the folder is the home THAT machine reports — this
      // computer's `$HOME` means nothing there.
      build(local: false);
      await open(tester);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(conn.creates.single['cwd'], '/home/remote');
    },
  );
}
