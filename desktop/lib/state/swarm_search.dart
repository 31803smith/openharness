import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../terminal/search_output_preview.dart';

import 'app_state.dart';
import 'pane_arrangement.dart';
import 'swarm_catalog.dart';
import 'swarm_navigation.dart';

/// One search session, shared by the native/Flutter input and its results.
/// Keystrokes only filter the cached catalog; they never query a machine.
class SwarmSearchController extends ChangeNotifier {
  SwarmSearchController(
    this.app,
    this.recent, {
    this.projects,
    this.history,
    this.commands,
    this.adding = false,
    this.navigating = false,
    this.split,
  }) : targetId = app.activeSwarmId,
       targetName = app.activeSwarm.name {
    _refresh();
    app.addListener(_refresh);
    projects?.addListener(_refresh);
  }

  final AppNotifier app;
  final List<String> recent;
  final SwarmProjectStore? projects;
  final SwarmNavigationHistory? history;

  /// Availability is read from workspace state and rechecked at activation.
  /// Commands never enter the ordinary agent/swarm catalog or History.
  final List<SwarmDestination> Function()? commands;
  final bool adding;
  final bool navigating;
  final PaneSplitRequest? split;
  bool get allowsCommands => split == null && history == null;
  bool get isCommandMode => allowsCommands && query.trimLeft().startsWith('>');
  final String targetId, targetName;
  final _cache = SwarmSearchCatalog();
  final _locations = SwarmLocationCatalog();
  List<SwarmDestination> _catalog = const [];
  Set<String> _catalogIds = const {};
  Set<String> _commandIds = const {};
  List<SwarmDestination> rows = const [];
  String query = '';
  String? _selectedId;
  int cursor = 0;
  SearchOutputPreview? preview;
  String? _previewId;
  bool? _splitCurrent;
  Set<String> _presentIds = const {};
  final _checked = <String, SwarmDestination>{};
  List<SwarmDestination> get checked => List.unmodifiable(_checked.values);
  int get checkedCount => _checked.length;
  bool get multiSelect => adding && split == null && !isCommandMode;
  bool get hasSelection => multiSelect && _checked.isNotEmpty;

  int get capacity {
    final target = app.swarms
        .where((swarm) => swarm.id == targetId)
        .firstOrNull;
    return target == null ? 0 : AppNotifier.maxPanes - target.panes.length;
  }

  bool isChecked(SwarmDestination row) {
    final ids = _missingIds(row);
    return ids.isNotEmpty && ids.every(_checked.containsKey);
  }

  bool canToggle(SwarmDestination row) =>
      multiSelect &&
      !row.isCommand &&
      (isChecked(row) ||
          (canAdd(row) &&
              _checked.length +
                      _missingIds(row)
                          .where((id) => !_checked.containsKey(id))
                          .length <=
                  capacity));

  void toggle([SwarmDestination? row]) {
    row ??= selected;
    if (row == null || !canToggle(row)) return;
    final ids = _missingIds(row);
    if (isChecked(row)) {
      _checked.removeWhere((id, _) => ids.contains(id));
    } else {
      for (final entry in _catalog) {
        if (entry.agentId != null && ids.contains(entry.id)) {
          _checked[entry.id] = entry;
        }
      }
    }
    notifyListeners();
  }

  void removeChecked(String id) {
    if (_checked.remove(id) != null) notifyListeners();
  }

  void clearChecked() {
    if (_checked.isEmpty) return;
    _checked.clear();
    notifyListeners();
  }

  bool get canSubmitSelection =>
      hasSelection &&
      _checked.length <= capacity &&
      _checked.values.every((row) => canAdd(row)) &&
      _checked.keys.every(_catalogIds.contains);
  bool get canAccept => hasSelection ? canSubmitSelection : canSubmit(selected);

  bool get canPreview =>
      !navigating &&
      !isCommandMode &&
      history == null &&
      selected != null &&
      selected?.closedId == null;
  bool get previewVisible => canPreview;

  List<SwarmDestination> get previewMembers {
    final row = selected;
    if (row == null || row.agentId != null) return const [];
    final memberIds = row.isGroup
        ? row.members
        : {
            for (final swarm in app.swarms.where(
              (swarm) => swarm.id == row.swarmId,
            ))
              for (final pane in swarm.panes)
                if (pane.agentId != null)
                  agentDestinationId(pane.machineId, pane.agentId!),
          };
    return _catalog.where((entry) => memberIds.contains(entry.id)).toList();
  }

  void _updatePreview() {
    if (!previewVisible || selected?.agentId == null) {
      preview = null;
      _previewId = null;
      return;
    }
    final row = selected!;
    // Keep a snapshot while this selection stays put. Query edits and output
    // traffic do not read the buffers again. Choosing another result
    // captures fresh context, including any replacement session.
    if (_previewId == row.id) return;
    final terminal = app.allPanes
        .where(
          (pane) =>
              pane.machineId == row.machineId && pane.agentId == row.agentId,
        )
        .map((pane) => pane.session?.terminal)
        .whereType<Terminal>()
        .firstOrNull;
    _previewId = row.id;
    preview = SearchOutputPreview.capture(terminal);
  }

  SwarmDestination? get selected => rows.isEmpty ? null : rows[cursor];
  String get hint => isCommandMode
      ? 'Search commands…'
      : history != null
      ? 'Search history…'
      : adding
      ? 'Search agents to add…'
      : navigating
      ? 'Find an agent or swarm…'
      : 'Search agents, swarms, machines, projects…';

  bool get canCreate =>
      history == null &&
      app.swarms.any(
        (swarm) =>
            swarm.id == targetId && swarm.panes.length < AppNotifier.maxPanes,
      ) &&
      (split == null || app.isPaneSplitCurrent(split!));

  String get primaryAction => switch (split?.axis) {
    PaneResizeAxis.x => 'Split right',
    PaneResizeAxis.y => 'Split down',
    null => 'Add to this swarm',
  };

  String actionLabel(SwarmDestination? row) => row?.isCommand == true
      ? action(row!)
      : hasSelection
      ? 'Add $checkedCount ${checkedCount == 1 ? 'agent' : 'agents'}'
      : adding
      ? row != null &&
                row.agentId == null &&
                split == null &&
                _missingIds(row).length > 1
            ? 'Add ${_missingIds(row).length} agents'
            : primaryAction
      : row == null
      ? 'Go to'
      : action(row);

  String get unavailableMessage =>
      split != null && !app.isPaneSplitCurrent(split!)
      ? 'The layout changed. Split the agent again.'
      : hasSelection && checkedCount > capacity
      ? 'This swarm has room for $capacity more agents.'
      : hasSelection && !canSubmitSelection
      ? 'A selected agent is unavailable. Remove it or search again.'
      : selected != null && alreadyHere(selected!)
      ? 'This agent is already in this swarm.'
      : 'This swarm has no room for another agent.';

  void _refresh() {
    final next = navigating
        ? _locations.read(app, projects?.projects ?? const [])
        : history == null
        ? _cache.read(app, projects?.projects ?? const [], recent: recent)
        : [...history!.menuDestinations(app), ...closedWorkDestinations(app)];
    final splitCurrent = split == null || app.isPaneSplitCurrent(split!);
    if (identical(next, _catalog) &&
        !isCommandMode &&
        splitCurrent == _splitCurrent) {
      return;
    }
    _catalog = next;
    _catalogIds = {for (final row in next) row.id};
    _splitCurrent = splitCurrent;
    _presentIds = {
      for (final swarm in app.swarms.where((s) => s.id == targetId))
        for (final pane in swarm.panes)
          if (pane.agentId != null)
            agentDestinationId(pane.machineId, pane.agentId!),
    };
    _checked.removeWhere((id, _) => _presentIds.contains(id));
    _filter();
    notifyListeners();
  }

  void refreshCommands() {
    if (!isCommandMode) return;
    _filter();
    notifyListeners();
  }

  void _filter() {
    final availableCommands = isCommandMode
        ? commands?.call() ?? const <SwarmDestination>[]
        : const <SwarmDestination>[];
    _commandIds = {for (final command in availableCommands) command.id};
    rows = isCommandMode
        ? rankSwarmDestinations(
            availableCommands,
            query.trimLeft().substring(1).trimLeft(),
          )
        : navigating
        ? rankSwarmLocations(_catalog, query, recent: recent)
        : rankSwarmDestinations(
            adding
                ? _catalog
                      .where(
                        (row) =>
                            (split == null || row.agentId != null) &&
                            (_hasMissing(row) ||
                                (query.isNotEmpty && row.agentId != null)),
                      )
                      .toList()
                : _catalog,
            query,
            recent: recent,
          );
    // The parent stays above its children visually, but Enter after a query
    // still targets the best match, including an agent nested under that parent.
    final preferred =
        _selectedId ??
        (navigating && !isCommandMode
            ? rankSwarmDestinations(rows, query, recent: recent).firstOrNull?.id
            : null);
    final index = rows.indexWhere((row) => row.id == preferred);
    cursor = rows.isEmpty
        ? 0
        : index >= 0
        ? index
        : cursor.clamp(0, rows.length - 1);
    _selectedId = selected?.id;
    _updatePreview();
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    cursor = 0;
    _selectedId = null;
    _filter();
    notifyListeners();
  }

  void move(int delta) {
    if (rows.isEmpty) return;
    cursor = (cursor + delta) % rows.length;
    _selectedId = selected!.id;
    _updatePreview();
    notifyListeners();
  }

  SwarmSearchSelection? submit([SwarmDestination? row]) {
    if (row == null && hasSelection) {
      return canSubmitSelection ? SwarmSearchSelection.multiple(checked) : null;
    }
    final destination = row ?? selected;
    if (destination == null || !canSubmit(destination)) return null;
    if (destination.isCommand &&
        !(commands?.call().any((command) => command.id == destination.id) ??
            false)) {
      return null;
    }
    return SwarmSearchSelection(
      destination,
      adding ? SwarmSearchAction.addHere : SwarmSearchAction.open,
    );
  }

  bool canSubmit(SwarmDestination? row) =>
      row != null &&
      (!adding || row.isCommand || canAdd(row)) &&
      (!row.isCommand || (isCommandMode && _commandIds.contains(row.id))) &&
      (adding ||
          !row.isGroup ||
          canOpenSwarmGroup(app, row, destinationSwarmId: targetId)) &&
      (row.closedId == null || app.canReopenClosed(row.closedId!));

  Set<String> _missingIds(SwarmDestination row) {
    final members = row.agentId == null ? row.members : {row.id};
    return members.difference(_presentIds);
  }

  bool _hasMissing(SwarmDestination row) => row.agentId != null
      ? !_presentIds.contains(row.id)
      : row.members.any((id) => !_presentIds.contains(id));

  bool alreadyHere(SwarmDestination row) =>
      adding && row.agentId != null && _presentIds.contains(row.id);

  bool canAdd(SwarmDestination? row) =>
      !navigating &&
      history == null &&
      row != null &&
      !row.isCommand &&
      row.closedId == null &&
      _missingIds(row).isNotEmpty &&
      (split == null || row.agentId != null) &&
      (split == null || app.isPaneSplitCurrent(split!)) &&
      app.swarms.any(
        (swarm) =>
            swarm.id == targetId &&
            swarm.panes.length + _missingIds(row).length <=
                AppNotifier.maxPanes,
      );

  SwarmSearchSelection? addHere() => adding
      ? submit()
      : canAdd(selected)
      ? SwarmSearchSelection(selected!, SwarmSearchAction.addHere)
      : null;

  static String action(SwarmDestination row) => row.isCommand
      ? 'Run command'
      : row.closedId != null
      ? 'Reopen'
      : row.isGroup || row.isSwarm
      ? 'Go to swarm'
      : 'Go to agent';

  @override
  void dispose() {
    app.removeListener(_refresh);
    projects?.removeListener(_refresh);
    super.dispose();
  }
}
