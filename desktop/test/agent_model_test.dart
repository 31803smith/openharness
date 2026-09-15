import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';

void main() {
  test('uses explicit terminal availability from a new CLI', () {
    final dormantPane = Agent.fromJson({
      'id': 'agent-1',
      'name': 'Agent',
      'status': 'offline',
      'terminal': {
        'available': true,
        'runtimes': [
          {'backend': 'tmux', 'paneId': '%1'},
        ],
      },
    });
    final stalePane = Agent.fromJson({
      'id': 'agent-2',
      'name': 'Stale',
      'terminal': {
        'available': false,
        'runtimes': [
          {'backend': 'tmux', 'paneId': '%2'},
        ],
      },
    });

    expect(dormantPane.terminalAvailable, isTrue);
    expect(stalePane.terminalAvailable, isFalse);
  });

  test('falls back to tmux runtime presence for an older CLI', () {
    final agent = Agent.fromJson({
      'id': 'agent-1',
      'name': 'Legacy',
      'terminal': {
        'runtimes': [
          {'backend': 'tmux', 'paneId': '%1'},
        ],
      },
    });

    expect(agent.terminalAvailable, isTrue);
    expect(agent.launchState, 'ready');
  });

  test('parses a sanitized asynchronous launch failure', () {
    final agent = Agent.fromJson({
      'id': 'agent-1',
      'name': 'Failed agent',
      'launch': {
        'state': 'failed',
        'error': 'ENGINE_DID_NOT_START',
        'detail': 'Engine exited\nsee terminal',
      },
    });

    expect(agent.launchState, 'failed');
    expect(agent.launchError, 'ENGINE_DID_NOT_START');
    expect(agent.launchDetail, 'Engine exited see terminal');
  });

  group('web search on a Local model', () {
    Agent onGrid(Map<String, Object?> grid) => Agent.fromJson({
      'id': 'agent-1',
      'name': 'Local',
      'engine': 'claude',
      'grid': {'baseUrl': 'https://grid.example/grid-abc/relay', ...grid},
    });

    test('reads the status off the grid block', () {
      expect(onGrid({'model': 'qwen', 'webSearch': 'on'}).gridWebSearch, GridWebSearch.on);
      expect(
        onGrid({'model': 'qwen', 'webSearch': 'unavailable'}).gridWebSearch,
        GridWebSearch.unavailable,
      );
      expect(
        onGrid({'model': 'qwen', 'webSearch': 'unsupported'}).gridWebSearch,
        GridWebSearch.unsupported,
      );
    });

    test('has nothing to say when the daemon said nothing, or said a word it does not know', () {
      // An older daemon, or a grid agent the daemon merely discovered: no field at all.
      expect(onGrid({'model': 'qwen'}).gridWebSearch, isNull);
      // A newer daemon with a fourth word: not printed verbatim, not guessed at.
      expect(onGrid({'model': 'qwen', 'webSearch': 'throttled'}).gridWebSearch, isNull);
      expect(onGrid({'model': 'qwen', 'webSearch': 7}).gridWebSearch, isNull);
    });

    test('has nothing to say off a grid', () {
      final own = Agent.fromJson({'id': 'agent-2', 'name': 'Own', 'grid': null});
      expect(own.gridModel, isNull);
      expect(own.gridWebSearch, isNull);
    });

    test('each degraded status is one sentence; on is none', () {
      expect(GridWebSearch.unavailable.sentence, 'Web search unavailable');
      expect(
        GridWebSearch.unsupported.sentence,
        'Web search not supported by this engine',
      );
      expect(GridWebSearch.on.sentence, isNull);
    });
  });
}
