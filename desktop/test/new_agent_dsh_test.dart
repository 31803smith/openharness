// A domain harness in the Create dialog: one tile, its base engine under
// Advanced, an install-first step on a machine that lacks it, and a create that
// names both the harness and the engine it runs on.
import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/dsh_catalog.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_arrangement.dart';
import 'package:harness/shared/widgets/app_select_field.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

const _folder = '/work/air-monitor';

class _Folders extends FileSelectorPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => _folder;
}

const _circuit = DshEntry(
  id: 'autonomous/circuit',
  name: 'Circuit',
  engine: 'claude',
  description: 'Chat with AI → a board you can order',
  installed: false,
  viewer: true,
  tier: 2,
);

/// Stands in for the machine: the engine probe answers at once, the harness
/// catalog answers what the test seeded, and installs/creates are recorded.
class _Notifier extends AppNotifier {
  _Notifier()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );

  final installs = <String>[];
  final launches = <Map<String, Object?>>[];
  Completer<String?>? pendingInstall;
  int harnessProbes = 0;

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}

  @override
  Future<void> probeDsh(String machineId, {bool force = false}) async {
    harnessProbes++;
  }

  @override
  Future<Map<String, dynamic>> listCodexProfiles(
    String machineId, {
    Set<String> observedPaths = const {},
  }) async => {'profiles': <dynamic>[]};

  @override
  Future<String?> installDsh(String machineId, String id) {
    installs.add(id);
    final machine = machineStates[machineId]!;
    machine.dsh.installs[id] = DshInstallProgress(id: id, phase: 'setup');
    notifyListeners();
    final pending = pendingInstall;
    if (pending == null) {
      machine.dsh.replace([_circuit.copyWith(installed: true)]);
      return Future.value(null);
    }
    return pending.future.then((error) {
      if (error == null) {
        machine.dsh.replace([_circuit.copyWith(installed: true)]);
      }
      return error;
    });
  }

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    String? codexHome,
    String? dsh,
    String? swarmId,
    PaneSplitRequest? split,
    AgentCreationAttempt? attempt,
  }) async {
    launches.add({
      'machine': machineId,
      'engine': engine,
      'dsh': dsh,
      'folder': folder,
      'bypass': bypassPermission,
    });
    return 'Test launch refused.';
  }
}

extension on DshEntry {
  DshEntry copyWith({bool? installed}) => DshEntry(
    id: id,
    name: name,
    engine: engine,
    description: description,
    installed: installed ?? this.installed,
    viewer: viewer,
    tier: tier,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FileSelectorPlatform.instance = _Folders());

  const machine = Machine(
    machineId: 'machine-1',
    authMode: MachineAuthMode.remote,
    name: 'harness-remote-box',
  );

  Future<_Notifier> open(
    WidgetTester tester, {
    required void Function(MachineState state) seed,
  }) async {
    final notifier = _Notifier();
    addTearDown(notifier.dispose);
    final state = MachineState(machine)..localOnly = true;
    state.engines.replace(const [
      EngineAvailability(engine: 'claude', installed: true),
      EngineAvailability(engine: 'codex', installed: true),
    ]);
    seed(state);
    notifier.machineStates['machine-1'] = state;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showNewAgentDialog(
                context,
                notifier,
                'machine-1',
                source: 'machine_row',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse…'));
    await tester.pumpAndSettle();
    return notifier;
  }

  String engineField(WidgetTester tester) => tester
      .widget<AppSelectField<String>>(
        find.byKey(const Key('new-agent-engine-field')),
      )
      .value;

  testWidgets(
    'Circuit is one click, says what it runs on, and creates on its base engine',
    (tester) async {
      final app = await open(
        tester,
        seed: (state) =>
            state.dsh.replace([_circuit.copyWith(installed: true)]),
      );
      expect(app.harnessProbes, 1, reason: 'asked on open, like the engines');
      await tester.tap(
        find.byKey(const ValueKey('new-agent-quick-autonomous/circuit')),
      );
      await tester.pumpAndSettle();
      expect(engineField(tester), 'autonomous/circuit');
      expect(find.text('Runs on Claude Code'), findsOneWidget);
      // Installed, so nothing to announce.
      expect(find.textContaining('Harness will install'), findsNothing);
      await tester.tap(find.byKey(const Key('new-agent-advanced')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-agent-runs-on')), findsOneWidget);
      expect(
        find.textContaining('Runs on Claude Code. The harness brings'),
        findsOneWidget,
      );
      // Its base engine's bypass flag is the one offered: a harness has no
      // flag of its own, and without the base's it would say "Managed by".
      await tester.ensureVisible(find.text('Bypass permission prompts'));
      expect(find.text('Bypass permission prompts'), findsOneWidget);
      expect(find.textContaining('Managed by'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Create Agent'));
      await tester.pump();
      expect(app.installs, isEmpty);
      expect(app.launches.single, {
        'machine': 'machine-1',
        'engine': 'claude',
        'dsh': 'autonomous/circuit',
        'folder': _folder,
        'bypass': false,
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a harness the machine lacks is installed first, with its own words',
    (tester) async {
      final app = await open(
        tester,
        seed: (state) => state.dsh.replace([_circuit]),
      );
      app.pendingInstall = Completer<String?>();
      await tester.tap(
        find.byKey(const ValueKey('new-agent-quick-autonomous/circuit')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Harness will install Circuit on harness-remote-box before starting.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Create Agent'));
      await tester.pump();
      expect(app.installs, ['autonomous/circuit']);
      expect(
        app.launches,
        isEmpty,
        reason: 'no create until the install lands',
      );
      expect(find.text('Installing Circuit…'), findsOneWidget);
      expect(
        find.textContaining('Setting up the toolchain…'),
        findsOneWidget,
        reason: 'the machine narrates the install through the status line',
      );
      app.pendingInstall!.complete(null);
      await tester.pump();
      await tester.pump();
      expect(app.launches.single['dsh'], 'autonomous/circuit');
      expect(app.launches.single['engine'], 'claude');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed install is a sentence and no create', (tester) async {
    final app = await open(
      tester,
      seed: (state) => state.dsh.replace([_circuit]),
    );
    app.pendingInstall = Completer<String?>();
    await tester.tap(
      find.byKey(const ValueKey('new-agent-quick-autonomous/circuit')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create Agent'));
    await tester.pump();
    app.pendingInstall!.complete('kicad-cli is not on harness-remote-box');
    await tester.pump();
    await tester.pump();
    expect(app.launches, isEmpty);
    expect(find.text('kicad-cli is not on harness-remote-box'), findsOneWidget);
    // Retryable: the button is back.
    expect(find.widgetWithText(FilledButton, 'Create Agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a machine that has not answered offers the tiles without a verdict',
    (tester) async {
      final app = await open(tester, seed: (_) {});
      await tester.tap(
        find.byKey(const ValueKey('new-agent-quick-autonomous/workshop')),
      );
      await tester.pumpAndSettle();
      expect(engineField(tester), 'autonomous/workshop');
      expect(find.text('Runs on Codex'), findsOneWidget);
      expect(find.textContaining('Harness will install'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Create Agent'));
      await tester.pump();
      expect(app.installs, isEmpty);
      expect(app.launches.single['engine'], 'codex');
      expect(app.launches.single['dsh'], 'autonomous/workshop');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('More lists the machine\'s harnesses after the engines', (
    tester,
  ) async {
    await open(
      tester,
      seed: (state) => state.dsh.replace([
        _circuit,
        const DshEntry(
          id: 'someone/robot-arm',
          name: 'Robot Arm',
          engine: 'codex',
        ),
      ]),
    );
    await tester.tap(find.byTooltip('More agents'));
    await tester.pumpAndSettle();
    // Far down a list of fourteen engines: scrolled into view first, or the
    // tap lands on the menu's edge and quietly selects nothing.
    await tester.ensureVisible(find.text('Robot Arm'));
    await tester.pumpAndSettle();
    expect(find.text('Robot Arm'), findsOneWidget);
    expect(find.text('on Codex'), findsOneWidget);
    await tester.tap(find.text('Robot Arm'));
    await tester.pumpAndSettle();
    expect(engineField(tester), 'someone/robot-arm');
    expect(find.text('Runs on Codex'), findsOneWidget);
    expect(
      find.text(
        'Harness will install Robot Arm on harness-remote-box before starting.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
