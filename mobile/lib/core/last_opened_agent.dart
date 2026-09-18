import 'dart:convert';

import 'local_key_value_store.dart';

/// One agent, named by the machine it runs on — what a relaunch reopens, a pager page shows, and
/// every pane it opens is about.
typedef AgentRef = ({String machineId, String agentId});

/// The agent the phone had on screen, so a relaunch can put the person back on it.
///
/// ⚠️ **In practice only ever overwritten, never cleared.** [forget] still exists and still works,
/// but nothing calls it: it was the pager's way of saying "the terminal was left", back when leaving
/// it meant landing on a list of agents that the next launch could start on instead. There is no
/// such list any more — the terminal is the phone's home screen — so the only question this answers
/// is *which* agent it opens on, and "none" is not one of the answers. A record naming an agent that
/// has since been deleted simply matches nothing, and the home screen falls through to the first
/// agent it can reach.
class LastOpenedAgent {
  LastOpenedAgent(this._storage);

  final LocalKeyValueStore? _storage;
  static const _key = 'phone_last_agent_v1';

  AgentRef? _value;
  Future<void> _writes = Future.value();

  /// What the previous run left, or null. Anything malformed reads as nothing — a missing
  /// preference must never hold the app on its launch screen.
  Future<AgentRef?> read() async {
    try {
      final raw = await _storage?.read(_key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final machineId = decoded['machineId'];
      final agentId = decoded['agentId'];
      if (machineId is! String || machineId.isEmpty) return null;
      if (agentId is! String || agentId.isEmpty) return null;
      return (machineId: machineId, agentId: agentId);
    } catch (_) {
      return null;
    }
  }

  void remember(AgentRef agent) {
    if (_value == agent) return;
    _value = agent;
    final encoded = jsonEncode({
      'machineId': agent.machineId,
      'agentId': agent.agentId,
    });
    _write((storage) => storage.write(_key, encoded));
  }

  /// Clears the record only while it still names [agent].
  ///
  /// A terminal replaced by another one can be disposed AFTER its successor has remembered itself,
  /// and an unconditional clear would then erase the agent actually on screen.
  ///
  /// ⚠️ **Nothing calls this now, and that is the point rather than an oversight.** The pager used
  /// to call it on the way out, back when leaving the terminal meant landing on a list of agents;
  /// the terminal is the home screen now, so there is no "left the terminal" to report and clearing
  /// the record would only cost the next launch its reopen. Kept because the reopen is a flag away
  /// from being turned off again (`_showTabBar` in `phone_shell.dart` restores the list screens),
  /// and this is the half of the pair that would have to come back with it.
  void forget(AgentRef agent) {
    if (_value != agent) return;
    _value = null;
    _write((storage) => storage.delete(_key));
  }

  void _write(Future<void> Function(LocalKeyValueStore storage) write) {
    final storage = _storage;
    if (storage == null) return;
    _writes = _writes.then((_) async {
      try {
        await write(storage);
      } catch (_) {
        // Losing the record only costs the reopen; the terminal itself is unaffected.
      }
    });
  }
}
