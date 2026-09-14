import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/widgets/app_select_field.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_arrangement.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:xterm/xterm.dart';

import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_interactions_test.dart' show chord;
import 'keymap_host_test.dart' show MemoryKeymap;
import 'keymap_runtime_test.dart' as runtime;

class _FirstUseApp extends AppNotifier {
  _FirstUseApp()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      ) {
    hasNavigationRail = false;
    const machine = Machine(
      machineId: 'm',
      name: 'My computer',
      authMode: MachineAuthMode.remote,
    );
    machines = [machine];
    machineStates['m'] = MachineState(machine)
      ..localOnly = true
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
  }

  Completer<void>? probe;
  var probes = 0;
  Completer<void>? reconnect;
  var reconnects = 0;
  Completer<String?>? creation;
  final launches =
      <({String machine, String engine, String folder, bool bypass})>[];
  final input = <TerminalBinaryFrame>[];

  @override
  Future<void> retryMachines() async {
    reconnects++;
    await reconnect?.future;
  }

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {
    probes++;
    await probe?.future;
  }

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    String? codexHome,
    String? swarmId,
    PaneSplitRequest? split,
    AgentCreationAttempt? attempt,
  }) async {
    launches.add((
      machine: machineId,
      engine: engine,
      folder: folder,
      bypass: bypassPermission,
    ));
    if (creation != null) {
      final error = await creation!.future;
      if (error != null) return error;
    }
    adoptSessionForTest(terminal('created', input));
    notifyListeners();
    return null;
  }
}

class _FolderPicker extends FileSelectorPlatform {
  var opened = 0;
  Completer<String?>? pending;
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opened++;
    if (pending != null) return pending!.future;
    return '/work/my-project';
  }
}

void main() {
  testWidgets(
    'welcome presents two actions without machine and project directories',
    (tester) async {
      final app = _FirstUseApp();
      final projects = SwarmProjectStore();
      await projects.add(
        const SavedSwarmProject(
          machineId: 'm',
          path: '/work/saved-project',
          name: 'Saved project',
        ),
      );
      await mount(tester, app, projects: projects);
      expect(find.text('Find a harness'), findsOneWidget);
      expect(find.text('Create a new harness'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('swarm-welcome-search-input')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('swarm-start-primary')), findsOneWidget);
      expect(find.text('Machines'), findsNothing);
      expect(find.text('Projects'), findsNothing);
      expect(find.text('Saved project'), findsNothing);
      expect(find.byKey(const ValueKey('swarm-start-clone')), findsNothing);
      expect(app.launches, isEmpty);
      await tester.pumpWidget(const SizedBox());
      projects.dispose();
      app.dispose();
    },
  );

  testWidgets('first discovery enables the new-agent action below search', (
    tester,
  ) async {
    final app = _FirstUseApp();
    final local = app.machineStates.remove('m')!;
    app.machinesLoading = true;
    final oldPicker = FileSelectorPlatform.instance;
    final picker = _FolderPicker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = oldPicker);
    await mount(tester, app);
    expect(find.text('Finding computers…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picker.opened, 0);
    // Enter opened search. Dismiss its results before choosing the separate
    // creation action beneath the search/recent-work area.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    app.machineStates['m'] = local;
    app.machinesLoading = false;
    app.dismissError();
    await tester.pump();
    expect(find.text('Create a new harness'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('swarm-start-primary')));
    await tester.pump();
    expect(picker.opened, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('/work/my-project'), findsOneWidget);
    expect(app.launches, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('offline start retries once and retains its empty swarm', (
    tester,
  ) async {
    final app = _FirstUseApp()..reconnect = Completer<void>();
    app.machineStates['m']!.nodeOnline = false;
    final original = app.activeSwarm;
    await mount(tester, app);
    expect(find.text('Reconnect'), findsOneWidget);
    await tester.tap(find.text('Reconnect'));
    await tester.pump();
    expect(find.text('Finding computers…'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.reconnects, 1);
    expect(app.launches, isEmpty);
    expect(app.activeSwarm, same(original));
    app.reconnect!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Reconnect'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('discovery preserves the focused agent search', (tester) async {
    final app = _FirstUseApp();
    final local = app.machineStates.remove('m')!;
    app.machinesLoading = true;
    await mount(tester, app);
    final browsing = find.byKey(const ValueKey('swarm-welcome-search-input'));
    final focus = tester.widget<TextField>(browsing).focusNode!;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    app.machineStates['m'] = local;
    app.machinesLoading = false;
    app.dismissError();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(find.text('Machines'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.launches, isEmpty);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'another unavailable computer does not hide the local start path',
    (tester) async {
      final app = _FirstUseApp();
      const remote = Machine(
        machineId: 'r',
        name: 'Remote computer',
        authMode: MachineAuthMode.remote,
      );
      app.machineStates['r'] = MachineState(remote)
        ..nodeOnline = false
        ..agentLoadStatus = AgentLoadStatus.error;
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      expect(find.text('Create a new harness'), findsOneWidget);
      expect(find.text('Machines'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('swarm-start-primary')));
      await tester.pump();
      expect(picker.opened, 1);
      expect(find.text('/work/my-project'), findsOneWidget);
      expect(
        tester
            .widget<AppSelectField<String>>(
              find.byKey(const Key('new-agent-machine-field')),
            )
            .value,
        'm',
      );
      expect(
        tester
            .widget<AppSelectField<String>>(
              find.byKey(const Key('new-agent-machine-field')),
            )
            .options
            .last
            .label,
        'Remote computer — Remote — Offline',
      );
      expect(app.launches, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'pending creation stays visible and an error preserves choices for retry',
    (tester) async {
      final app = _FirstUseApp()..creation = Completer<String?>();
      app.machineStates['m']!.engines.replace(const [
        EngineAvailability(engine: 'claude', installed: true),
      ]);
      final oldPicker = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FolderPicker();
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyN, shift: true);
      await tester.pump();
      await tester.tap(find.text('Browse…'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tapAt(const Offset(8, 100));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Creating agent…'), findsOneWidget);
      expect(app.launches, hasLength(1));
      expect(app.panes, isEmpty);
      final folder = find.byKey(const Key('new-agent-folder'));
      expect(
        tester.widget<InkWell>(folder).focusNode!.canRequestFocus,
        isFalse,
      );

      app.creation!.complete('Choose another project folder and try again.');
      await tester.pump();
      expect(
        find.text('Choose another project folder and try again.'),
        findsOneWidget,
      );
      expect(find.text('/work/my-project'), findsOneWidget);
      expect(
        tester
            .widget<AppSelectField<String>>(
              find.byKey(const Key('new-agent-engine-field')),
            )
            .value,
        'claude',
      );
      await tester.tap(find.text('Change'));
      await tester.pump();
      expect(
        find.text('Choose another project folder and try again.'),
        findsNothing,
      );
      app.creation = null;
      await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);
      expect(app.launches, hasLength(2));
      expect(app.input, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  for (final native in [false, true]) {
    testWidgets(
      'new agent ${native ? 'native menu' : 'floating picker'} defaults to this computer',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('harness/swarm_tabs'),
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('harness/swarm_tabs'),
            null,
          ),
        );
        final app = _FirstUseApp();
        final map = MemoryKeymap();
        app.machineStates['m']!.engines.replace(const [
          EngineAvailability(engine: 'codex', installed: true),
        ]);
        const remote = Machine(
          machineId: 'remote',
          name: 'Remote computer',
          authMode: MachineAuthMode.remote,
        );
        app.machines = [...app.machines, remote];
        app.machineStates['remote'] = MachineState(remote)
          ..nodeOnline = true
          ..agentLoadStatus = AgentLoadStatus.loaded
          ..agents = const [
            Agent(
              id: 'existing',
              name: 'Existing work',
              engine: 'codex',
              terminalAvailable: true,
              project: AgentProject(name: 'Workspace', cwd: '/work/existing'),
            ),
          ];
        final pane = app.adoptSessionForTest(
          TerminalSession(
              machineId: 'remote',
              agentId: 'existing',
              agentName: 'Existing work',
              engineId: 'codex',
              send: (_, _) async => true,
              sendBinary: (frame) async {
                if (frame.kind == TerminalBinaryKind.input) {
                  app.input.add(frame);
                }
                return true;
              },
            )
            ..status = TerminalSessionStatus.controlling
            ..streamId = 'stream-existing',
        );
        await runtime.mount(tester, app, map, native: native);
        if (native) {
          final opening = runtime.native(tester, 'newAgent');
          await tester.pump();
          await opening;
        } else {
          final search = find.byKey(const ValueKey('swarm-new-agent-button'));
          final add = find.byKey(const ValueKey('swarm-add-agent-button'));
          final bell = find.byKey(const ValueKey('swarm-notifications-button'));
          expect(
            tester.getRect(search).right,
            lessThanOrEqualTo(tester.getRect(bell).left),
          );
          expect(tester.getRect(add).left, greaterThan(1000));
          expect(
            tester.getRect(add).top,
            lessThan(tester.getRect(find.byKey(pane.cellKey)).bottom),
          );
          await tester.tap(add);
          await tester.pump();
          expect(find.byType(AlertDialog), findsNothing);
          await tester.tap(
            find.byKey(const ValueKey('swarm-search-new-agent')),
          );
          await tester.pump();
        }
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('/work/existing'), findsNothing);
        expect(find.text('Choose a folder…'), findsOneWidget);
        final machineField = tester.widget<AppSelectField<String>>(
          find.byKey(const Key('new-agent-machine-field')),
        );
        expect(machineField.value, 'm');
        expect(machineField.options.map((option) => option.label), [
          'My computer — This computer',
          'Remote computer — Remote',
        ]);
        expect(
          tester
              .widget<AppSelectField<String>>(
                find.byKey(const Key('new-agent-engine-field')),
              )
              .value,
          'codex',
        );
        expect(app.panes, [pane]);
        expect(app.launches, isEmpty);
        expect(app.input, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        if (!native) {
          final search = find.byKey(const ValueKey('swarm-search-input'));
          expect(search, findsOneWidget);
          expect(tester.widget<TextField>(search).focusNode!.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
        }
        expect(
          tester
              .widget<TerminalView>(find.byType(TerminalView))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        map.dispose();
      },
    );
  }

  testWidgets(
    'new agent is keyboard accessible without hidden focus stops',
    (tester) async {
      final app = _FirstUseApp();
      app.machineStates['m']!.engines.replace(const [
        EngineAvailability(engine: 'codex', installed: true),
      ]);
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker()..pending = Completer<String?>();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyN, shift: true);
      await tester.pump();

      bool fieldFocused(String key) => tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(InkWell),
            ),
          )
          .focusNode!
          .hasPrimaryFocus;

      expect(find.byKey(const Key('new-agent-machine-field')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(
          tester.element(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Clone repository…'),
            ),
          ),
        ).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final folder = tester.widget<InkWell>(
        find.byKey(const Key('new-agent-folder')),
      );
      expect(folder.focusNode!.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picker.opened, 1);
      expect(find.text('Waiting for the folder picker…'), findsOneWidget);
      picker.pending!.complete('/work/my-project');
      await tester.pump();
      await tester.pump();
      expect(folder.focusNode!.hasPrimaryFocus, isTrue);
      expect(find.text('/work/my-project'), findsOneWidget);

      for (final id in ['codex', 'claude', 'cursor']) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          Focus.of(
            tester.element(
              find.descendant(
                of: find.byKey(ValueKey('new-agent-quick-$id')),
                matching: find.byType(Text),
              ),
            ),
          ).hasPrimaryFocus,
          isTrue,
        );
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(fieldFocused('new-agent-engine-field'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(find.text('Advanced'))).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(tester.element(find.text('Cancel'))).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        Focus.of(
          tester.element(
            find.descendant(
              of: find.byKey(const ValueKey('create-agent-submit')),
              matching: find.text('Create Agent'),
            ),
          ),
        ).hasPrimaryFocus,
        isTrue,
      );
      expect(app.launches, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.launches.single.folder, '/work/my-project');
      expect(app.input, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets('fresh workspace reaches an agent with an installed default', (
    tester,
  ) async {
    final app = _FirstUseApp();
    app.machineStates['m']!.engines.replace(const [
      EngineAvailability(engine: 'claude', installed: false, installable: true),
      EngineAvailability(engine: 'codex', installed: true),
    ]);
    final oldPicker = FileSelectorPlatform.instance;
    final picker = _FolderPicker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = oldPicker);
    await mount(tester, app);

    expect(find.text('New Harness'), findsWidgets);
    expect(find.text('Machines'), findsNothing);
    expect(find.text('Projects'), findsNothing);
    expect(app.launches, isEmpty);
    expect(
      find.byKey(const ValueKey('swarm-welcome-search-input')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('swarm-welcome-search-input')),
          )
          .focusNode!
          .hasFocus,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('swarm-start-primary')));
    await tester.pump();
    final engine = tester.widget<AppSelectField<String>>(
      find.byKey(const Key('new-agent-engine-field')),
    );
    expect(engine.value, 'codex');
    expect(find.byKey(const Key('new-agent-machine-field')), findsNothing);
    expect(
      tester.getTopLeft(find.text('Working folder')).dy,
      lessThan(tester.getTopLeft(find.text('Agent')).dy),
    );
    expect(picker.opened, 1);
    expect(app.probes, 1);
    expect(find.text('/work/my-project'), findsOneWidget);
    expect(app.launches, isEmpty);
    await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
    await tester.pump();

    expect(app.launches, [
      (
        machine: 'm',
        engine: 'codex',
        folder: '/work/my-project',
        bypass: false,
      ),
    ]);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.text('Your first workspace'), findsNothing);
    expect(app.input, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('every empty swarm offers the same existing-agent addition', (
    tester,
  ) async {
    final app = _FirstUseApp();
    app.machineStates['m']!.agents = const [
      Agent(
        id: 'existing',
        name: 'My ongoing work',
        engine: 'codex',
        terminalAvailable: true,
      ),
    ];
    await mount(tester, app);
    expect(app.panes, isEmpty);
    expect(find.text('Find a harness'), findsOneWidget);
    expect(find.text('Go to an agent'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('swarm-welcome-search-input')),
      'My ongoing work',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.panes.single.agentId, 'existing');
    final source = app.activeSwarm;
    final pane = app.panes.single;
    app.newSwarm();
    await tester.pump();
    expect(find.text('Find a harness'), findsOneWidget);
    expect(find.text('Create a new harness'), findsOneWidget);
    expect(find.text('Go to an agent'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('swarm-welcome-search-input')),
      'My ongoing work',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.panes.single, same(pane));
    expect(source.panes.single, same(pane));
    final used = app.activeSwarmId;
    await app.closeSwarm(used);
    app.newSwarm();
    await tester.pump();
    expect(app.closedHistory, isNotEmpty);
    expect(find.text('Find a harness'), findsOneWidget);
    expect(app.launches, isEmpty);
    expect(find.text('Go to an agent'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'first-folder selection reuses discovery and ignores repeated activation',
    (tester) async {
      final app = _FirstUseApp()..probe = Completer<void>();
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker()..pending = Completer<String?>();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);

      await tester.tap(find.text('Create a new harness'));
      await tester.pump();
      await tester.tap(find.text('Create a new harness'));
      await tester.pump();
      expect(picker.opened, 1);
      expect(app.probes, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.launches, isEmpty);

      app.machineStates['m']!.engines.replace(const [
        EngineAvailability(engine: 'claude', installed: false),
        EngineAvailability(engine: 'codex', installed: true),
      ]);
      app.probe!.complete();
      await tester.pump();
      picker.pending!.complete('/work/chosen');
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('/work/chosen'), findsOneWidget);
      expect(
        tester
            .widget<AppSelectField<String>>(
              find.byKey(const Key('new-agent-engine-field')),
            )
            .value,
        'codex',
      );
      expect(app.probes, 1);
      expect(app.launches, isEmpty);
      expect(app.input, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  for (final change in [
    'cancel',
    'swarm',
    'machine',
    'remote',
    'offline',
    'link',
  ]) {
    testWidgets('first-folder result is discarded after $change', (
      tester,
    ) async {
      final app = _FirstUseApp();
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker()..pending = Completer<String?>();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      await tester.tap(find.text('Create a new harness'));
      await tester.pump();
      switch (change) {
        case 'swarm':
          app.newSwarm();
        case 'machine':
          app.machineStates['m'] = MachineState(app.machines.single)
            ..localOnly = true;
        case 'remote':
          app.machineStates['m']!.localOnly = false;
        case 'offline':
          app.machineStates['m']!.nodeOnline = false;
        case 'link':
          app.machineStates['m']!.needsLink = true;
      }
      picker.pending!.complete(change == 'cancel' ? null : '/work/stale');
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.allPanes, isEmpty);
      expect(app.launches, isEmpty);
      expect(app.input, isEmpty);
      // Dismissing the native chooser also releases the ordinary New agent
      // command; no abandoned pending flag should trap the workspace.
      await chord(tester, LogicalKeyboardKey.keyN, shift: true);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('/work/stale'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }

  testWidgets(
    'a late probe uses an installed agent without overriding a choice',
    (tester) async {
      for (final chooseExplicitly in [false, true]) {
        final app = _FirstUseApp()..probe = Completer<void>();
        await mount(tester, app);
        await chord(tester, LogicalKeyboardKey.keyN, shift: true);
        await tester.pump();
        if (chooseExplicitly) {
          await tester.tap(
            find.byKey(const ValueKey('new-agent-quick-cursor')),
          );
          await tester.pump();
        }
        app.machineStates['m']!.engines.replace(const [
          EngineAvailability(engine: 'claude', installed: false),
          EngineAvailability(engine: 'codex', installed: true),
        ]);
        app.probe!.complete();
        await tester.pump();
        await tester.pump();
        expect(app.probes, 1);
        final engine = tester.widget<AppSelectField<String>>(
          find.byKey(const Key('new-agent-engine-field')),
        );
        expect(engine.value, chooseExplicitly ? 'cursor' : 'codex');
        expect(app.launches, isEmpty);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      }
    },
  );
}
