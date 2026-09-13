import 'pane_preset.dart';
import 'pane_arrangement.dart';
import 'terminal_pane.dart';

/// A named arrangement of agents. Membership never owns the agent process.
/// Shared agents reuse the same pane/session across swarms, so the daemon has
/// exactly one controller and switching tabs cannot take over our own stream.
class Swarm {
  Swarm({required this.id, this.name = 'New swarm'});

  final String id;
  String name;
  final List<TerminalPane> panes = [];
  final Map<int, PanePreset> presets = {};
  final Map<String, PaneArrangement> paneSizes = {};
  PaneArrangement? arranged;
  String? arrangedKey;
  int? focusedPaneId;
  int? zoomedPaneId;
  int? previousPaneId;
  int? gridColumns;
  final Map<int, int> pinnedSlots = {};

  void remove(TerminalPane pane) {
    final index = panes.indexOf(pane);
    if (index < 0) return;
    panes.removeAt(index);
    pinnedSlots.remove(pane.id);
    if (focusedPaneId == pane.id) {
      focusedPaneId = panes.isEmpty
          ? null
          : panes[index.clamp(0, panes.length - 1)].id;
    }
    if (zoomedPaneId == pane.id) zoomedPaneId = null;
    if (previousPaneId == pane.id) previousPaneId = null;
  }

  Map<String, Object?> toJson() {
    final agents = panes
        .where((p) => p.agentId != null)
        .toList(growable: false);
    return {
      'id': id,
      'name': name,
      'focus': agents.indexWhere((p) => p.id == focusedPaneId),
      'previousFocus': agents.indexWhere((p) => p.id == previousPaneId),
      'zoom': agents.indexWhere((p) => p.id == zoomedPaneId),
      'presets': {for (final e in presets.entries) '${e.key}': e.value.id},
      if (paneSizes.isNotEmpty)
        'paneSizes': {
          for (final e in paneSizes.entries) e.key: e.value.toJson(),
        },
      'panes': [
        for (final p in agents)
          PaneLayoutEntry(
            machineId: p.machineId,
            agentId: p.agentId!,
            composerVisible: p.composerVisible,
            pinnedSlot: pinnedSlots[p.id],
          ).toJson(),
      ],
    };
  }
}

/// Session-free history: closing a view never owns the agent's lifetime.
sealed class ClosedWork {
  const ClosedWork({required this.historyId});
  final String historyId;
}

class ClosedAgent extends ClosedWork {
  ClosedAgent(
    TerminalPane pane,
    Swarm swarm, {
    required super.historyId,
    required this.name,
    required this.machineName,
    required this.engine,
  }) : swarmId = swarm.id,
       swarmName = swarm.name,
       index = swarm.panes.indexOf(pane),
       machineId = pane.machineId,
       agentId = pane.agentId!,
       composerVisible = pane.composerVisible,
       pinnedSlot = swarm.pinnedSlots[pane.id],
       zoomed = swarm.zoomedPaneId == pane.id;

  final String swarmId, swarmName, machineId, machineName, agentId, name;
  final String? engine;
  final int index;
  final bool composerVisible, zoomed;
  final int? pinnedSlot;
}

/// Terminal buffers and controllers are released normally; a reopened view
/// reuses any live peer.
class ClosedSwarm extends ClosedWork {
  ClosedSwarm(
    Swarm swarm, {
    required super.historyId,
    required this.index,
    Swarm? replacement,
  }) : id = swarm.id,
       name = swarm.name,
       gridColumns = swarm.gridColumns,
       focus = swarm.panes.indexWhere((p) => p.id == swarm.focusedPaneId),
       previousFocus = swarm.panes.indexWhere(
         (p) => p.id == swarm.previousPaneId,
       ),
       zoom = swarm.panes.indexWhere((p) => p.id == swarm.zoomedPaneId),
       presets = Map.unmodifiable(swarm.presets),
       paneSizes = Map.unmodifiable(swarm.paneSizes),
       panes = List.unmodifiable([
         for (final pane in swarm.panes)
           (
             machineId: pane.machineId,
             agentId: pane.agentId,
             composerVisible: pane.composerVisible,
             pinnedSlot: swarm.pinnedSlots[pane.id],
           ),
       ]),
       replacementId = replacement?.id;

  final String id;
  final String name;
  final int index;
  final int? gridColumns;
  final int focus;
  final int previousFocus;
  final int zoom;
  final Map<int, PanePreset> presets;
  final Map<String, PaneArrangement> paneSizes;
  final List<
    ({String machineId, String? agentId, bool composerVisible, int? pinnedSlot})
  >
  panes;
  final String? replacementId;

  bool replacesUntouchedWelcome(Swarm swarm) =>
      swarm.id == replacementId &&
      swarm.name == 'New swarm' &&
      swarm.panes.isEmpty &&
      swarm.presets.isEmpty;
}
