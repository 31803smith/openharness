import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pending_question.dart';
import 'package:harness/state/swarm_attention.dart';
import 'package:harness/terminal/terminal_session.dart';

import 'swarm_screen_test.dart' show terminal;
import 'swarm_state_test.dart' show createApp;

PendingQuestion waitingQuestion(
  String agentId, {
  String machineId = 'm',
  String requestId = 'question',
  String prompt = 'Which folder?',
  int ageOrder = 0,
}) => PendingQuestion(
  machineId: machineId,
  agentId: agentId,
  requestId: requestId,
  answerKey: prompt,
  prompt: prompt,
  options: const ['A', 'B'],
  multi: false,
  since: DateTime.utc(2026, 9, 13).add(Duration(seconds: ageOrder)),
);

Future<void> announceQuestion(
  AppNotifier app,
  String agentId, {
  String requestId = 'question',
  String prompt = 'Which folder?',
}) => app.handleEventForTest('m', {
  'type': 'commander_question',
  'payload': {
    'agentId': agentId,
    'requestId': requestId,
    'questions': [
      {
        'q': prompt,
        'options': ['A', 'B'],
      },
    ],
  },
});

void main() {
  test('questions stay oldest first and search prompt plus machine/project context', () {
    final app = createApp();
    addTearDown(app.dispose);
    final machine = app.machineStates['m']!;
    machine.agents = [
      const Agent(
        id: 'auth',
        name: 'Login',
        engine: 'codex',
        terminalAvailable: true,
        project: AgentProject(
          name: 'Payments',
          cwd: '/work/billing',
          branch: 'fix-login',
        ),
      ),
      const Agent(id: 'docs', name: 'Docs', terminalAvailable: true),
    ];
    machine.blockedAgents['auth'] = waitingQuestion(
      'auth',
      prompt: 'Choose the staging region',
      ageOrder: 1,
    );
    machine.blockedAgents['docs'] = waitingQuestion(
      'docs',
      prompt: 'Publish documentation?',
    );
    final entries = swarmAttentionEntries(app);
    expect(filterSwarmAttention(entries, '  ').map((e) => e.question.agentId), [
      'docs',
      'auth',
    ]);
    for (final query in [
      'staging payments',
      'host region',
      'billing login',
      'stg rgn',
    ]) {
      expect(
        filterSwarmAttention(entries, query).single.question.agentId,
        'auth',
        reason: query,
      );
    }
    expect(filterSwarmAttention(entries, 'absent'), isEmpty);
  });

  test(
    'missing and unavailable terminals remain visible and cannot add a view',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final machine = app.machineStates['m']!;
      machine.agents = [
        const Agent(
          id: 'closed',
          name: 'Closed agent',
          terminalAvailable: false,
        ),
      ];
      machine.blockedAgents['missing'] = waitingQuestion('missing');
      machine.blockedAgents['closed'] = waitingQuestion('closed');
      final entries = swarmAttentionEntries(app);
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.destination.title), [
        'Closed agent',
        'missing',
      ]);
      for (final entry in entries) {
        expect(entry.available, isFalse);
        expect(
          await activateSwarmAttention(
            app,
            entry,
            destinationSwarmId: app.activeSwarmId,
          ),
          isFalse,
        );
      }
      expect(app.panes, isEmpty);
      // A retained view is still useful even when discovery no longer lists it.
      final retained = app.adoptSessionForTest(terminal('missing', []));
      final row = swarmAttentionEntries(app)
          .firstWhere((e) => e.question.agentId == 'missing');
      expect(row.available, isTrue);
      expect(row.destination.hasView, isTrue);
      expect(row.destination.title, retained.session!.agentName);
    },
  );

  test('resolved and replaced question snapshots cannot change focus or membership', () async {
    final app = createApp();
    addTearDown(app.dispose);
    await announceQuestion(app, 'a0');
    final row = swarmAttentionEntries(app).single;
    await app.handleEventForTest('m', {
      'type': 'commander_question_close',
      'payload': {'agentId': 'a0', 'requestId': 'question'},
    });
    expect(
      await activateSwarmAttention(
        app,
        row,
        destinationSwarmId: app.activeSwarmId,
      ),
      isFalse,
    );
    await announceQuestion(
      app,
      'a0',
      requestId: 'replacement',
      prompt: 'Choose a region instead',
    );
    expect(
      await activateSwarmAttention(
        app,
        row,
        destinationSwarmId: app.activeSwarmId,
      ),
      isFalse,
    );
    expect(app.panes, isEmpty);
    expect(app.focusedPaneId, isNull);
  });

  test('shared retained view uses current owner without retrying a taken-over terminal', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final sent = <String>[];
    final session = TerminalSession(
      machineId: 'm',
      agentId: 'a0',
      agentName: 'Retained',
      engineId: 'codex',
      send: (type, _) async {
        sent.add(type);
        return true;
      },
      sendBinary: (_) async => true,
    )..status = TerminalSessionStatus.controlling;
    final pane = app.adoptSessionForTest(session);
    final first = app.activeSwarm;
    app.newSwarm();
    await app.addAgentToSwarm('m', 'a0');
    final second = app.activeSwarm;
    final other = app.adoptSessionForTest(terminal('a1', []));
    app.togglePinPane(pane.id);
    app.toggleZoomPane();
    session.status = TerminalSessionStatus.takenOver;
    final pins = Map.of(second.pinnedSlots);
    await announceQuestion(app, 'a0');
    final row = swarmAttentionEntries(app).single;
    expect(row.destination.swarmId, second.id);
    sent.clear();
    expect(
      await activateSwarmAttention(app, row, destinationSwarmId: second.id),
      isTrue,
    );
    expect(app.activeSwarmId, second.id);
    expect(app.focusedPaneId, pane.id);
    expect(second.zoomedPaneId, pane.id);
    expect(second.panes, [pane, other]);
    expect(first.panes, [pane]);
    expect(second.pinnedSlots, pins);
    expect(pane.session, same(session));
    expect(session.status, TerminalSessionStatus.takenOver);
    expect(sent, isEmpty);
  });

  test('opening a question captures its target and a vanished existing view never becomes Add', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final first = app.activeSwarm;
    await announceQuestion(app, 'a0');
    final unopened = swarmAttentionEntries(app).single;
    expect(unopened.destination.hasView, isFalse);
    app.newSwarm();
    final second = app.activeSwarm;
    expect(
      await activateSwarmAttention(app, unopened, destinationSwarmId: first.id),
      isTrue,
    );
    expect(first.panes.single.agentId, 'a0');
    expect(second.panes, isEmpty);
    expect(app.activeSwarmId, second.id);
    final existing = swarmAttentionEntries(app).single;
    await app.closeSwarm(first.id);
    await announceQuestion(app, 'a0');
    expect(
      await activateSwarmAttention(
        app,
        existing,
        destinationSwarmId: second.id,
      ),
      isFalse,
    );
    expect(second.panes, isEmpty);
  });
}
