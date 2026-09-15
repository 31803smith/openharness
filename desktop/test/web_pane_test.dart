// A harness's viewer tile: opened to the right of its agent's terminal when the
// agent's frame names a viewer, navigated when that URL changes, left closed
// once the person closes it, and taken down with the agent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/terminal_pane.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/web_pane_panel.dart';

import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

Map<String, dynamic> _frame(String id, {String? viewerUrl}) => {
  'id': id,
  'name': 'Agent $id',
  'engine': 'claude',
  'dsh': 'autonomous/circuit',
  'dshName': 'Circuit',
  'viewerUrl': ?viewerUrl,
  'terminal': {
    'available': true,
    'runtimes': [
      {'backend': 'tmux', 'paneId': '%1'},
    ],
  },
};

Future<void> _synced(AppNotifier app, String id, {String? viewerUrl}) =>
    app.handleEventForTest('m', {
      'type': 'agent_synced',
      'payload': {'agent': _frame(id, viewerUrl: viewerUrl)},
    });

List<TerminalPane> _viewers(AppNotifier app) =>
    app.panes.where((pane) => pane.isWeb).toList();

void main() {
  test(
    'a viewer opens to the right of its agent and follows the URL',
    () async {
      final app = createApp();
      addTearDown(app.dispose);
      final input = <TerminalBinaryFrame>[];
      final first = app.adoptSessionForTest(terminal('a0', input));
      final second = app.adoptSessionForTest(terminal('a1', input));
      app.focusPane(first.id);

      // A frame with no viewer opens nothing.
      await _synced(app, 'a0');
      expect(_viewers(app), isEmpty);

      await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/');
      final viewer = _viewers(app).single;
      expect(viewer.ownerAgentId, 'a0');
      expect(
        viewer.agentId,
        isNull,
        reason: 'a viewer is not the agent\'s tile',
      );
      expect(viewer.url, 'http://127.0.0.1:4179/');
      expect(app.panes.map((p) => p.id), [first.id, viewer.id, second.id]);
      expect(app.focusedPaneId, first.id, reason: 'never steals focus');

      // The same URL again is nothing new; a different one navigates in place.
      await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/');
      expect(_viewers(app).single.id, viewer.id);
      await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/?file=a.step');
      expect(_viewers(app).single.id, viewer.id);
      expect(_viewers(app).single.url, 'http://127.0.0.1:4179/?file=a.step');
      expect(app.panes.length, 3);

      // A frame that drops the viewer takes the tile down.
      await _synced(app, 'a0');
      expect(_viewers(app), isEmpty);
      expect(app.panes.map((p) => p.id), [first.id, second.id]);
    },
  );

  test('a viewer closed by hand stays closed until the URL changes', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final input = <TerminalBinaryFrame>[];
    app.adoptSessionForTest(terminal('a0', input));
    await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/');
    final viewer = _viewers(app).single;
    await app.closePane(viewer.id);
    expect(_viewers(app), isEmpty);
    await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/');
    expect(_viewers(app), isEmpty, reason: 'the same page does not pop back');
    await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4180/');
    expect(_viewers(app).single.url, 'http://127.0.0.1:4180/');
  });

  test('a viewer is never persisted, and goes with its agent', () async {
    final app = createApp();
    addTearDown(app.dispose);
    final input = <TerminalBinaryFrame>[];
    app.adoptSessionForTest(terminal('a0', input));
    await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/');
    expect(_viewers(app), hasLength(1));
    final saved = app.activeSwarm.toJson();
    expect((saved['panes'] as List).length, 1);
    expect(saved.toString(), isNot(contains('4179')));

    await app.handleEventForTest('m', {
      'type': 'agent_deleted',
      'agentId': 'a0',
      'payload': {'agentId': 'a0'},
    });
    expect(app.panes, isEmpty);
  });

  test('a viewer waits for a terminal tile to hang beside', () async {
    final app = createApp();
    addTearDown(app.dispose);
    await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/');
    expect(app.panes, isEmpty, reason: 'no terminal on any desk');
    await app.addAgentToSwarm('m', 'a0');
    expect(app.panes.map((p) => p.isWeb), [false, true]);
  });

  testWidgets('the tile renders a header and, under test, the URL in words', (
    tester,
  ) async {
    final app = createApp();
    addTearDown(app.dispose);
    app.stateOf('m')!.nodeOnline = true;
    final input = <TerminalBinaryFrame>[];
    app.adoptSessionForTest(terminal('a0', input));
    await mount(tester, app);
    await _synced(app, 'a0', viewerUrl: 'http://127.0.0.1:4179/');
    await tester.pump();
    expect(WebPanePanel.webviewAvailable, isFalse);
    expect(find.byType(WebPanePanel), findsOneWidget);
    expect(find.byKey(const ValueKey('web-pane-placeholder')), findsOneWidget);
    expect(find.text('http://127.0.0.1:4179/'), findsOneWidget);
    expect(find.textContaining('Viewer'), findsWidgets);
    // Its own close control, and no way to end an agent from it.
    expect(find.byTooltip('Close viewer'), findsOneWidget);
    expect(
      find.byTooltip('Stop Agent'),
      findsOneWidget,
      reason: 'the terminal keeps its own',
    );
    await tester.tap(find.byTooltip('Close viewer'));
    await tester.pump();
    expect(_viewers(app), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
