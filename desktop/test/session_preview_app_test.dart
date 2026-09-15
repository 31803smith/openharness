import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_state_test.dart' show createApp;

class _RecentConnection extends WsConn {
  _RecentConnection()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'm',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    calls.add(type);
    expect(payload, {'agentId': 'a0', 'n': 3});
    return {
      'agentId': 'a0',
      'asks': ['An earlier request'],
      'events': [
        {'kind': 'summary', 'fullText': 'An existing saved response.'},
      ],
    };
  }
}

void main() {
  testWidgets(
    'preview uses only the existing read API and live text never notifies the workspace',
    (tester) async {
      final conn = _RecentConnection();
      final app = createApp(connectionForTest: (_) => conn);
      final machine = app.machineStates['m']!;
      machine.nodeOnline = true;
      const agent = Agent(id: 'a0', sessionId: 'current', name: 'A');
      machine.agents = [agent];
      final key = app.previewKey('m', agent);
      app.sessionPreviews.warm([key]);
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        app.sessionPreviews.read(key)!.response,
        'An existing saved response.',
      );
      expect(conn.calls, ['agent_recent']);
      Future<void> event(String type, Map<String, dynamic> payload) =>
          app.handleEventForTest('m', {
            'type': type,
            'payload': {'agentId': 'a0', 'sessionId': 'current', ...payload},
          });
      await event('turn_started', {'userMessage': 'The active task'});
      var workspaceChanges = 0;
      app.addListener(() => workspaceChanges++);
      for (var i = 0; i < 100; i++) {
        await event('text_delta', {'content': 'Progress $i'});
      }
      await event('tool_start', {'tool': 'Read'});
      await tester.pump(const Duration(milliseconds: 80));
      expect(workspaceChanges, 0);
      expect(app.sessionPreviews.read(key)!.liveText, 'Progress 99');
      expect(app.sessionPreviews.read(key)!.activity, 'Read');
      await event('text_delta', {
        'sessionId': 'old',
        'content': 'Stale session',
      });
      await event('turn_ended', {'sessionId': 'old'});
      expect(app.sessionPreviews.read(key)!.liveText, 'Progress 99');
      expect(machine.processingAgentIds, contains('a0'));
      expect(conn.calls, ['agent_recent']);
      app.dispose();
    },
  );
}
