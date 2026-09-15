import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/core/project_folder.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_arrangement.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

class _App extends AppNotifier {
  _App() : super(config: AppConfig.dev, authSession: AuthSession()) {
    for (final id in ['local', 'remote']) {
      machineStates[id] =
          MachineState(
              Machine(
                machineId: id,
                name: id,
                authMode: MachineAuthMode.remote,
              ),
            )
            ..localOnly = id == 'local'
            ..nodeOnline = true
            ..agents = [
              for (final name in ['alpha', 'beta'])
                Agent(
                  id: '$id-$name',
                  name: name,
                  project: AgentProject(name: name, cwd: '/$id/$name'),
                ),
            ];
    }
  }
  final calls = <Map<String, Object?>>[];
  final previews = <String>[];
  final pending = <String, Completer<Map<String, dynamic>>>{};
  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}
  @override
  Future<Map<String, dynamic>> listCodexProfiles(
    String machineId, {
    Set<String> observedPaths = const {},
  }) async => {'profiles': []};
  @override
  Future<Map<String, dynamic>> readProjectPreview(
    String machineId,
    String path,
  ) async {
    previews.add('$machineId:$path');
    return pending[path]?.future ??
        Future.value({'readme': 'README for $path', 'branch': 'main'});
  }

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    ProjectFolderRequest? projectFolder,
    bool bypassPermission = false,
    String? codexHome,
    String? swarmId,
    PaneSplitRequest? split,
    AgentCreationAttempt? attempt,
  }) async {
    calls.add({
      'machine': machineId,
      'engine': engine,
      'folder': folder,
      'project': projectFolder?.payload,
    });
    return null;
  }
}

void main() {
  late _App app;
  Future<void> mount(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1000);
    addTearDown(tester.view.reset);
    app = _App();
    await app.agentPreference.select('claude');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showNewAgentDialog(context, app, 'local', source: 'test'),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester) async {
    final bar = find.byKey(const Key('new-agent-project-bar'));
    await tester.ensureVisible(bar);
    await tester.tap(bar);
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String value) async {
    await tester.enterText(
      find.byKey(const Key('new-agent-project-search')),
      value,
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester) async {
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'arrows preview, Enter selects, and reopening restores that project',
    (tester) async {
      await mount(tester);
      await search(tester);
      expect(
        find.byKey(const Key('new-agent-folder-newProject')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('README for /local/beta'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.text('README for /local/alpha'), findsOneWidget);
      await enter(tester);
      expect(find.byKey(const Key('new-agent-project-search')), findsNothing);
      expect(find.text('/local/alpha'), findsOneWidget);
      expect(app.calls, isEmpty);
      await search(tester);
      expect(find.text('README for /local/alpha'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('/local/alpha'), findsOneWidget);
    },
  );

  testWidgets(
    'agent switching keeps the project; each machine restores its own choice',
    (tester) async {
      await mount(tester);
      await search(tester);
      await type(tester, 'alpha');
      await enter(tester);
      await tester.tap(find.byKey(const ValueKey('new-agent-quick-opencode')));
      await tester.pumpAndSettle();
      expect(find.text('/local/alpha'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('new-agent-machine-remote')));
      await tester.pumpAndSettle();
      expect(find.text('New project'), findsOneWidget);
      await search(tester);
      expect(find.byKey(const ValueKey('project-/local/alpha')), findsNothing);
      await type(tester, 'beta');
      await enter(tester);
      await tester.tap(find.byKey(const ValueKey('new-agent-machine-local')));
      await tester.pumpAndSettle();
      expect(find.text('/local/alpha'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('new-agent-machine-remote')));
      await tester.pumpAndSettle();
      expect(find.text('/remote/beta'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-agent-submit')));
      await tester.pumpAndSettle();
      expect(app.calls.single, containsPair('folder', '/remote/beta'));
      expect(app.calls.single, containsPair('machine', 'remote'));
      expect(app.calls.single, containsPair('engine', 'opencode'));
    },
  );

  testWidgets(
    'Git URL becomes the selected project; unknown searches do not choose New',
    (tester) async {
      await mount(tester);
      await search(tester);
      await type(tester, 'no such project');
      await enter(tester);
      expect(find.text('No matching projects'), findsOneWidget);
      expect(find.byKey(const Key('new-agent-project-search')), findsOneWidget);
      await type(tester, 'owner/repo');
      await enter(tester);
      expect(find.text('repo'), findsOneWidget);
      await search(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('new-agent-project-search')),
            )
            .controller!
            .text,
        'https://github.com/owner/repo.git',
      );
      await enter(tester);
      await tester.tap(find.byKey(const Key('create-agent-submit')));
      await tester.pumpAndSettle();
      expect(app.calls.single['project'], {
        'projectSource': 'remote',
        'repositoryUrl': 'https://github.com/owner/repo.git',
      });
    },
  );

  testWidgets(
    'Command Enter creates the highlighted project, not the old selection',
    (tester) async {
      await mount(tester);
      await search(tester);
      await type(tester, 'alpha');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(app.calls.single['folder'], '/local/alpha');
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('a late preview never replaces the newly highlighted project', (
    tester,
  ) async {
    await mount(tester);
    app.pending['/local/alpha'] = Completer();
    await search(tester);
    await tester.enterText(
      find.byKey(const Key('new-agent-project-search')),
      'alpha',
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(app.previews, contains('local:/local/alpha'));
    await type(tester, 'beta');
    app.pending['/local/alpha']!.complete({'readme': 'STALE README'});
    await tester.pumpAndSettle();
    expect(find.text('README for /local/beta'), findsOneWidget);
    expect(find.text('STALE README'), findsNothing);
  });
}
