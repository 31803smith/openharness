import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/usage/models_menu_controller.dart';
import 'package:harness/usage/usage_accounts.dart';
import 'package:harness/usage/usage_controller.dart';
import 'package:harness/usage/usage_source.dart';
import 'package:harness/usage/usage_window.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_state_test.dart' show createApp;

/// Answers what the Talk to Model manager dialog reads on opening and records the
/// create it sends on Start. Anything else asked (the terminal the new pane
/// opens, say) is left pending, which is what a machine that has not answered
/// yet looks like — the same shape as the dialog's own test.
class _LocalModelConn extends WsConn {
  _LocalModelConn([String machineId = 'm'])
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: machineId,
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  final creates = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) {
    switch (type) {
      case 'engines_probe':
        return Future.value({
          'engines': [
            {'engine': 'opencode', 'installed': true},
          ],
        });
      case 'grid_models_list':
        return Future.value({'gridName': 'someone-7f3a91c4', 'models': []});
      case 'fs_list_dir':
        return Future.value({
          'path': '/home/remote',
          'entries': [],
          'truncated': false,
        });
      case 'agent_create':
        creates.add(Map.of(payload));
        return Future.value({
          'creationId': payload['creationId'],
          'state': 'created',
          'agent': {
            'id': 'lm1',
            'name': 'Model manager',
            'engine': 'opencode',
          },
        });
      default:
        return Completer<Map<String, dynamic>>().future;
    }
  }
}

class _Source implements UsageSource {
  _Source(this.provider, this.answer);
  @override
  final UsageProvider provider;
  Future<ProviderUsage> Function() answer;
  int calls = 0;
  @override
  Future<ProviderUsage> read() {
    calls++;
    return answer();
  }
}

void main() {
  final instant = DateTime.utc(2026, 9, 13, 12);
  ProviderUsage reading({
    double session = 85,
    double weekly = 30,
    DateTime? reset,
    DateTime? fetched,
    String? account = 'aabbccddeeff0011',
  }) => ProviderUsage(
    provider: UsageProvider.claude,
    status: UsageStatus.ok,
    account: account,
    fetchedAt: fetched ?? instant,
    windows: [
      UsageWindow(label: 'Session', usedPercent: session, resetsAt: reset),
      UsageWindow(label: 'Weekly', usedPercent: weekly),
    ],
  );

  test(
    'remaining means the limiting window, with account deduplication',
    () async {
      final source = _Source(UsageProvider.claude, () async => reading());
      final usage = UsageController(
        sources: [source],
        autoStart: false,
        remote: () async => [
          MachineUsage(machineName: 'Shared Mac', readings: [reading()]),
          MachineUsage(
            machineName: 'Other Mac',
            readings: [reading(account: '1122334455667788', session: 50)],
          ),
        ],
      );
      final menu = ModelsMenuController(usage: usage, now: () => instant);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      await menu.refresh();
      expect(menu.rows, hasLength(2));
      expect(menu.rows.first['title'], 'Anthropic');
      expect(menu.rows.first['status'], '15% remaining');
      expect(menu.rows.first['details'], contains('Weekly — 70% remaining'));
      expect(menu.rows.first['account'], 'aabbcc');
      expect(menu.rows.toString(), isNot(contains('Shared Mac')));
      expect(menu.rows.last['title'], 'Anthropic');
      expect(menu.rows.last['account'], '112233');
      expect(menu.rows.last['status'], '50% remaining');
      expect(menu.rows.toString(), isNot(contains('aabbccddeeff0011')));
    },
  );

  test(
    'no startup work; opening coalesces and caches requests for a minute',
    () async {
      var now = instant;
      var answer = Completer<ProviderUsage>();
      final source = _Source(UsageProvider.claude, () => answer.future);
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => now);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      expect(source.calls, 0);
      final first = menu.refresh();
      expect(menu.refresh(), same(first));
      expect(source.calls, 1);
      answer.complete(reading());
      await first;
      await menu.refresh();
      expect(source.calls, 1);
      now = now.add(const Duration(minutes: 1));
      answer = Completer<ProviderUsage>();
      final second = menu.refresh();
      expect(source.calls, 2);
      answer.complete(reading());
      await second;
    },
  );

  test('unidentified accounts do not invent an account label', () async {
    final source = _Source(
      UsageProvider.claude,
      () async => reading(account: null),
    );
    final usage = UsageController(sources: [source], autoStart: false);
    final menu = ModelsMenuController(usage: usage, now: () => instant);
    addTearDown(usage.dispose);
    addTearDown(menu.dispose);
    await menu.refresh();
    expect(menu.rows.single['title'], 'Anthropic');
    expect(menu.rows.single['account'], '');
  });

  test(
    'unknown, expired and invalid readings never become made-up percentages',
    () async {
      ProviderUsage value = const ProviderUsage(
        provider: UsageProvider.claude,
        status: UsageStatus.signedOut,
      );
      var now = instant;
      final source = _Source(UsageProvider.claude, () async => value);
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => now);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      await menu.refresh();
      expect(menu.rows.single['status'], 'Not signed in');
      for (final next in [
        reading(reset: instant),
        reading(session: double.nan),
        reading(fetched: instant.subtract(const Duration(minutes: 3))),
      ]) {
        value = next;
        now = now.add(const Duration(minutes: 1));
        await menu.refresh();
        expect(menu.rows.single['status'], 'Usage unavailable');
        expect(menu.rows.single['details'].toString(), isNot(contains('%')));
      }
    },
  );

  test(
    'a positive fraction of remaining usage is not rounded to zero',
    () async {
      final source = _Source(
        UsageProvider.claude,
        () async => reading(session: 99.6),
      );
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => instant);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      await menu.refresh();
      expect(menu.rows.single['status'], '<1% remaining');
    },
  );

  test(
    'source errors and a late response after disposal are contained',
    () async {
      final answer = Completer<ProviderUsage>();
      final source = _Source(UsageProvider.codex, () => answer.future);
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => instant);
      addTearDown(usage.dispose);
      var notifications = 0;
      menu.addListener(() => notifications++);
      final request = menu.refresh();
      menu.dispose();
      final count = notifications;
      answer.completeError(StateError('synthetic secret must not reach UI'));
      await request;
      expect(notifications, count);
    },
  );

  testWidgets(
    'native Models opens lazily without changing the swarm or search',
    (tester) async {
      const channel = MethodChannel('harness/swarm_tabs');
      final messenger = tester.binding.defaultBinaryMessenger;
      final messages = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        messages.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final source = _Source(
        UsageProvider.codex,
        () async => const ProviderUsage(
          provider: UsageProvider.codex,
          status: UsageStatus.signedOut,
        ),
      );
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage);
      final app = createApp();
      final original = app.activeSwarmId;
      final projects = SwarmProjectStore();
      await tester.pumpWidget(
        MaterialApp(
          home: SwarmScreen(
            notifier: app,
            nativeTabs: true,
            projectStore: projects,
            modelsMenu: menu,
          ),
        ),
      );
      expect(source.calls, 0);
      final previousUpdates = messages
          .where((c) => c.method == 'update')
          .length;
      final reply = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('modelsOpened'),
        ),
        (_) => reply.complete(),
      );
      await reply.future;
      await tester.pump();
      expect(source.calls, 1);
      expect(app.activeSwarmId, original);
      expect(
        messages.where((c) => c.method == 'update').length,
        previousUpdates,
      );
      expect(messages.where((c) => c.method == 'closeSearch'), isEmpty);
      final snapshot =
          messages.lastWhere((c) => c.method == 'modelsState').arguments as Map;
      expect((snapshot['subscriptions'] as List).single['title'], 'OpenAI');
      expect(
        (snapshot['subscriptions'] as List).single['status'],
        'Not signed in',
      );
      await tester.pumpWidget(const SizedBox());
      expect(
        (messages.lastWhere((c) => c.method == 'modelsState').arguments
            as Map)['subscriptions'],
        isEmpty,
      );
      menu.dispose();
      usage.dispose();
      app.dispose();
      projects.dispose();
    },
  );

  testWidgets(
    'native runLocalModel opens the dialog, and Start creates the agent',
    (tester) async {
      // The Models menu's one command arrives as a bare method call with no
      // arguments, the way Link Machine… does. It must reach the notifier's
      // action through this screen's context — the dialog is the proof the
      // door is wired, and the create is the proof it leads somewhere.
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const channel = MethodChannel('harness/swarm_tabs');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => true);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final conn = _LocalModelConn();
      final app = createApp(connectionForTest: (_) => conn);
      // A create on a machine the app believes offline parks the agent and
      // polls for the node — a timer that never lets the frame settle. The
      // fixture host is answering, so say so.
      app.machineStates['m']!.nodeOnline = true;
      final projects = SwarmProjectStore();
      await tester.pumpWidget(
        MaterialApp(
          home: SwarmScreen(
            notifier: app,
            nativeTabs: true,
            projectStore: projects,
          ),
        ),
      );
      final reply = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('runLocalModel'),
        ),
        (_) => reply.complete(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Models that live on your machine'), findsOneWidget);
      // Nothing is missing on this machine, so nothing about it is said.
      expect(find.byKey(const Key('run-local-model-status')), findsNothing);
      expect(conn.creates, isEmpty);

      await tester.tap(find.byKey(const Key('run-local-model-start')));
      await tester.pumpAndSettle();
      // The handler answers only once the dialog is done, the way every
      // dialog door does, so native focus is not handed back mid-dialog.
      await reply.future;
      expect(find.text('Models that live on your machine'), findsNothing);
      final create = conn.creates.single;
      expect(create['engine'], 'opencode');
      expect(create['agent'], AppNotifier.localModelAgent);
      expect(create['name'], AppNotifier.localModelAgentName);
      expect(create.containsKey('prompt'), isFalse);
      expect(create['cwd'], '/home/remote');

      await tester.pumpWidget(const SizedBox());
      app.dispose();
      projects.dispose();
    },
  );

  testWidgets('native runLocalModel with a machineId opens on THAT machine', (
    tester,
  ) async {
    // With two machines linked the native menu lists them and names the chosen
    // one. The create — and the dialog's own reads — must go to that machine's
    // connection, not to this computer's: the manager manages the models of
    // the computer it runs on.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const channel = MethodChannel('harness/swarm_tabs');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final conns = {
      'm': _LocalModelConn('m'),
      'other': _LocalModelConn('other'),
    };
    final app = createApp(connectionForTest: (id) => conns[id]!);
    const other = Machine(
      machineId: 'other',
      authMode: MachineAuthMode.remote,
      name: 'Studio',
    );
    app.machines = [...app.machines, other];
    app.machineStates['other'] = MachineState(other)
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
    app.machineStates['m']!.nodeOnline = true;
    final projects = SwarmProjectStore();
    await tester.pumpWidget(
      MaterialApp(
        home: SwarmScreen(
          notifier: app,
          nativeTabs: true,
          projectStore: projects,
        ),
      ),
    );
    final reply = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('runLocalModel', {'machineId': 'other'}),
      ),
      (_) => reply.complete(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('run-local-model-start')));
    await tester.pumpAndSettle();
    await reply.future;

    expect(conns['m']!.creates, isEmpty);
    final create = conns['other']!.creates.single;
    expect(create['agent'], AppNotifier.localModelAgent);
    expect(app.panes.single.machineId, 'other');

    await tester.pumpWidget(const SizedBox());
    app.dispose();
    projects.dispose();
  });
}
