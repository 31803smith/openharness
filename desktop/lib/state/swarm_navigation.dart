import 'package:flutter/foundation.dart' show listEquals;

import '../core/fuzzy_match.dart';
import '../core/models.dart';
import 'app_state.dart';
import 'swarm.dart';
import 'swarm_catalog.dart';

String swarmDestinationId(String id) => 'swarm:$id';
String agentDestinationId(String machineId, String agentId) =>
    'agent:$machineId\u0000$agentId';

/// Session-local history contains identities only, never terminal buffers or
/// controllers. Repeated discovery/output notifications do not reorder it.
class SwarmNavigationHistory {
  static const capacity = 64;
  final _recent = <String>[];
  (String, int?)? _location;
  final _trail = <(String, int?)>[];
  int _cursor = -1;
  bool _traversing = false;
  int _revision = 0;
  List<Object?>? _menuPresentation;
  List<SwarmDestination> _menuDestinations = const [];
  List<String> get recent => List.unmodifiable(_recent);

  void record(AppNotifier app) {
    final location = (app.activeSwarmId, app.focusedPaneId);
    if (_location == location) return;
    if (!_traversing) {
      _trail.removeRange(_cursor + 1, _trail.length);
      _trail.add(location);
      if (_trail.length > capacity * 2) _trail.removeAt(0);
      _cursor = _trail.length - 1;
    }
    _revision++;
    if (_location?.$1 != location.$1) {
      _remember(swarmDestinationId(location.$1));
    }
    final pane = app.focusedPane;
    if (pane?.agentId != null) {
      _remember(agentDestinationId(pane!.machineId, pane.agentId!));
    }
    _location = location;
  }

  int? _next(AppNotifier app, int direction) {
    for (
      var i = _cursor + direction;
      i >= 0 && i < _trail.length;
      i += direction
    ) {
      final (swarmId, paneId) = _trail[i];
      final swarm = app.swarms.where((s) => s.id == swarmId).firstOrNull;
      if (swarm == null ||
          (paneId == null && swarm.panes.isNotEmpty) ||
          (paneId != null && !swarm.panes.any((p) => p.id == paneId))) {
        continue;
      }
      if ((swarmId, paneId) != _location) return i;
    }
    return null;
  }

  bool canGoBack(AppNotifier app) => _next(app, -1) != null;
  bool canGoForward(AppNotifier app) => _next(app, 1) != null;

  /// Changes focus only; closed views are skipped without attaching a stream.
  void step(AppNotifier app, int direction) {
    if (direction != -1 && direction != 1) return;
    final index = _next(app, direction);
    if (index == null) return;
    final (swarmId, paneId) = _trail[index];
    _cursor = index;
    _traversing = true;
    try {
      app.selectSwarm(swarmId, attachPending: false);
      if (paneId != null) app.focusPane(paneId, reveal: true);
    } finally {
      _traversing = false;
    }
  }

  void _remember(String id) {
    _recent.remove(id);
    _recent.insert(0, id);
    if (_recent.length > capacity) _recent.removeLast();
  }

  /// Native menus are ready before opening. Ordinary terminal output reuses
  /// this snapshot; navigation, membership and discovery invalidate it.
  List<SwarmDestination> menuDestinations(AppNotifier app) {
    final presentation = <Object?>[
      _revision,
      app.activeSwarmId,
      app.focusedPaneId,
      for (final swarm in app.swarms) ...[
        swarm.id,
        swarm.name,
        for (final pane in swarm.panes)
          (pane.id, pane.machineId, pane.agentId, pane.session?.agentName),
      ],
      for (final machine in app.machineStates.values)
        (
          machine.machine,
          machine.nodeOnline,
          machine.agents,
          machine.agents.length,
          machine.localEndpoint?.agentProjects,
          machine.localProjects,
        ),
    ];
    if (listEquals(_menuPresentation, presentation)) return _menuDestinations;
    _menuPresentation = presentation;
    final catalog = {
      for (final entry in swarmDestinations(app, recent: _recent))
        if (entry.hasView) entry.id: entry,
    };
    return _menuDestinations = List.unmodifiable([
      for (final id in _recent) ?catalog[id],
    ]);
  }
}

/// A searchable snapshot. Resolving a result again at activation prevents live
/// discovery or a closed tab from redirecting an action to unrelated work.
class SwarmDestination {
  SwarmDestination({
    required this.id,
    required this.title,
    required this.detail,
    required this.swarmId,
    required this.current,
    this.machineId,
    this.machineLabel = '',
    this.agentId,
    this.engine,
    this.closedId,
    this.commandId,
    this.shortcut,
    this.projectId,
    this.members = const {},
    Iterable<String?> searchFields = const [],
  }) : fields = [
         title.toLowerCase(),
         ...searchFields.whereType<String>().map((s) => s.toLowerCase()),
       ];

  final String id, title, detail, machineLabel;
  final String? swarmId, machineId, agentId, engine;
  final String? closedId;
  final String? commandId, shortcut;
  bool get isCommand => commandId != null;
  final String? projectId;
  final Set<String> members;
  final bool current;
  final List<String> fields;
  bool get isProject => projectId != null;
  bool get isMachine => agentId == null && machineId != null && !isProject;
  bool get isGroup => isProject || isMachine;
  bool get isSwarm => agentId == null && !isGroup && !isCommand;
  bool get hasView => swarmId != null;
}

enum SwarmSearchAction { open, addHere }

class SwarmSearchSelection {
  const SwarmSearchSelection(
    this.destination, [
    this.action = SwarmSearchAction.open,
  ]);
  final SwarmDestination destination;
  final SwarmSearchAction action;
}

/// One catalog for all search entry points. Terminal output leaves these
/// normalized snapshots intact; only discovery, membership or metadata changes
/// rebuild them. Typing never reads a folder or asks a machine for data.
class SwarmSearchCatalog {
  List<Object?>? _presentation;
  List<SwarmDestination> _entries = const [];

  List<SwarmDestination> read(
    AppNotifier app,
    List<SavedSwarmProject> projects, {
    List<String> recent = const [],
  }) {
    final presentation = <Object?>[
      app.activeSwarmId,
      app.focusedPaneId,
      ...recent,
      ...projects,
      for (final swarm in app.swarms) ...[
        swarm.id,
        swarm.name,
        for (final pane in swarm.panes)
          (pane.id, pane.machineId, pane.agentId, pane.session?.agentName),
      ],
      for (final machine in app.machineStates.values)
        (
          machine.machine,
          machine.nodeOnline,
          machine.needsLink,
          machine.agents,
          machine.agents.length,
          machine.localEndpoint?.agentProjects,
          machine.localProjects,
        ),
    ];
    if (listEquals(_presentation, presentation)) return _entries;
    _presentation = presentation;
    final entries = swarmDestinations(app, recent: recent);
    final agentsById = {
      for (final entry in entries)
        if (entry.agentId != null) entry.id: entry,
    };
    final machineMembers = <String, Set<String>>{};
    for (final entry in agentsById.values) {
      (machineMembers[entry.machineId!] ??= {}).add(entry.id);
    }
    final groups = swarmProjects(app, projects);
    for (final machine in app.machineStates.values) {
      final id = machine.machine.machineId;
      final members = machineMembers[id] ?? const <String>{};
      entries.add(
        SwarmDestination(
          id: 'machine:$id',
          title: machine.machine.displayName,
          detail: [
            'Machine',
            _agentCountLabel(members),
            if (machine.needsLink)
              'Link required'
            else if (machine.nodeOnline == false)
              'Offline',
          ].join(' · '),
          machineId: id,
          swarmId: null,
          current: false,
          members: Set.unmodifiable(members),
        ),
      );
    }
    for (final group in groups) {
      final members = {
        for (final entry in group.agents)
          if (agentsById.containsKey(
            agentDestinationId(entry.machineId, entry.agent.id),
          ))
            agentDestinationId(entry.machineId, entry.agent.id),
      };
      entries.add(
        SwarmDestination(
          id: 'project:${group.id}',
          projectId: group.id,
          title: group.name,
          detail: 'Project · ${_agentCountLabel(members)}',
          swarmId: null,
          current: false,
          members: Set.unmodifiable(members),
          searchFields: {
            group.saved?.path,
            for (final entry in group.agents) ...[
              entry.machine.machine.displayName,
              entry.project?.cwd,
              entry.project?.branch,
            ],
          },
        ),
      );
      // Explicit project associations from older daemons are searchable too.
      final name = group.name.toLowerCase();
      for (final id in members) {
        final entry = agentsById[id]!;
        if (!entry.fields.contains(name)) entry.fields.add(name);
      }
    }
    return _entries = List.unmodifiable(entries);
  }
}

Future<bool> activateSwarmSearchSelection(
  AppNotifier app,
  SwarmSearchSelection selection, {
  required String destinationSwarmId,
  List<SavedSwarmProject> projects = const [],
}) async {
  final destination = selection.destination;
  if (selection.action == SwarmSearchAction.open && !destination.isGroup) {
    return activateSwarmDestination(
      app,
      destination,
      destinationSwarmId: destinationSwarmId,
    );
  }
  if (selection.action == SwarmSearchAction.addHere) {
    if (destination.agentId == null ||
        !app.swarms.any((s) => s.id == destinationSwarmId)) {
      return false;
    }
    final live = swarmDestinations(app)
        .where((e) => e.id == destination.id)
        .firstOrNull;
    if (live == null) return false;
    await app.addAgentToSwarm(
      destination.machineId!,
      destination.agentId!,
      swarmId: destinationSwarmId,
    );
    if (app.activeSwarmId == destinationSwarmId) {
      app.revealAgentView(
        destination.machineId!,
        destination.agentId!,
        preferredSwarmId: destinationSwarmId,
      );
    }
    return app.swarms.any(
      (s) =>
          s.id == destinationSwarmId &&
          s.panes.any(
            (p) =>
                p.machineId == destination.machineId &&
                p.agentId == destination.agentId,
          ),
    );
  }
  if (!canOpenSwarmGroup(
    app,
    destination,
    destinationSwarmId: destinationSwarmId,
  )) {
    return false;
  }
  final entries = SwarmSearchCatalog().read(app, projects);
  final group = entries
      .where((entry) => entry.id == destination.id)
      .firstOrNull;
  // Keep the membership represented by the selected result. Discovery may
  // change while this action is waiting to run.
  if (group == null || !group.members.containsAll(destination.members)) {
    return false;
  }
  final agents = [
    for (final entry in entries)
      if (entry.agentId != null && destination.members.contains(entry.id))
        (machineId: entry.machineId!, agentId: entry.agentId!),
  ];
  if (agents.length != destination.members.length) return false;
  final existing = _matchingGroupSwarm(app, destination);
  if (existing != null) {
    app.selectSwarm(existing.id);
    final focus = existing.focusedPaneId;
    if (focus != null) app.focusPane(focus);
    return true;
  }
  final target = app.swarms
      .where((swarm) => swarm.id == destinationSwarmId)
      .firstOrNull;
  if (target != null && target.panes.isEmpty) {
    app.selectSwarm(target.id);
  } else {
    app.newSwarm(name: group.title);
  }
  await app.seedSwarm(group.title, agents);
  return true;
}

bool canOpenSwarmGroup(
  AppNotifier app,
  SwarmDestination destination, {
  required String destinationSwarmId,
}) =>
    destination.isGroup &&
    destination.members.length <= AppNotifier.maxPanes &&
    (_matchingGroupSwarm(app, destination) != null ||
        app.swarms.any(
          (swarm) => swarm.id == destinationSwarmId && swarm.panes.isEmpty,
        ) ||
        app.swarms.length < AppNotifier.maxSwarms);

Swarm? _matchingGroupSwarm(AppNotifier app, SwarmDestination destination) {
  bool matches(Swarm swarm) =>
      // Empty tabs only match their name; two empty projects are distinct.
      (destination.members.isNotEmpty || swarm.name == destination.title) &&
      swarm.panes.length == destination.members.length &&
      swarm.panes.every(
        (pane) =>
            pane.agentId != null &&
            destination.members.contains(
              agentDestinationId(pane.machineId, pane.agentId!),
            ),
      );
  return app.swarms
          .where((swarm) => swarm.name == destination.title && matches(swarm))
          .firstOrNull ??
      (matches(app.activeSwarm) ? app.activeSwarm : null) ??
      app.swarms.where(matches).firstOrNull;
}

String _agentCountLabel(Iterable<String?> ids) {
  final count = ids.whereType<String>().length;
  return '$count ${count == 1 ? 'agent' : 'agents'}';
}

String _swarmMachineLabel(AppNotifier app, Iterable<String> machineIds) {
  final ids = machineIds.toSet();
  if (ids.isEmpty) return '';
  if (ids.length > 1) return '${ids.length} machines';
  final id = ids.single;
  return app.stateOf(id)?.machine.displayName ?? id;
}

List<SwarmDestination> closedWorkDestinations(AppNotifier app) => [
  for (final entry in app.closedHistory)
    if (entry is ClosedSwarm)
      SwarmDestination(
        id: entry.historyId,
        closedId: entry.historyId,
        title: entry.name,
        machineLabel: _swarmMachineLabel(app, [
          for (final pane in entry.panes)
            if (pane.agentId != null) pane.machineId,
        ]),
        detail:
            '${_agentCountLabel(entry.panes.map((pane) => pane.agentId))} · Recently closed',
        swarmId: null,
        current: false,
      )
    else if (entry is ClosedAgent)
      SwarmDestination(
        id: entry.historyId,
        closedId: entry.historyId,
        title: entry.name,
        detail: '${entry.machineName} · ${entry.swarmName} · Recently closed',
        swarmId: null,
        machineId: entry.machineId,
        machineLabel:
            app.stateOf(entry.machineId)?.machine.displayName ??
            entry.machineName,
        agentId: entry.agentId,
        engine: entry.engine,
        current: false,
        searchFields: [entry.machineName, entry.swarmName, entry.engine],
      ),
];

List<SwarmDestination> swarmDestinations(
  AppNotifier app, {
  List<String> recent = const [],
}) {
  final owners = <String, List<Swarm>>{};
  final agents = <String, (MachineState, Agent)>{};
  final result = <SwarmDestination>[];
  final recency = {for (var i = 0; i < recent.length; i++) recent[i]: i};
  for (final machine in app.machineStates.values) {
    for (final agent in machine.agents) {
      agents[agentDestinationId(machine.machine.machineId, agent.id)] = (
        machine,
        agent,
      );
    }
  }
  for (final swarm in app.swarms) {
    final context = <String?>[];
    for (final pane in swarm.panes) {
      if (pane.agentId == null) continue;
      final id = agentDestinationId(pane.machineId, pane.agentId!);
      (owners[id] ??= []).add(swarm);
      final row = agents[id];
      final project = row?.$1.projectOf(row.$2);
      context.addAll([
        row?.$1.machine.displayName,
        row?.$2.name ?? pane.session?.agentName,
        project?.name,
        project?.branch,
        project?.cwd,
      ]);
    }
    result.add(
      SwarmDestination(
        id: swarmDestinationId(swarm.id),
        title: swarm.name,
        machineLabel: _swarmMachineLabel(app, [
          for (final pane in swarm.panes)
            if (pane.agentId != null) pane.machineId,
        ]),
        detail: _agentCountLabel(swarm.panes.map((pane) => pane.agentId)),
        swarmId: swarm.id,
        current: swarm.id == app.activeSwarmId,
        searchFields: context.toSet(),
      ),
    );
  }
  for (final id in {...owners.keys, ...agents.keys}) {
    final memberships = owners[id] ?? const <Swarm>[];
    final row = agents[id];
    if (memberships.isEmpty && row?.$2.terminalAvailable != true) continue;
    Swarm? owner;
    var ownerRank = 1000;
    for (final candidate in memberships) {
      final rank = candidate.id == app.activeSwarmId
          ? -1
          : recency[swarmDestinationId(candidate.id)] ?? 999;
      if (rank < ownerRank) {
        owner = candidate;
        ownerRank = rank;
      }
    }
    final pane = owner?.panes
        .where(
          (p) =>
              p.agentId != null &&
              agentDestinationId(p.machineId, p.agentId!) == id,
        )
        .firstOrNull;
    final machineId = row?.$1.machine.machineId ?? pane!.machineId;
    final agentId = row?.$2.id ?? pane!.agentId!;
    final machine = app.machineStates[machineId];
    final project = row?.$1.projectOf(row.$2);
    final machineName = machine?.machine.displayName ?? machineId;
    final engine = row?.$2.engine ?? pane?.session?.engineId;
    result.add(
      SwarmDestination(
        id: id,
        title: row?.$2.name ?? pane?.session?.agentName ?? agentId,
        detail: [
          machineName,
          project?.name,
          project?.branch,
          owner?.name,
          if (machine?.nodeOnline == false) 'Offline',
        ].whereType<String>().where((s) => s.isNotEmpty).toSet().join(' · '),
        swarmId: owner?.id,
        machineId: machineId,
        machineLabel: machineName,
        agentId: agentId,
        engine: engine,
        current:
            owner?.id == app.activeSwarmId && pane?.id == app.focusedPaneId,
        searchFields: [
          machineName,
          project?.name,
          project?.branch,
          project?.cwd,
          engine,
          ...memberships.map((s) => s.name),
        ],
      ),
    );
  }
  return result;
}

final _words = RegExp(r'\s+');

List<String> swarmQueryTerms(String query) {
  final needle = query.trim().toLowerCase();
  return needle.isEmpty ? const [] : needle.split(_words);
}

/// The same field preference drives ranking and the visible match emphasis.
/// A good metadata match should not paint unrelated fuzzy title characters.
int? swarmFieldMatchScore(String field, String term, {required bool title}) {
  final offset = field.indexOf(term);
  final spread = offset >= 0 ? 0 : subsequenceSpread(field, term);
  if (spread == null) return null;
  return (title ? 0 : 64) +
      (field == term
          ? 0
          : offset == 0
          ? 8
          : offset > 0
          ? 16
          : 128 + spread);
}

/// Each word may match a different field, in either order: "mini auth" and
/// "auth mini" both find Auth on Mac mini. Names outrank incidental metadata.
List<SwarmDestination> rankSwarmDestinations(
  List<SwarmDestination> all,
  String query, {
  List<String> recent = const [],
}) {
  final needle = query.trim().toLowerCase();
  final terms = swarmQueryTerms(query);
  final recency = {for (var i = 0; i < recent.length; i++) recent[i]: i};
  final ranked = <({SwarmDestination entry, int score})>[];
  for (final entry in all) {
    if (entry.fields.first == needle) {
      ranked.add((entry: entry, score: -1));
      continue;
    }
    var total = 0;
    for (final term in terms) {
      int? best;
      for (var i = 0; i < entry.fields.length; i++) {
        final field = entry.fields[i];
        final score = swarmFieldMatchScore(field, term, title: i == 0);
        if (score == null) continue;
        if (best == null || score < best) best = score;
        // Every remaining field is metadata, whose best possible score is 64.
        // An exact/prefix/substring title match already beats that; an exact
        // metadata match ties it. Neither needs further field scans.
        if (best <= 64) break;
      }
      if (best == null) {
        total = -1;
        break;
      }
      total += best;
    }
    if (total >= 0) {
      ranked.add((entry: entry, score: total));
    }
  }
  int tier(SwarmDestination e) => !e.hasView
      ? 3
      : e.current
      ? 2
      : recency.containsKey(e.id)
      ? 0
      : 1;
  ranked.sort((a, b) {
    var order = a.score.compareTo(b.score);
    if (order == 0 && needle.isEmpty) {
      order = tier(a.entry).compareTo(tier(b.entry));
    }
    if (order == 0) {
      order = (recency[a.entry.id] ?? 999).compareTo(
        recency[b.entry.id] ?? 999,
      );
    }
    if (order == 0) {
      order = a.entry.fields.first.compareTo(b.entry.fields.first);
    }
    return order == 0 ? a.entry.id.compareTo(b.entry.id) : order;
  });
  return [for (final row in ranked) row.entry];
}

Future<bool> activateSwarmDestination(
  AppNotifier app,
  SwarmDestination destination, {
  required String destinationSwarmId,
}) async {
  // Workspace commands are owned by the screen, never resolved as an agent.
  if (destination.isCommand) return false;
  if (destination.closedId != null) {
    return app.reopenClosed(historyId: destination.closedId);
  }
  if (destination.isSwarm) {
    if (!app.swarms.any((s) => s.id == destination.swarmId)) return false;
    app.selectSwarm(destination.swarmId!, attachPending: false);
    final pane = app.focusedPane;
    if (pane != null) app.focusPane(pane.id, reveal: true);
    return true;
  }
  if (app.revealAgentView(
    destination.machineId!,
    destination.agentId!,
    preferredSwarmId: destination.swarmId,
  )) {
    return true;
  }
  // An existing-view result that disappeared must never become an Add action.
  if (destination.hasView) return false;
  final agent = app.machineStates[destination.machineId]?.agents
      .where((a) => a.id == destination.agentId)
      .firstOrNull;
  if (agent?.terminalAvailable != true ||
      !app.swarms.any((s) => s.id == destinationSwarmId)) {
    return false;
  }
  await app.addAgentToSwarm(
    destination.machineId!,
    destination.agentId!,
    swarmId: destinationSwarmId,
  );
  if (app.activeSwarmId == destinationSwarmId) {
    final pane = app.focusedPane;
    if (pane?.machineId == destination.machineId &&
        pane?.agentId == destination.agentId) {
      app.focusPane(pane!.id, reveal: true);
    }
  }
  return app.swarms.any(
    (s) =>
        s.id == destinationSwarmId &&
        s.panes.any(
          (p) =>
              p.machineId == destination.machineId &&
              p.agentId == destination.agentId,
        ),
  );
}
