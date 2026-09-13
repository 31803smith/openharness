import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_navigation.dart';
import 'engine_identity.dart';
import 'swarm_welcome.dart';

Future<SwarmSearchSelection?> showSwarmSwitcher(
  BuildContext context,
  AppNotifier app,
  SwarmNavigationHistory history, {
  bool historyOnly = false,
  SwarmProjectStore? projects,
}) => showAppDialog<SwarmSearchSelection>(
  context: context,
  transitionDuration: Duration.zero,
  veilBlur: 0,
  veilTint: const Color(0x66000000),
  builder: (_) => _SwarmSwitcher(
    app: app,
    recent: history.recent,
    history: historyOnly ? history : null,
    projects: projects,
  ),
);

class _SwarmSwitcher extends StatefulWidget {
  const _SwarmSwitcher({
    required this.app,
    required this.recent,
    this.history,
    this.projects,
  });
  final AppNotifier app;
  final List<String> recent;
  final SwarmNavigationHistory? history;
  final SwarmProjectStore? projects;
  @override
  State<_SwarmSwitcher> createState() => _SwarmSwitcherState();
}

class _SwarmSwitcherState extends State<_SwarmSwitcher> {
  final _scroll = ScrollController();
  final _query = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Unified search query');
  final _searchCatalog = SwarmSearchCatalog();
  List<SwarmDestination> _catalog = const [];
  List<SwarmDestination> _rows = [];
  String? _scopeId, _selectedId;
  String _rootQuery = '';
  int _cursor = 0;
  double _rowHeight = 56;
  bool _revealScheduled = false;
  late final String _targetId, _targetName;
  SwarmDestination? get _selected => _rows.isEmpty ? null : _rows[_cursor];
  SwarmDestination? get _scope =>
      _catalog.where((row) => row.id == _scopeId).firstOrNull;
  bool get _composing =>
      _query.value.composing.isValid && !_query.value.composing.isCollapsed;

  @override
  void initState() {
    super.initState();
    _targetId = widget.app.activeSwarmId;
    _targetName = widget.app.activeSwarm.name;
    _refreshCatalog();
    widget.app.addListener(_onAppChanged);
    widget.projects?.addListener(_onAppChanged);
  }

  void _onAppChanged() {
    final previous = _catalog;
    _refreshCatalog();
    if (!identical(previous, _catalog)) setState(() {});
  }

  void _refreshCatalog() {
    final next = widget.history == null
        ? _searchCatalog.read(
            widget.app,
            widget.projects?.projects ?? const [],
            recent: widget.recent,
          )
        : [
            ...widget.history!.menuDestinations(widget.app),
            ...closedSwarmDestinations(widget.app),
          ];
    if (identical(next, _catalog)) return;
    _catalog = next;
    _filter();
  }

  void _filter() {
    final scope = _scope;
    final source = _scopeId == null
        ? _catalog
        : [
            for (final row in _catalog)
              if (scope?.members.contains(row.id) == true) row,
          ];
    _rows = rankSwarmDestinations(source, _query.text, recent: widget.recent);
    final index = _rows.indexWhere((row) => row.id == _selectedId);
    _cursor = _rows.isEmpty
        ? 0
        : index >= 0
        ? index
        : _cursor.clamp(0, _rows.length - 1);
    _selectedId = _selected?.id;
    _revealSelection();
  }

  void _move(int delta) {
    if (_rows.isEmpty || _composing) return;
    setState(() {
      _cursor = (_cursor + delta) % _rows.length;
      _selectedId = _rows[_cursor].id;
    });
    _scrollToSelection();
  }

  void _revealSelection() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (mounted) _scrollToSelection();
    });
  }

  void _scrollToSelection() {
    if (!_scroll.hasClients || _rows.isEmpty) return;
    final top = _cursor * _rowHeight;
    final bottom = top + _rowHeight;
    final position = _scroll.position;
    final offset = top < position.pixels
        ? top
        : bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : position.pixels;
    final target = offset.clamp(0.0, position.maxScrollExtent);
    if (target != position.pixels) _scroll.jumpTo(target);
  }

  void _submit([SwarmDestination? row]) {
    if (_composing) return;
    final selected = row ?? _selected;
    if (selected == null) return;
    if (selected.isGroup) {
      setState(() {
        _rootQuery = _query.text;
        _scopeId = selected.id;
        _query.clear();
        _cursor = 0;
        _selectedId = null;
        _filter();
      });
      _searchFocus.requestFocus();
    } else {
      Navigator.pop(context, SwarmSearchSelection(selected));
    }
  }

  bool _canAdd(SwarmDestination? row) =>
      widget.history == null &&
      row?.agentId != null &&
      row!.hasView &&
      widget.app.swarms.any(
        (swarm) =>
            swarm.id == _targetId &&
            swarm.panes.length < AppNotifier.maxPanes &&
            !swarm.panes.any(
              (pane) =>
                  pane.machineId == row.machineId &&
                  pane.agentId == row.agentId,
            ),
      );

  void _addHere() {
    if (!_composing && _canAdd(_selected)) {
      Navigator.pop(
        context,
        SwarmSearchSelection(_selected!, SwarmSearchAction.addHere),
      );
    }
  }

  void _back() {
    setState(() {
      _selectedId = _scopeId;
      _scopeId = null;
      _query.text = _rootQuery;
      _query.selection = TextSelection.collapsed(offset: _query.text.length);
      _filter();
    });
    _searchFocus.requestFocus();
  }

  String _action(SwarmDestination row) => row.closedId != null
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
    widget.app.removeListener(_onAppChanged);
    widget.projects?.removeListener(_onAppChanged);
    _scroll.dispose();
    _query.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    _rowHeight = (scale.scale(13) + scale.scale(11) + 32).clamp(
      56,
      double.infinity,
    );
    final selected = _selected;
    final scope = _scope;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _addHere,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, meta: true):
            _addHere,
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () {
          if (!_composing) Navigator.pop(context);
        },
        if (_scopeId != null)
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
      },
      child: Dialog(
        alignment: const Alignment(0, -0.5),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: SizedBox(
          width: 680,
          height: 480,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (widget.history != null) ...[
                  const Row(
                    children: [
                      Text(
                        'History',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Spacer(),
                      Text(
                        'This session',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(
                      child: SwarmSearchField(
                        controller: _query,
                        focusNode: _searchFocus,
                        autofocus: true,
                        hintText: widget.history != null
                            ? 'Search history…'
                            : _scopeId != null
                            ? 'Search agents in ${scope?.title ?? 'this group'}…'
                            : 'Search agents, swarms, machines, projects…',
                        onChanged: (_) => setState(() {
                          _cursor = 0;
                          _selectedId = null;
                          _filter();
                        }),
                        onMove: _move,
                        onSubmitted: _submit,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Close search',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
                if (_scopeId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'All results',
                          onPressed: _back,
                          icon: const Icon(Icons.arrow_back, size: 16),
                        ),
                        Expanded(
                          child: Text(
                            scope?.title ?? 'Group no longer available',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              scope == null ||
                                  scope.members.isEmpty ||
                                  scope.members.length > AppNotifier.maxPanes ||
                                  widget.app.swarms.length >=
                                      AppNotifier.maxSwarms
                              ? null
                              : () => Navigator.pop(
                                  context,
                                  SwarmSearchSelection(
                                    scope,
                                    SwarmSearchAction.openGroup,
                                  ),
                                ),
                          child: Text(
                            'Open ${scope?.members.length ?? 0} agents as swarm',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Expanded(
                  child: _rows.isEmpty
                      ? Center(
                          child: Text(
                            _scopeId != null && _query.text.isEmpty
                                ? 'No available agent views in this group'
                                : 'No matching results',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white60,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          itemCount: _rows.length,
                          itemExtent: _rowHeight,
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            return ListTile(
                              key: ValueKey(row.id),
                              selected: index == _cursor,
                              selectedColor: Colors.white,
                              selectedTileColor: Colors.white10,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              leading: row.agentId != null
                                  ? EngineMark(engine: row.engine, size: 20)
                                  : Icon(
                                      row.isMachine
                                          ? Icons.computer_outlined
                                          : row.isProject
                                          ? Icons.folder_outlined
                                          : Icons.tab,
                                      size: 19,
                                      color: Colors.white60,
                                    ),
                              title: Text(
                                row.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                row.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                              trailing: Text(
                                row.current ? 'Current' : _action(row),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white54,
                                ),
                              ),
                              onTap: () => _submit(row),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selected != null &&
                                selected.agentId != null &&
                                !selected.hasView
                            ? 'Open view in $_targetName'
                            : '↑↓ choose · Esc close',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                    if (_canAdd(selected))
                      TextButton(
                        onPressed: _addHere,
                        child: const Text(
                          'Add to this swarm  ⌘↵',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: selected == null ? null : _submit,
                      child: Text(
                        '${selected == null ? 'Open' : _action(selected)}  ↵',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
