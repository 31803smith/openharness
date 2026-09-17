import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/auth/auth_session.dart';
import 'package:harness_mobile/core/config.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/phone/agent_index.dart';
import 'package:harness_mobile/phone/compact_age.dart';
import 'package:harness_mobile/phone/phone_search_folder_header.dart';
import 'package:harness_mobile/phone/phone_search_groups.dart';
import 'package:harness_mobile/phone/phone_search_index.dart';
import 'package:harness_mobile/phone/phone_search_page.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/state/pending_question.dart';

final _now = DateTime.now();

Agent _agent(
  String id, {
  String? title,
  String cwd = '/srv/work',
  int? minutesAgo,
  bool terminal = true,
}) => Agent(
  id: id,
  name: 'work · $id',
  title: title,
  engine: 'codex',
  project: AgentProject(name: 'work', cwd: cwd),
  updatedAt: minutesAgo == null
      ? null
      : _now.subtract(Duration(minutes: minutesAgo)),
  terminalAvailable: terminal,
);

MachineState _machine(String id, List<Agent> agents) =>
    MachineState(
        Machine(machineId: id, authMode: MachineAuthMode.remote, name: id),
      )
      ..nodeOnline = true
      ..connectionStatus = ConnectionStatus.connected
      ..agentLoadStatus = AgentLoadStatus.loaded
      ..agents = agents;

void _markWaiting(MachineState machine, String agentId) =>
    machine.blockedAgents[agentId] = PendingQuestion(
      machineId: machine.machine.machineId,
      agentId: agentId,
      requestId: 'r',
      answerKey: 'q',
      prompt: 'q',
      options: const ['yes'],
      multi: false,
      since: _now,
    );

AppNotifier _app(List<MachineState> machines) {
  final app = AppNotifier(
    config: AppConfig.dev,
    authSession: AuthSession(),
    configStore: null,
  );
  app.machines = [for (final state in machines) state.machine];
  for (final state in machines) {
    app.machineStates[state.machine.machineId] = state;
  }
  return app;
}

List<String> _agentIds(List<PhoneSearchResult> rows) => [
  for (final row in rows)
    if (row.entry != null) row.entry!.agent.id,
];

void main() {
  group('Agent.fromJson', () {
    test('reads the title and when the conversation last moved', () {
      final agent = Agent.fromJson({
        'id': 'a',
        'name': 'work · 3188',
        'title': 'Fix login redirect',
        'updatedAt': '2026-09-17T07:00:00.000Z',
      });
      expect(agent.title, 'Fix login redirect');
      expect(agent.updatedAt, DateTime.utc(2026, 9, 17, 7));
      expect(agent.copyWith(name: 'x').updatedAt, agent.updatedAt);
    });

    test('an older daemon, or garbage, leaves both unknown', () {
      final agent = Agent.fromJson({
        'id': 'a',
        'title': null,
        'updatedAt': 'yesterday-ish',
      });
      expect(agent.title, isNull);
      expect(agent.updatedAt, isNull);
    });
  });

  test('recentAgents: waiting, working, openable, then newest first', () {
    final machine = _machine('m', [
      _agent('undated'),
      _agent('old', minutesAgo: 90),
      _agent('gone', minutesAgo: 1, terminal: false),
      _agent('fresh', minutesAgo: 2),
      _agent('busy', minutesAgo: 60),
      _agent('asking', minutesAgo: 30),
    ]);
    machine.processingAgentIds.add('busy');
    _markWaiting(machine, 'asking');
    final entries = [
      for (final agent in machine.agents)
        AgentEntry(machine: machine, agent: agent),
    ];
    expect(recentAgents(entries).map((entry) => entry.agent.id), [
      'asking',
      'busy',
      'fresh',
      'old',
      'undated',
      'gone',
    ]);
  });

  group('search', () {
    final app = _app([
      _machine('box', [
        _agent('3188', minutesAgo: 1),
        _agent('48e9', title: 'Review payment flow', minutesAgo: 20),
        _agent('2312', cwd: '/srv/node', minutesAgo: 5),
      ]),
    ]);
    tearDownAll(app.dispose);

    test('a title ranks like a name, ahead of a fresher metadata hit', () {
      final withFolderHit = _app([
        _machine('box', [
          _agent('f00d', cwd: '/srv/reviewer', minutesAgo: 0),
          ...app.machineStates['box']!.agents,
        ]),
      ]);
      addTearDown(withFolderHit.dispose);
      final ranked = rankPhoneSearch(phoneSearchIndex(withFolderHit), 'review');
      expect(_agentIds(ranked), ['48e9', 'f00d']);
      expect(ranked.first.subtitle, 'Review payment flow');
    });

    test('groups keep recency: the freshest agent heads the first group', () {
      final groups = phoneSearchGroups(phoneSearchIndex(app));
      expect([for (final group in groups) group.folder], ['work', 'node']);
      expect(_agentIds(phoneSearchGroupedRows(groups)), [
        '3188',
        '48e9',
        '2312',
      ]);
    });

    test('the best match is the first row of the first group', () {
      final ranked = rankPhoneSearch(phoneSearchIndex(app), '2312');
      final groups = phoneSearchGroups(ranked);
      expect(groups.first.folder, 'node');
      expect(_agentIds(groups.first.rows).first, '2312');
    });
  });

  test('compactAge', () {
    final now = DateTime(2026, 9, 17, 12);
    String ago(Duration age) => compactAge(now.subtract(age), now);
    expect(ago(const Duration(seconds: 20)), 'now');
    expect(ago(const Duration(minutes: 4)), '4m');
    expect(ago(const Duration(hours: 2, minutes: 59)), '2h');
    expect(ago(const Duration(days: 3)), '3d');
    expect(ago(const Duration(days: 15)), '2w');
    expect(ago(const Duration(days: 400)), '1y');
    expect(compactAge(now.add(const Duration(minutes: 5)), now), 'now');
  });

  testWidgets('the page draws folders, the work and how fresh it is', (
    tester,
  ) async {
    final app = _app([
      _machine('box', [
        _agent('3188', title: 'Fix login redirect', minutesAgo: 4),
        _agent('2312', cwd: '/srv/node', minutesAgo: 30),
      ]),
    ]);
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: PhoneSearchPage(notifier: app)));
    await tester.pump();

    expect(find.byType(PhoneSearchFolderHeader), findsNWidgets(2));
    expect(find.text('Fix login redirect'), findsOneWidget);
    expect(find.text('4m'), findsOneWidget);
    expect(find.text('30m'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('work · 3188')).dy,
      lessThan(tester.getTopLeft(find.text('work · 2312')).dy),
    );

    await tester.enterText(find.byType(TextField), 'login');
    await tester.pump();
    expect(find.text('work · 2312'), findsNothing);
    expect(find.byType(PhoneSearchFolderHeader), findsOneWidget);
  });

  testWidgets('one bar: no Cancel beside it, and its chevron closes search', (
    tester,
  ) async {
    final app = _app([
      _machine('box', [_agent('3188', minutesAgo: 4)]),
    ]);
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openPhoneSearch(context, app),
            child: const Text('Open search'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSearchPage), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneSearchPage), findsNothing);
  });
}
