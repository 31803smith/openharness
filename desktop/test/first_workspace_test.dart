import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/widgets/app_select_field.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:xterm/xterm.dart';

import 'swarm_screen_test.dart' show mount, terminal;

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
  final launches =
      <({String machine, String engine, String folder, bool bypass})>[];
  final input = <TerminalBinaryFrame>[];

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {
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
  }) async {
    launches.add((
      machine: machineId,
      engine: engine,
      folder: folder,
      bypass: bypassPermission,
    ));
    adoptSessionForTest(terminal('created', input));
    notifyListeners();
    return null;
  }
}

class _FolderPicker extends FileSelectorPlatform {
  var opened = 0;
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opened++;
    return '/work/my-project';
  }
}

void main() {
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

    expect(find.text('Start with one agent'), findsOneWidget);
    expect(find.text('Machines'), findsNothing);
    expect(find.text('Projects'), findsNothing);
    expect(app.launches, isEmpty);
    await tester.tap(find.text('New agent'));
    await tester.pump();
    final engine = tester.widget<AppSelectField<String>>(
      find.byKey(const Key('new-agent-engine-field')),
    );
    final machine = tester.widget<AppSelectField<String>>(
      find.byKey(const Key('new-agent-machine-field')),
    );
    expect(engine.value, 'codex');
    expect(machine.value, 'm');
    expect(
      tester.getTopLeft(find.text('Project folder')).dy,
      lessThan(tester.getTopLeft(find.text('Coding agent')).dy),
    );
    expect(picker.opened, 0);
    await tester.tap(find.text('Browse…'));
    await tester.pump();
    expect(app.launches, isEmpty);
    await tester.tap(find.text('Create agent'));
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

  testWidgets('existing agents open directly from an empty workspace', (
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
    await tester.tap(find.byKey(const ValueKey('welcome-agent:m:existing')));
    await tester.pump();
    expect(app.panes.single.agentId, 'existing');
    expect(app.launches, isEmpty);
    expect(find.text('Go to an agent'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'a late probe uses an installed agent without overriding a choice',
    (tester) async {
      for (final chooseExplicitly in [false, true]) {
        final app = _FirstUseApp()..probe = Completer<void>();
        await mount(tester, app);
        await tester.tap(find.text('New agent'));
        await tester.pump();
        if (chooseExplicitly) {
          await tester.tap(find.byKey(const Key('new-agent-engine-field')));
          await tester.pump();
          await tester.tap(find.text('Cursor'));
          await tester.pump();
        }
        app.machineStates['m']!.engines.replace(const [
          EngineAvailability(engine: 'claude', installed: false),
          EngineAvailability(engine: 'codex', installed: true),
        ]);
        app.probe!.complete();
        await tester.pump();
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
