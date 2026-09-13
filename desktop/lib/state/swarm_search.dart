import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'swarm_catalog.dart';
import 'swarm_navigation.dart';

/// One search session, shared by the native/Flutter input and its results.
/// Keystrokes only filter the cached catalog; they never query a machine.
class SwarmSearchController extends ChangeNotifier {
  SwarmSearchController(this.app, this.recent, {this.projects, this.history})
    : targetId = app.activeSwarmId,
      targetName = app.activeSwarm.name {
    _refresh();
    app.addListener(_refresh);
    projects?.addListener(_refresh);
  }

  final AppNotifier app;
  final List<String> recent;
  final SwarmProjectStore? projects;
  final SwarmNavigationHistory? history;
  final String targetId, targetName;
  final _cache = SwarmSearchCatalog();
  List<SwarmDestination> _catalog = const [];
  List<SwarmDestination> rows = const [];
  String query = '', _rootQuery = '';
  String? _scopeId, _selectedId;
  int cursor = 0;

  SwarmDestination? get selected => rows.isEmpty ? null : rows[cursor];
  bool get scoped => _scopeId != null;
  SwarmDestination? get scope =>
      _catalog.where((row) => row.id == _scopeId).firstOrNull;
  String get hint => history != null
      ? 'Search history…'
      : scoped
      ? 'Search agents in ${scope?.title ?? 'this group'}…'
      : 'Search agents, swarms, machines, projects…';

  void _refresh() {
    final next = history == null
        ? _cache.read(app, projects?.projects ?? const [], recent: recent)
        : [...history!.menuDestinations(app), ...closedWorkDestinations(app)];
    if (identical(next, _catalog)) return;
    _catalog = next;
    _filter();
    notifyListeners();
  }

  void _filter() {
    final group = scope;
    rows = rankSwarmDestinations(
      !scoped
          ? _catalog
          : [
              for (final row in _catalog)
                if (group?.members.contains(row.id) == true) row,
            ],
      query,
      recent: recent,
    );
    final index = rows.indexWhere((row) => row.id == _selectedId);
    cursor = rows.isEmpty
        ? 0
        : index >= 0
        ? index
        : cursor.clamp(0, rows.length - 1);
    _selectedId = selected?.id;
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
    notifyListeners();
  }

  SwarmSearchSelection? submit([SwarmDestination? row]) {
    final destination = row ?? selected;
    if (destination == null || !canSubmit(destination)) return null;
    if (!destination.isGroup) return SwarmSearchSelection(destination);
    _rootQuery = query;
    _scopeId = destination.id;
    query = '';
    cursor = 0;
    _selectedId = null;
    _filter();
    notifyListeners();
    return null;
  }

  bool canSubmit(SwarmDestination? row) =>
      row != null &&
      (row.closedId == null || app.canReopenClosed(row.closedId!));

  void back() {
    if (!scoped) return;
    _selectedId = _scopeId;
    _scopeId = null;
    query = _rootQuery;
    _filter();
    notifyListeners();
  }

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

  bool get canOpenGroup =>
      scope != null &&
      scope!.members.isNotEmpty &&
      scope!.members.length <= AppNotifier.maxPanes &&
      app.swarms.length < AppNotifier.maxSwarms;

  static String action(SwarmDestination row) => row.closedId != null
      ? 'Reopen'
      : row.isGroup
      ? 'Browse agents'
      : row.isSwarm
      ? 'Switch swarm'
      : row.hasView
      ? 'Focus pane'
      : 'Open here';

  @override
  void dispose() {
    app.removeListener(_refresh);
    projects?.removeListener(_refresh);
    super.dispose();
  }
}
