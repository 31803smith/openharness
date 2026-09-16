import 'dart:convert';

import 'local_key_value_store.dart';

typedef AgentRef = ({String machineId, String agentId});

/// The agent the phone had on screen, so a relaunch can put the person back on it.
///
/// ⚠️ **Cleared when the terminal is LEFT, not when the app goes away.** A process the OS kills —
/// swiped out of recents, reclaimed in the background — never runs `dispose`, so the record it
/// leaves behind is exactly "the agent that was open when the app closed". Backing out of the
/// terminal does run it, and then there is nothing to reopen: the person had already gone back to
/// the list.
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
