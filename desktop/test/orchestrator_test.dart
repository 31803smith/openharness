import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/orchestrator/orchestrator_controller.dart';
import 'package:harness/orchestrator/orchestrator_workspace.dart';
import 'package:harness/shortcuts/app_shortcuts.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/terminal_panel.dart';
import 'package:harness/widgets/web_pane_panel.dart';

import 'swarm_state_test.dart' show createApp, MemoryStore;

const projectId = '0123456789abcdef0123456789abcdef';
Map<String, dynamic> project({
  int revision = 1,
  List<Map<String, dynamic>> tasks = const [],
}) => {
  'id': projectId,
  'revision': revision,
  'state': 'active',
  'directorId': 'director',
  'directorWorking': false,
  'tasks': tasks,
  'messages': <Map<String, dynamic>>[
    {'id': 'prompt', 'role': 'user', 'text': 'Build a lamp and launch film'},
    {
      'id': 'reply',
      'role': 'assistant',
      'text': 'I’ll coordinate CAD, Blender, and video.',
    },
  ],
};
Map<String, dynamic> task(String id, {String state = 'running', String? url}) =>
    {
      'id': id,
      'title': id,
      'harness': 'test/$id',
      'state': state,
      'attempt': 1,
      'agentId': 'agent-$id',
      'artifacts': <dynamic>[],
      'runtime': {'viewerUrl': url, 'viewerName': '$id view'},
    };

void main() {
  test('Cmd-P is two keys and leaves Cmd-B and Shift-Cmd-P distinct', () {
    final shortcut = kAppShortcuts
        .singleWhere((s) => s.action == ShortcutAction.orchestrate)
        .activator;
    expect(shortcut.trigger, LogicalKeyboardKey.keyP);
    expect(shortcut.meta, isTrue);
    expect(shortcut.shift, isFalse);
    expect(shortcut.control, isFalse);
    expect(shortcut.alt, isFalse);
    expect(
      kAppShortcuts
          .singleWhere((s) => s.action == ShortcutAction.routeTask)
          .activator
          .trigger,
      LogicalKeyboardKey.keyB,
    );
  });

  test(
    'transient chat failure retries the same receipt and retains the draft',
    () async {
      final requests = <Map<String, dynamic>>[];
      var fail = true;
      final controller = OrchestratorController(
        id: projectId,
        request: (payload) async {
          requests.add(payload);
          if (fail) throw StateError('Disconnected');
          return {'project': project(revision: 2)};
        },
      );
      addTearDown(controller.dispose);
      controller.draft = 'Make it taller';
      expect(await controller.send(controller.draft), isFalse);
      expect(controller.draft, 'Make it taller');
      fail = false;
      expect(await controller.send(controller.draft), isTrue);
      expect(requests[0]['messageId'], requests[1]['messageId']);
      expect(controller.draft, isEmpty);
    },
  );

  test('late polling results do not replace newer action results', () async {
    final poll = Completer<Map<String, dynamic>>();
    final controller = OrchestratorController(
      id: projectId,
      request: (payload) => payload['action'] == 'status'
          ? poll.future
          : Future.value({'project': project(revision: 5)}),
    );
    addTearDown(controller.dispose);
    final pending = controller.refresh();
    await controller.perform('resume');
    poll.complete({'project': project(revision: 2)});
    await pending;
    expect(controller.project!['revision'], 5);
  });

  testWidgets(
    'progressive viewers never expose worker terminals or steal a draft',
    (tester) async {
      final app = createApp();
      addTearDown(app.dispose);
      var current = project();
      final requests = <Map<String, dynamic>>[];
      final controller = OrchestratorController(
        id: projectId,
        request: (payload) async {
          requests.add(payload);
          return {'project': current};
        },
      );
      addTearDown(controller.dispose);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 850);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrchestratorWorkspace(
              notifier: app,
              machineId: 'm',
              projectId: projectId,
              controller: controller,
            ),
          ),
        ),
      );
      await tester.pump();
      final composer = find.byKey(const ValueKey('orchestrator-composer'));
      await tester.tap(composer);
      await tester.enterText(composer, 'Keep the base slimmer');
      current = project(
        revision: 2,
        tasks: [task('cad', url: 'http://127.0.0.1:9999/cad')],
      );
      await controller.refresh();
      await tester.pump();
      current = project(
        revision: 3,
        tasks: [
          task('cad', url: 'http://127.0.0.1:9999/cad'),
          task('blender', url: 'http://127.0.0.1:9998/scene'),
          task('video'),
        ],
      );
      await controller.refresh();
      await tester.pump();
      expect(
        tester.widget<TextField>(composer).controller!.text,
        'Keep the base slimmer',
      );
      expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
      expect(find.byType(TerminalPanel), findsNothing);
      expect(find.byType(WebPanePanel), findsNWidgets(2));
      expect(app.panes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        requests.where((r) => r['action'] == 'message').single['text'],
        'Keep the base slimmer',
      );
      expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(requests.any((r) => r['action'] == 'cancel'), isFalse);
    },
  );

  testWidgets('small workspace fits and unsafe viewer URLs are not mounted', (
    tester,
  ) async {
    final app = createApp();
    addTearDown(app.dispose);
    final controller = OrchestratorController(
      id: projectId,
      request: (_) async => {
        'project': project(
          tasks: [task('cad', url: 'https://untrusted.example/view')],
        ),
      },
    );
    addTearDown(controller.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrchestratorWorkspace(
            notifier: app,
            machineId: 'm',
            projectId: projectId,
            controller: controller,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(WebPanePanel), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'project tabs survive close/reopen and persisted layout restore',
    () async {
      final store = MemoryStore();
      final app = createApp(store: store);
      addTearDown(app.dispose);
      app.openOrchestratorProject('m', projectId, 'Lamp project');
      final tabId = app.activeSwarmId;
      expect(app.activeSwarm.isOrchestrator, isTrue);
      await app.closeSwarm(tabId);
      app.reopenClosedSwarm();
      expect(app.activeSwarm.orchestratorId, projectId);
      expect(app.activeSwarm.orchestratorMachineId, 'm');
      await app.flushPaneLayout();
      expect(store.values['swarm_layout_v1'], contains(projectId));
      final restored = createApp(store: store);
      addTearDown(restored.dispose);
      await restored.restorePaneLayoutForTest();
      expect(restored.swarms.singleWhere((s) => s.orchestratorId == projectId).isOrchestrator, isTrue);
    },
  );
}
