import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../terminal/search_output_preview.dart';

import 'app_state.dart';
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
  bool get isCommandMode => history == null && query.trimLeft().startsWith('>');
  final String targetId, targetName;
  final _cache = SwarmSearchCatalog();
  List<SwarmDestination> _catalog = const [];
  Set<String> _commandIds = const {};
  List<SwarmDestination> rows = const [];
  String query = '';
  String? _selectedId;
  int cursor = 0;
  bool previewEnabled = false;
  SearchOutputPreview? preview;
  String? _previewId;

  bool get canPreview =>
      !isCommandMode && selected?.agentId != null && selected?.closedId == null;
  bool get previewVisible => previewEnabled && canPreview;

  void togglePreview() {
    if (!previewEnabled && !canPreview) return;
    previewEnabled = !previewEnabled;
    _updatePreview();
    notifyListeners();
  }

  void _updatePreview() {
    if (!previewVisible) {
      preview = null;
      _previewId = null;
      return;
    }
    final row = selected!;
    // Keep a snapshot while this selection stays put. Query edits and output
    // traffic do not read the buffers again. A new selection or re-enabling
    // preview captures fresh context, including any replacement session.
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
      : 'Search agents, swarms, machines, projects…';

  void _refresh() {
    final next = history == null
        ? _cache.read(app, projects?.projects ?? const [], recent: recent)
        : [...history!.menuDestinations(app), ...closedWorkDestinations(app)];
    if (identical(next, _catalog) && !isCommandMode) return;
    _catalog = next;
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
        : rankSwarmDestinations(_catalog, query, recent: recent);
    final index = rows.indexWhere((row) => row.id == _selectedId);
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
    final destination = row ?? selected;
    if (destination == null || !canSubmit(destination)) return null;
    if (destination.isCommand &&
        !(commands?.call().any((command) => command.id == destination.id) ??
            false)) {
      return null;
    }
    return SwarmSearchSelection(destination);
  }

  bool canSubmit(SwarmDestination? row) =>
      row != null &&
      (!row.isCommand || (isCommandMode && _commandIds.contains(row.id))) &&
      (!row.isGroup ||
          canOpenSwarmGroup(app, row, destinationSwarmId: targetId)) &&
      (row.closedId == null || app.canReopenClosed(row.closedId!));

  bool canAdd(SwarmDestination? row) =>
      history == null &&
      row?.agentId != null &&
      row!.hasView &&
      app.swarms.any(
        (swarm) =>
            swarm.id == targetId &&
            swarm.panes.length < AppNotifier.maxPanes &&
            !swarm.panes.any(
              (pane) =>
                  pane.machineId == row.machineId &&
                  pane.agentId == row.agentId,
            ),
      );

  SwarmSearchSelection? addHere() => canAdd(selected)
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
