// The Talk to Local model manager dialog and the one action behind it: the copy, the machine line, the
// prerequisites that replace it, and what Start actually sends.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/settings/config_store.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/pane_menu.dart';
import 'package:harness/ws/ws_conn.dart';

/// A connection that answers the dialog's three reads and the create at once. Without it the
/// dialog would wait out each request's own timeout, and `pumpAndSettle` would be measuring those
/// rather than the dialog. Anything else asked of it (a terminal open after the create, say) is
/// left pending, which is what a machine that has not answered yet looks like.
class _Conn extends WsConn {
  _Conn({required this.engines, required this.gridName, this.gridCli})
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

  /// The daemon's word on the machine's `grid` binary (`managed`/`path`/`missing`); null = an
  /// older daemon that sends no such field.
  final String? gridCli;

  /// What the daemon names the created agent. A daemon that knows `name` echoes it; one that
  /// predates the field names the pane itself — the shape of an old Harness on that machine.
  String replyName = 'Local model manager';

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
        return Future.value({
          'gridName': gridName,
          'models': <Object?>[],
          if (gridCli != null) 'gridCli': gridCli,
        });
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
          'agent': {'id': 'lm1', 'name': replyName, 'engine': 'opencode'},
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
    String? gridCli,
    ConfigStore? configStore,
    bool local = true,
  }) {
    conn = _Conn(engines: engines, gridName: gridName, gridCli: gridCli);
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
      // A remote fixture is answering: the dialog now refuses an offline machine before Start.
      ..nodeOnline = true
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
                child: const Text('Talk to Local model manager'),
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

    expect(find.text('Models that live on your machine'), findsOneWidget);
    expect(
      find.text(
        "Local model manager is an agent that looks after the models on one of your computers. "
        "Say what you need and it helps you pick a model that fits that computer and the work, "
        "then sets it up there. Once a model is up, every agent on every machine can switch to "
        "it from its model picker.",
      ),
      findsOneWidget,
    );
    // No "Don't show this again": the dialog is where the machine is chosen, and a dialog that
    // could be waved off would take the choice with it.
    expect(find.text("Don't show this again"), findsNothing);
    expect(find.text('Not now'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    // The product's two rules for this dialog: never the CLI's name, never one vendor's noun for
    // a computer. The app runs on Linux too.
    expect(find.textContaining('grid'), findsNothing);
    expect(find.textContaining('this Mac'), findsNothing);
    // The body introduces the agent by name and never says the product's: the person is meeting
    // Local model manager, not being told to go talk to Harness.
    expect(find.textContaining('Harness'), findsNothing);
    expect(find.textContaining('!'), findsNothing);
    // No dashes of any kind in the copy: the owner's rule for this dialog.
    expect(find.textContaining('—'), findsNothing);
    expect(find.textContaining('–'), findsNothing);
    // Nothing about prerequisites when nothing is missing — but WHICH machine is always said,
    // this computer marked as such, so nobody has to guess where the manager will open.
    expect(status, findsNothing);
    // One slim row, not a control: with one machine there is nothing to choose.
    expect(find.byKey(const Key('run-local-model-machine')), findsOneWidget);
    expect(find.text('studio-7'), findsOneWidget);
    expect(find.text('This machine'), findsOneWidget);
    // And one plain sentence saying what that means.
    expect(
      find.text(
        'The model will run on this computer (studio-7). Agents on any machine can use it.',
      ),
      findsOneWidget,
    );
    // No chips, no "…", no prompt to pick: one machine is a statement, not a choice.
    expect(find.text('Which computer should it look after?'), findsNothing);
    expect(
      find.byKey(const ValueKey('run-local-model-machine-local')),
      findsNothing,
    );
    expect(find.byKey(const Key('run-local-model-machine-more')), findsNothing);
    expect(find.textContaining('(this computer)'), findsNothing);
  });

  testWidgets('missing opencode is said, and disables Start', (tester) async {
    build(
      engines: const [
        {'engine': 'opencode', 'installed': false},
      ],
    );
    await open(tester);

    expect(statusText(tester), 'Needs opencode on this machine first.');
    // The machine is still named: the sentence is about it.
    expect(find.text('studio-7'), findsOneWidget);
    expect(startEnabled(tester), isFalse);
    await tester.tap(start, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Start'), findsOneWidget);
    expect(conn.creates, isEmpty);
  });

  testWidgets('no private grid is NOT the dialog\'s business', (tester) async {
    // `gridName: null` used to disable Start with a sentence about the account. The dialog now
    // only picks a machine and goes; whether local models are set up there is the manager's own
    // first finding, said in conversation. A connected person is never stopped here.
    build(gridName: null);
    await open(tester);

    expect(status, findsNothing);
    expect(startEnabled(tester), isTrue);
    expect(find.textContaining('grid'), findsNothing);
    expect(find.textContaining('set up'), findsNothing);
  });

  testWidgets('an offline machine is said before Start, not after', (
    tester,
  ) async {
    // A remote machine whose daemon is not answering. Start used to go ahead and fail on the
    // home-folder read — the same fact, discovered after the click. Now the dialog says it and
    // Start waits, and picking a machine that IS online clears it.
    final conns = {
      'local': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
      'studio': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
    };
    notifier.dispose();
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      connectionForTest: (id) => conns[id]!,
    )..hasNavigationRail = false;
    const local = Machine(
      machineId: 'local',
      authMode: MachineAuthMode.remote,
      name: 'this one',
    );
    const studio = Machine(
      machineId: 'studio',
      authMode: MachineAuthMode.remote,
      name: 'studio-7',
    );
    notifier.machines = [local, studio];
    notifier.machineStates['local'] = MachineState(local)
      ..localOnly = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
    notifier.machineStates['studio'] = MachineState(studio)
      ..nodeOnline = false
      ..agentLoadStatus = AgentLoadStatus.loaded;

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('door'),
              onPressed: () =>
                  notifier.runLocalModel(context, machineId: 'studio'),
              child: const Text('door'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();

    expect(
      statusText(tester),
      'studio-7 is offline right now. Wake it up, or pick another machine.',
    );
    expect(startEnabled(tester), isFalse);

    // A machine that is up but not LINKED to this computer is a different sentence: the relay
    // refuses it (4404), and telling the person to wake it would send them to a computer that is
    // already awake.
    notifier.machineStates['studio']!
      ..nodeOnline = true
      ..needsLink = true;
    notifier.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      statusText(tester),
      'studio-7 isn’t linked to this computer yet. Link it from the Machines menu, then come back.',
    );
    expect(startEnabled(tester), isFalse);
    notifier.machineStates['studio']!.needsLink = false;

    await tester.tap(
      find.byKey(const ValueKey('run-local-model-machine-local')),
    );
    await tester.pumpAndSettle();
    expect(status, findsNothing);
    expect(startEnabled(tester), isTrue);
  });

  testWidgets('an old daemon that ignores the agent is named as the cause', (
    tester,
  ) async {
    // A Harness that predates `agent`/`name` opens a plain opencode pane and names it itself.
    // The pane exists, so the person is told what happened instead of watching a manager that
    // never introduces itself.
    build();
    conn.replyName = 'harness-2';
    await open(tester);
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(conn.creates, hasLength(1));
    expect(
      notifier.lastError,
      'Harness on studio-7 is too old to open Local model manager: it opened a plain opencode '
      'pane instead. Update Harness there and try again.',
    );
  });

  testWidgets(
    'a machine with no Harness Compute binary is said, and disables Start',
    (tester) async {
      // `gridCli: missing` is the daemon saying there is no `grid` on this computer to serve with —
      // the daemon installs one on start, so this is a machine whose install did not land. Said as
      // the feature's name, never the binary's; the account's grid is not the dialog's business.
      build(gridCli: 'missing', gridName: null);
      await open(tester);

      expect(
        statusText(tester),
        "Harness Compute isn't installed on this machine.",
      );
      expect(find.textContaining('grid'), findsNothing);
      expect(find.textContaining('sign in'), findsNothing);
      expect(startEnabled(tester), isFalse);
    },
  );

  testWidgets('Not now creates nothing', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('run-local-model-not-now')));
    await tester.pumpAndSettle();

    expect(find.text('Models that live on your machine'), findsNothing);
    expect(conn.creates, isEmpty);
    expect(notifier.panes, isEmpty);
  });

  testWidgets(
    'Start opens opencode in the home folder as the harness-compute agent, named',
    (tester) async {
      await open(tester);
      await tester.tap(start);
      await tester.pumpAndSettle();

      expect(find.text('Models that live on your machine'), findsNothing);
      final payload = conn.creates.single;
      expect(payload['engine'], 'opencode');
      // The pane IS the agent (`opencode --agent harness-compute`), and is titled before opencode
      // reports a session title.
      expect(payload['agent'], 'harness-compute');
      expect(payload['name'], 'Local model manager');
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

  testWidgets('a named machine wins over this computer\'s own', (tester) async {
    // The pane picker names its pane's machine. This computer has a local machine of its own
    // here, and it must NOT be preferred: a picker on a remote agent's pane is asking about the
    // models THAT computer can serve.
    final conns = {
      'local': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
      'studio': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
    };
    notifier.dispose();
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      connectionForTest: (id) => conns[id]!,
    )..hasNavigationRail = false;
    const local = Machine(
      machineId: 'local',
      authMode: MachineAuthMode.remote,
      name: 'this one',
    );
    const studio = Machine(
      machineId: 'studio',
      authMode: MachineAuthMode.remote,
      name: 'studio-7',
    );
    notifier.machines = [local, studio];
    notifier.machineStates['local'] = MachineState(local)
      ..localOnly = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
    notifier.machineStates['studio'] = MachineState(studio)
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('door'),
              onPressed: () =>
                  notifier.runLocalModel(context, machineId: 'studio'),
              child: const Text('door'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(conns['local']!.creates, isEmpty);
    // That machine's own home, as it reports it — never this computer's `$HOME`.
    expect(conns['studio']!.creates.single['cwd'], '/home/remote');
    expect(notifier.panes.single.machineId, 'studio');
  });

  testWidgets('from a pane, the machine is named, not offered', (tester) async {
    // A pane's picker asks about THAT pane's computer. Two machines linked, the door names the
    // remote one and says not to offer the other: the dialog shows one plain row, no chips, and
    // Start opens there.
    final conns = {
      'local': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
      'studio': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
    };
    notifier.dispose();
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      connectionForTest: (id) => conns[id]!,
    )..hasNavigationRail = false;
    const local = Machine(
      machineId: 'local',
      authMode: MachineAuthMode.remote,
      name: 'this one',
    );
    const studio = Machine(
      machineId: 'studio',
      authMode: MachineAuthMode.remote,
      name: 'studio-7',
    );
    notifier.machines = [local, studio];
    notifier.machineStates['local'] = MachineState(local)
      ..localOnly = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
    notifier.machineStates['studio'] = MachineState(studio)
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('door'),
              onPressed: () => notifier.runLocalModel(
                context,
                machineId: 'studio',
                chooseMachine: false,
              ),
              child: const Text('door'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();

    expect(find.text('studio-7'), findsOneWidget);
    // Said plainly that this is NOT the computer the person is sitting at.
    expect(
      find.text(
        'The model will run on studio-7, not on this computer. Agents on any machine can use it.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('run-local-model-machine-local')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('run-local-model-machine-studio')),
      findsNothing,
    );
    expect(find.text('Which computer should it look after?'), findsNothing);

    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(conns['local']!.creates, isEmpty);
    expect(conns['studio']!.creates, hasLength(1));
  });

  testWidgets('with two machines the dialog lists them, and the pick wins', (
    tester,
  ) async {
    // The door's machine is where the dialog STARTS; the person can move it. Two machines, the
    // door names the remote one, the person picks this computer: the create lands here.
    final conns = {
      'local': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
      'studio': _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
    };
    notifier.dispose();
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      connectionForTest: (id) => conns[id]!,
    )..hasNavigationRail = false;
    const local = Machine(
      machineId: 'local',
      authMode: MachineAuthMode.remote,
      name: 'this one',
    );
    const studio = Machine(
      machineId: 'studio',
      authMode: MachineAuthMode.remote,
      name: 'studio-7',
    );
    notifier.machines = [local, studio];
    notifier.machineStates['local'] = MachineState(local)
      ..localOnly = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
    notifier.machineStates['studio'] = MachineState(studio)
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;

    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('door'),
              onPressed: () =>
                  notifier.runLocalModel(context, machineId: 'studio'),
              child: const Text('door'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();
    // Both machines as chips on one row, this computer first, the door's machine chosen — and
    // one sentence saying what the chips are for.
    expect(find.text('Which computer should it look after?'), findsOneWidget);
    final localChip = find.byKey(
      const ValueKey('run-local-model-machine-local'),
    );
    final remoteChip = find.byKey(
      const ValueKey('run-local-model-machine-studio'),
    );
    expect(localChip, findsOneWidget);
    expect(remoteChip, findsOneWidget);
    expect(
      tester.getTopLeft(localChip).dx < tester.getTopLeft(remoteChip).dx,
      isTrue,
    );
    expect(tester.getTopLeft(localChip).dy, tester.getTopLeft(remoteChip).dy);
    // Two machines fit; nothing is folded behind "…".
    expect(find.byKey(const Key('run-local-model-machine-more')), findsNothing);

    await tester.tap(localChip);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(conns['studio']!.creates, isEmpty);
    expect(conns['local']!.creates, hasLength(1));
    expect(notifier.panes.single.machineId, 'local');
  });

  testWidgets('five machines stay on one row: three chips and a "…" list', (
    tester,
  ) async {
    // The row never grows with the account. Past three, the rest fold behind the more button,
    // which opens the full list — and a machine chosen from there takes a visible slot.
    final ids = ['local', 'b', 'c', 'd', 'e'];
    final conns = {
      for (final id in ids)
        id: _Conn(engines: _installed, gridName: 'someone-7f3a91c4'),
    };
    notifier.dispose();
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      connectionForTest: (id) => conns[id]!,
    )..hasNavigationRail = false;
    notifier.machines = [
      for (final id in ids)
        Machine(
          machineId: id,
          authMode: MachineAuthMode.remote,
          name: 'box-$id',
        ),
    ];
    for (final m in notifier.machines) {
      notifier.machineStates[m.machineId] = MachineState(m)
        ..localOnly = m.machineId == 'local'
        ..nodeOnline = true
        ..agentLoadStatus = AgentLoadStatus.loaded;
    }
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('door'),
              onPressed: () =>
                  notifier.runLocalModel(context, machineId: 'local'),
              child: const Text('door'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('door')));
    await tester.pumpAndSettle();

    final chips = [
      for (final id in ids) find.byKey(ValueKey('run-local-model-machine-$id')),
    ];
    expect(chips[0], findsOneWidget);
    expect(chips[1], findsOneWidget);
    expect(chips[2], findsOneWidget);
    expect(chips[3], findsNothing);
    expect(chips[4], findsNothing);
    final more = find.byKey(const Key('run-local-model-machine-more'));
    expect(more, findsOneWidget);
    // All on one line.
    final tops = {for (final c in chips.take(3)) tester.getTopLeft(c).dy};
    expect(tops.length, 1);
    // The more button is a shade shorter than a chip; same row means its
    // center sits within the chips' height, not that its top matches.
    final chipRect = tester.getRect(chips[0]);
    final moreCenter = tester.getCenter(more).dy;
    expect(moreCenter > chipRect.top && moreCenter < chipRect.bottom, isTrue);

    await tester.tap(more);
    await tester.pumpAndSettle();
    // The pane menu, not a select: a header, rows, the current one filled — no tick anywhere.
    expect(find.text('Machines'), findsOneWidget);
    expect(find.byType(PaneMenuRow), findsNWidgets(5));
    for (final tick in [Icons.check, Icons.check_rounded]) {
      expect(
        find.descendant(
          of: find.byType(PaneMenuRow),
          matching: find.byIcon(tick),
        ),
        findsNothing,
      );
    }
    await tester.tap(find.text('box-e').last);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(conns['e']!.creates, hasLength(1));
    expect(notifier.panes.single.machineId, 'e');
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
