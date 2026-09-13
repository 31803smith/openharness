import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/desktop_window.dart';
import '../core/harness_file_store.dart';
import '../core/test_run.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shortcuts/app_shortcuts.dart';
import '../shortcuts/app_keymap.dart';
import '../shortcuts/keymap.dart';
import '../shortcuts/keymap_commands.dart';
import '../shortcuts/keymap_host.dart';
import '../shortcuts/keymap_native.dart';
import '../shortcuts/keymap_settings.dart';
import '../state/app_state.dart';
import '../state/pane_arrangement.dart';
import '../terminal/terminal_viewport.dart';
import '../usage/models_menu_controller.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_attention.dart';
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import '../widgets/layout_palette.dart';
import '../widgets/engine_identity.dart';
import '../widgets/link_machine_screen.dart';
import '../widgets/new_agent_dialog.dart';
import '../widgets/pane_grid.dart';
import '../widgets/shortcuts_sheet.dart';
import '../widgets/swarm_dialogs.dart';
import '../widgets/swarm_inline_search.dart';
import '../widgets/swarm_project_agents.dart';
import '../widgets/swarm_attention.dart';
import '../widgets/swarm_switcher.dart';
import '../widgets/swarm_wallpaper.dart';
import '../widgets/swarm_welcome.dart';
import '../widgets/task_palette.dart';

class SwarmScreen extends StatefulWidget {
  const SwarmScreen({
    super.key,
    required this.notifier,
    this.nativeTabs,
    this.projectStore,
    this.modelsMenu,
  });
  final AppNotifier notifier;
  final bool? nativeTabs;
  final SwarmProjectStore? projectStore;
  final ModelsMenuController? modelsMenu;
  @override
  State<SwarmScreen> createState() => _SwarmScreenState();
}

class _SwarmScreenState extends State<SwarmScreen> {
  static const _channel = MethodChannel('harness/swarm_tabs');
  late final bool _native =
      widget.nativeTabs ?? (Platform.isMacOS && !kUnderTest);
  late final SwarmProjectStore _projects =
      widget.projectStore ??
      SwarmProjectStore(storage: kUnderTest ? null : HarnessFileStore.shared);
  StreamSubscription<SpokenTaskRequest>? _spokenTasks;
  final _shellFocus = FocusNode(debugLabel: 'Swarm shell');
  final _navigation = SwarmNavigationHistory();
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Title bar search');
  final _searchAnchor = LayerLink();
  SwarmSearchController? _search;
  OverlayEntry? _searchOverlay;
  FocusNode? _searchReturnFocus;
  double _nativeSearchWidth = 600;
  String? _searchFieldState;
  bool _nativeQueryChange = false;
  bool _spokenPaletteOpen = false;
  bool _dialogOpen = false;
  bool _routeIsCurrent = true;
  String? _linkDialogMachineId;
  String? _nativeState;
  ModelsMenuController? _modelsMenu;
  String? _modelsState;
  final _defaultKeymap = AppKeymap();
  AppKeymap? _providedKeymap;
  AppKeymap get _keymap => _providedKeymap ?? _defaultKeymap;
  String? _nativeKeyContext;
  String _pendingKeys = '';
  AppNotifier get app => widget.notifier;

  @override
  void initState() {
    super.initState();
    _keymap.addListener(_keymapChanged);
    app.hasNavigationRail = false;
    app.railFocused = false;
    _recordNavigation();
    app.addListener(_recordNavigation);
    FocusManager.instance.addListener(_restoreEmptyFocus);
    FocusManager.instance.addListener(_syncKeyContext);
    _searchFocus.addListener(_searchFocusChanged);
    grid.AppTheme.palette.addListener(_paletteChanged);
    unawaited(_projects.load());
    _spokenTasks = app.spokenTasks.listen(_openSpokenTask);
    if (_native) {
      _modelsMenu =
          widget.modelsMenu ??
          ModelsMenuController(remote: app.readRemoteUsage);
      _modelsMenu!.addListener(_syncModels);
      _channel.setMethodCallHandler(_onNative);
      app.addListener(_syncNative);
      _syncNative();
      _syncModels();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keymap = KeymapTheme.of(context);
    if (keymap != _providedKeymap) {
      _keymap.removeListener(_keymapChanged);
      _providedKeymap = keymap;
      _keymap.addListener(_keymapChanged);
    }
    _syncKeymap();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeIsCurrent == current) return;
    _routeIsCurrent = current;
    if (!current && _search != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_routeIsCurrent) _closeSearch(restoreFocus: false);
      });
    }
    if (_native) _syncNative();
  }

  @override
  void dispose() {
    _keymap.removeListener(_keymapChanged);
    _defaultKeymap.dispose();
    grid.AppTheme.palette.removeListener(_paletteChanged);
    app.removeListener(_recordNavigation);
    FocusManager.instance.removeListener(_restoreEmptyFocus);
    FocusManager.instance.removeListener(_syncKeyContext);
    _searchOverlay?.remove();
    _searchOverlay?.dispose();
    _search?.dispose();
    _searchFocus.dispose();
    _searchText.dispose();
    _shellFocus.dispose();
    unawaited(_spokenTasks?.cancel());
    if (_native) {
      _modelsMenu?.removeListener(_syncModels);
      if (widget.modelsMenu == null) _modelsMenu?.dispose();
      unawaited(
        _channel.invokeMethod<void>('modelsState', {'subscriptions': []}),
      );
      app.removeListener(_syncNative);
      _channel.setMethodCallHandler(null);
      unawaited(
        _channel.invokeMethod<void>('update', {'tabs': [], 'enabled': false}),
      );
    }
    if (widget.projectStore == null) _projects.dispose();
    super.dispose();
  }

  AppKeymap? _sentKeymap;
  int? _sentKeymapVersion;
  void _syncKeymap() {
    if (!_native ||
        (_sentKeymap == _keymap && _sentKeymapVersion == _keymap.version)) {
      return;
    }
    _sentKeymap = _keymap;
    _sentKeymapVersion = _keymap.version;
    unawaited(
      _channel.invokeMethod<void>('keymapState', nativeKeymapSnapshot(_keymap)),
    );
  }

  void _keymapChanged() {
    _syncKeymap();
    if (mounted) setState(() {});
    _search?.refreshCommands();
  }

  void _syncKeyContext() {
    if (!_native) return;
    final focus = FocusManager.instance.primaryFocus?.context;
    final kind = focus == null
        ? KeymapContext.workspace
        : KeymapRegion.of(focus)?.contextKind ?? KeymapContext.workspace;
    if (_nativeKeyContext == kind.name) return;
    _nativeKeyContext = kind.name;
    unawaited(
      _channel.invokeMethod<void>('keymapContext', {'context': kind.name}),
    );
  }

  bool get _shortcutsEnabled =>
      mounted && _routeIsCurrent && !_dialogOpen && !_spokenPaletteOpen;

  void _runShortcut(String id) {
    if (!_canExecuteCommand(id)) return;
    if (id != 'navigation.quick_open' && id != 'navigation.commands') {
      _closeSearch();
    }
    _commands[id]?.call();
  }

  void _recordNavigation() {
    _navigation.record(app);
    if (_search != null && _search!.targetId != app.activeSwarmId) {
      _closeSearch(restoreFocus: false);
    }
  }

  int get _attention =>
      app.machineStates.values.fold(0, (n, m) => n + m.blockedAgents.length);

  void _restoreEmptyFocus() {
    if (!mounted ||
        app.panes.isNotEmpty ||
        _dialogOpen ||
        _spokenPaletteOpen ||
        _search != null ||
        ModalRoute.of(context)?.isCurrent == false ||
        _shellFocus.hasFocus) {
      return;
    }
    // Hiding the final terminal releases focus after its parent has rebuilt.
    // Only reclaim the route's empty scope, never another field or dialog.
    if (FocusManager.instance.primaryFocus == _shellFocus.enclosingScope) {
      _shellFocus.requestFocus();
    }
  }

  // Any retained session has a mounted terminal, including read-only/offline
  // output. Never-attached setup guides have no buffer to search.
  bool get _canFindTerminal => app.focusedPane?.session != null;

  void _paletteChanged() {
    _searchOverlay?.markNeedsBuild();
    if (_native) _syncNative();
  }

  void _syncNative() {
    final payload = {
      'enabled': _routeIsCurrent && !_dialogOpen && !_spokenPaletteOpen,
      'activeId': app.activeSwarmId,
      'palette': grid.AppTheme.palette.value.nativeColors,
      'canReopen': app.canReopenLastClosed,
      'canFind': _canFindTerminal,
      'canClosePane': app.focusedPane != null,
      'canGoBack': _navigation.canGoBack(app),
      'canGoForward': _navigation.canGoForward(app),
      'closedHistory': [
        for (final entry in closedWorkDestinations(app))
          {
            'id': entry.id,
            'title': entry.title,
            'machineName': entry.machineLabel,
            'detail': entry.detail,
            'swarm': entry.isSwarm,
            'engine': entry.engine,
            'iconAsset': engineIdentity(entry.engine).asset,
            'canReopen': app.canReopenClosed(entry.id),
          },
      ],
      'attention': _attention,
      'history': [
        for (final entry in _navigation.menuDestinations(app))
          {
            'id': entry.id,
            'title': entry.title,
            'machineName': entry.machineLabel,
            'detail': entry.detail,
            'swarm': entry.isSwarm,
            'engine': entry.engine,
            'iconAsset': engineIdentity(entry.engine).asset,
            'current': entry.current,
          },
      ],
      'tabs': [
        for (final swarm in app.swarms)
          {
            'id': swarm.id,
            'name': swarm.name,
            'attention': swarm.panes
                .where(
                  (p) =>
                      p.agentId != null &&
                      app.questionFor(p.machineId, p.agentId!) != null,
                )
                .length,
          },
      ],
    };
    final encoded = jsonEncode(payload);
    if (encoded == _nativeState) return;
    _nativeState = encoded;
    unawaited(_channel.invokeMethod<void>('update', payload));
  }

  void _syncModels() {
    final payload = {'subscriptions': _modelsMenu?.rows ?? []};
    final encoded = jsonEncode(payload);
    if (encoded == _modelsState) return;
    _modelsState = encoded;
    unawaited(_channel.invokeMethod<void>('modelsState', payload));
  }

  Future<void> _onNative(MethodCall call) async {
    if (mounted && call.method == 'keymapPending') {
      final keys = (call.arguments as Map?)?['keys'];
      if (keys is List &&
          keys.length <= 4 &&
          keys.every((key) => key is String)) {
        final pending = keys
            .map((key) => describeKeyStroke(KeyStroke.parse(key)))
            .join(' ');
        if (_pendingKeys != pending) setState(() => _pendingKeys = pending);
      }
      return;
    }
    if (!mounted ||
        _dialogOpen ||
        _spokenPaletteOpen ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final args = call.arguments is Map ? call.arguments as Map : const {};
    if (call.method == 'modelsOpened') {
      await _modelsMenu?.refresh();
      return;
    }
    if (call.method == 'searchBegin') {
      _openSearch();
      _updateSearchGeometry(args);
      return;
    }
    if (call.method == 'searchGeometry') {
      _updateSearchGeometry(args);
      return;
    }
    if (call.method == 'searchChanged') {
      // The field editor is authoritative while typing. Echoing an earlier
      // query back over the channel could replace a newer edit or marked text.
      _nativeQueryChange = true;
      try {
        if (args['query'] is String) _search?.setQuery(args['query']);
      } finally {
        _nativeQueryChange = false;
      }
      return;
    }
    if (call.method == 'keymapCommand' &&
        !(args['command'] as String? ?? '').startsWith('picker.')) {
      if (args['command'] is String) _runShortcut(args['command']);
      return;
    }
    if (call.method == 'searchCommand' || call.method == 'keymapCommand') {
      final search = _search;
      if (search == null) return;
      final command =
          const {
            'picker.next': 'next',
            'picker.previous': 'previous',
            'picker.preview': 'preview',
            'picker.accept': 'submit',
            'picker.add_here': 'add',
            'picker.cancel': 'close',
          }[args['command']] ??
          args['command'];
      switch (command) {
        case 'next':
          search.move(1);
        case 'previous':
          search.move(-1);
        case 'preview':
          search.togglePreview();
        case 'submit':
          final choice = search.submit();
          if (choice != null) await _chooseSearch(choice);
        case 'add':
          final choice = search.addHere();
          if (choice != null) await _chooseSearch(choice);
        case 'close':
          _closeSearch();
      }
      return;
    }
    if (call.method != 'jump') _closeSearch(restoreFocus: false);
    switch (call.method) {
      case 'new':
        app.newSwarm();
      case 'reopen':
        app.reopenClosed();
      case 'reopenHistory':
        if (args['id'] is String) app.reopenClosed(historyId: args['id']);
      case 'historyBack':
        _stepHistory(-1);
      case 'historyForward':
        _stepHistory(1);
      case 'showHistory':
        await _jump(historyOnly: true);
      case 'select':
        if (args['id'] is String) app.selectSwarm(args['id']);
      case 'close':
        if (args['id'] is String) await app.closeSwarm(args['id']);
      case 'closeActive':
        await app.closeSwarm(app.activeSwarmId);
      case 'rename':
        if (args['id'] is String) await _rename(args['id']);
      case 'renameActive':
        await _rename(app.activeSwarmId);
      case 'next':
        app.stepSwarm(1);
      case 'previous':
        app.stepSwarm(-1);
      case 'reorder':
        if (args['id'] is String && args['index'] is int) {
          app.reorderSwarm(args['id'], args['index']);
        }
      case 'addAgent':
        await _addAgent();
      case 'newAgent':
        await _newAgent(swarmId: app.activeSwarmId);
      case 'addProject':
        await _addProject();
      case 'linkMachine':
        await _dialog(() => showSwarmLinkDialog(context, app));
      case 'jump':
        await _jump();
      case 'historyDestination':
        final entry = _navigation
            .menuDestinations(app)
            .where((entry) => entry.id == args['id'])
            .firstOrNull;
        if (entry != null) {
          _preparePaneFocus();
          await activateSwarmDestination(
            app,
            entry,
            destinationSwarmId: app.activeSwarmId,
          );
        }
      case 'closePane':
        if (app.focusedPaneId != null) await app.closePane(app.focusedPaneId!);
      case 'findTerminal':
        app.focusedPane?.session?.find(TerminalFindAction.open);
      case 'findNext':
        app.focusedPane?.session?.find(TerminalFindAction.next);
      case 'findPrevious':
        app.focusedPane?.session?.find(TerminalFindAction.previous);
      case 'notifications':
        await _notifications();
      case 'settings':
        await _settings();
    }
  }

  Future<void> _dialog(Future<void> Function() action) async {
    if (_dialogOpen || _spokenPaletteOpen || !mounted) return;
    _closeSearch();
    _dialogOpen = true;
    if (_native) _syncNative();
    try {
      await action();
    } finally {
      _dialogOpen = false;
      if (_native && mounted) _syncNative();
    }
  }

  Future<void> _rename(String id) => _dialog(() async {
    final swarm = app.swarms.where((s) => s.id == id).firstOrNull;
    if (swarm == null) return;
    final name = await showSwarmRenameDialog(context, swarm.name);
    if (name != null) app.renameSwarm(id, name);
  });
  Future<void> _settings() =>
      _dialog(() => showSettingsScreen(context, app, source: 'swarm'));
  Future<void> _newAgent({
    String? machineId,
    String? folder,
    String? swarmId,
    PaneSplitRequest? split,
  }) => _dialog(() async {
    final local = app.machineStates.values
        .where((m) => m.isLocalMachine)
        .firstOrNull;
    final id =
        machineId ??
        local?.machine.machineId ??
        app.machineStates.keys.firstOrNull;
    if (id == null) {
      await showSwarmLinkDialog(context, app);
      return;
    }
    await showNewAgentDialog(
      context,
      app,
      id,
      source: 'swarm',
      initialFolder: folder,
      swarmId: swarmId,
      split: split,
    );
  });

  Future<void> _splitAgent(PaneResizeAxis axis) async {
    final split = app.preparePaneSplit(axis);
    final pane = app.focusedPane;
    if (split == null || pane == null) return;
    final machine = app.machineStates[pane.machineId];
    final agent = machine?.agents
        .where((a) => a.id == pane.agentId)
        .firstOrNull;
    await _newAgent(
      machineId: pane.machineId,
      folder: agent == null ? null : machine?.projectOf(agent)?.cwd,
      swarmId: split.swarmId,
      split: split,
    );
  }

  Future<void> _jump({bool historyOnly = false}) async {
    if (!historyOnly) {
      _openSearch();
      _focusSearch(selectAll: true);
      return;
    }
    final target = app.activeSwarmId;
    SwarmSearchSelection? selected;
    await _dialog(() async {
      selected = await showSwarmHistory(context, app, _navigation);
    });
    if (!mounted || selected == null) return;
    await _activateSearch(selected!, target);
  }

  Future<void> _activateSearch(
    SwarmSearchSelection selected,
    String target,
  ) async {
    final command = selected.destination.commandId;
    if (command != null) {
      // The result list is gone before a dialog or focus-changing command runs.
      // Recheck availability: a machine or pane may have changed while typing.
      FocusManager.instance.applyFocusChangesIfNeeded();
      if (_canExecuteCommand(command)) _commands[command]?.call();
      return;
    }
    _preparePaneFocus();
    final opened = await activateSwarmSearchSelection(
      app,
      selected,
      destinationSwarmId: target,
      projects: _projects.projects,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That result is no longer available. Search again.'),
        ),
      );
    }
  }

  void _searchFocusChanged() {
    if (_searchFocus.hasFocus && _search == null) _openSearch();
  }

  void _openSearch() {
    if (_search != null ||
        !mounted ||
        _dialogOpen ||
        _spokenPaletteOpen ||
        !_routeIsCurrent) {
      return;
    }
    _searchReturnFocus ??= FocusManager.instance.primaryFocus == _searchFocus
        ? null
        : FocusManager.instance.primaryFocus;
    if (_native) _preparePaneFocus();
    _search = SwarmSearchController(
      app,
      _navigation.recent,
      projects: _projects,
      commands: _searchCommands,
    );
    _search!.addListener(_syncSearch);
    _searchOverlay = OverlayEntry(builder: _buildSearchOverlay);
    Overlay.of(context).insert(_searchOverlay!);
    _nativeQueryChange = _native;
    _syncSearch();
    _nativeQueryChange = false;
    setState(() {});
    // Flutter releases its text client before AppKit takes the caret. This
    // prevents a terminal's old client from reclaiming the field editor.
    if (_native) _focusSearch();
  }

  void _focusSearch({bool selectAll = false}) {
    if (_search == null) return;
    if (_native) {
      unawaited(
        _channel.invokeMethod<void>('focusSearch', {'selectAll': selectAll}),
      );
    } else {
      _searchFocus.requestFocus();
      if (selectAll) {
        _searchText.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchText.text.length,
        );
      }
    }
  }

  void _syncSearch() {
    final search = _search;
    if (search == null) return;
    if (_searchText.text != search.query) {
      _searchText.value = TextEditingValue(
        text: search.query,
        selection: TextSelection.collapsed(offset: search.query.length),
      );
    }
    final state = {'query': search.query, 'hint': search.hint};
    final encoded = jsonEncode(state);
    if (_searchFieldState != encoded) {
      _searchFieldState = encoded;
      if (_native) {
        unawaited(
          _channel.invokeMethod<void>('searchState', {
            if (!_nativeQueryChange) 'query': search.query,
            'hint': search.hint,
          }),
        );
      }
    }
    _searchOverlay?.markNeedsBuild();
  }

  void _updateSearchGeometry(Map args) {
    if (args['width'] is num) {
      _nativeSearchWidth = (args['width'] as num).toDouble();
      _searchOverlay?.markNeedsBuild();
    }
  }

  void _closeSearch({bool restoreFocus = true}) {
    if (_search == null) return;
    _searchOverlay?.remove();
    _searchOverlay?.dispose();
    _searchOverlay = null;
    _search!.removeListener(_syncSearch);
    _search!.dispose();
    _search = null;
    _searchFieldState = null;
    _searchText.clear();
    _searchFocus.unfocus();
    if (_native) unawaited(_channel.invokeMethod<void>('closeSearch'));
    final previous = _searchReturnFocus;
    _searchReturnFocus = null;
    if (restoreFocus) {
      if (previous?.context != null && previous!.canRequestFocus) {
        previous.requestFocus();
      } else {
        _shellFocus.requestFocus();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _chooseSearch(SwarmSearchSelection choice) async {
    final target = _search?.targetId;
    if (target == null) return;
    _closeSearch(restoreFocus: choice.destination.isCommand);
    await _activateSearch(choice, target);
  }

  double _searchWidth(double available) =>
      _search == null ? 192 : (available - 200).clamp(140, 600).toDouble();

  Widget _buildSearchOverlay(BuildContext context) {
    final search = _search!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            (_native ? _nativeSearchWidth : _searchWidth(constraints.maxWidth))
                .clamp(128.0, constraints.maxWidth - 16);
        final scale = MediaQuery.textScalerOf(context);
        final height = swarmSearchResultsHeight(
          search,
          scale,
        ).clamp(140.0, constraints.maxHeight - (_native ? 12 : 56));
        final results = SizedBox(
          width: width,
          height: height.toDouble(),
          child: Material(
            key: const ValueKey('swarm-search-results'),
            elevation: 8,
            shadowColor: Colors.black54,
            color: grid.AppPalette.swarmSearchSurface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: SwarmSearchResults(
                search: search,
                onChoose: _chooseSearch,
                onRefocus: _focusSearch,
              ),
            ),
          ),
        );
        return Stack(
          children: [
            Positioned(
              top: _native ? 0 : 44,
              left: 0,
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearch,
              ),
            ),
            if (_native)
              Positioned(top: 0, right: 8, child: results)
            else
              Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: _searchAnchor,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomRight,
                  followerAnchor: Alignment.topRight,
                  offset: Offset.zero,
                  child: results,
                ),
              ),
          ],
        );
      },
    );
  }

  void _stepHistory(int direction) {
    if (direction < 0
        ? !_navigation.canGoBack(app)
        : !_navigation.canGoForward(app)) {
      return;
    }
    _preparePaneFocus();
    _navigation.step(app, direction);
  }

  void _preparePaneFocus() {
    // The closing picker otherwise restores its previous terminal, whose focus
    // callback can overwrite the chosen destination during this same frame.
    _shellFocus.requestFocus();
    FocusManager.instance.applyFocusChangesIfNeeded();
  }

  Future<void> _addAgent() async {
    await _jump();
  }

  Future<void> _addProject() => _dialog(() async {
    final project = await showSwarmProjectDialog(context, app);
    if (project != null) await _projects.add(project);
  });
  Future<void> _machine(MachineState machine) async {
    if (machine.needsLink) {
      await _dialog(
        () => showLinkMachineScreenDialog(
          context,
          app,
          machine.machine.machineId,
        ),
      );
      return;
    }
    if (machine.agents.isEmpty) {
      if (machine.nodeOnline == false) {
        await _dialog(() => showSwarmLinkDialog(context, app));
      } else {
        await _newAgent(machineId: machine.machine.machineId);
      }
      return;
    }
    await app.seedSwarm(machine.machine.displayName, [
      for (final a in machine.agents)
        (machineId: machine.machine.machineId, agentId: a.id),
    ]);
  }

  Future<void> _project(SwarmProjectGroup group) async {
    if (group.agents.isEmpty) {
      final saved = group.saved;
      await _newAgent(machineId: saved?.machineId, folder: saved?.path);
    } else {
      await app.seedSwarm(group.name, [
        for (final a in group.agents)
          (machineId: a.machineId, agentId: a.agent.id),
      ]);
    }
  }

  Future<void> _projectAgents(SwarmProjectGroup group) => _dialog(() async {
    final project = await showSwarmProjectAgents(context, app, group);
    if (project != null) await _projects.add(project);
  });

  Future<void> _notifications() async {
    final target = app.activeSwarmId;
    SwarmAttentionEntry? selected;
    await _dialog(() async {
      selected = await showSwarmAttention(context, app, _navigation);
    });
    if (!mounted || selected == null) return;
    _preparePaneFocus();
    await activateSwarmAttention(app, selected!, destinationSwarmId: target);
  }

  Future<void> _openSpokenTask(SpokenTaskRequest request) async {
    final spoken = SpokenTask(
      voiceId: request.voiceId,
      text: request.text,
      cmd: request.cmd,
      report: (voiceId, state, agentId) =>
          app.reportVoiceRoute(request.machineId, voiceId, state, agentId),
    );
    if (_spokenPaletteOpen || _dialogOpen || !mounted) {
      spoken.cancelled();
      return;
    }
    _closeSearch();
    _spokenPaletteOpen = true;
    if (_native) _syncNative();
    try {
      await revealWindow();
      if (!mounted) {
        spoken.cancelled();
        return;
      }
      await showTaskPalette(context, app, spoken: spoken);
    } finally {
      _spokenPaletteOpen = false;
      if (_native && mounted) _syncNative();
      spoken.cancelled();
    }
  }

  void _maybeLink() {
    final machine = app.stateOf(app.selectedMachineId ?? '');
    if (machine == null ||
        !machine.needsLink ||
        machine.isLocalMachine ||
        _dialogOpen ||
        _search != null ||
        app.isLinkPromptDismissed(machine.machine.machineId) ||
        _linkDialogMachineId != null) {
      return;
    }
    _linkDialogMachineId = machine.machine.machineId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await _dialog(
          () => showLinkMachineScreenDialog(
            context,
            app,
            machine.machine.machineId,
          ),
        );
      }
      _linkDialogMachineId = null;
    });
  }

  // Keyboard actions and search commands execute the same callbacks.
  late final Map<ShortcutAction, VoidCallback> _actionHandlers = {
    ShortcutAction.newSwarm: app.newSwarm,
    ShortcutAction.reopenClosedSwarm: app.reopenClosed,
    ShortcutAction.closeSwarm: () => app.closeSwarm(app.activeSwarmId),
    ShortcutAction.renameSwarm: () => _rename(app.activeSwarmId),
    ShortcutAction.nextSwarm: () => app.stepSwarm(1),
    ShortcutAction.previousSwarm: () => app.stepSwarm(-1),
    ShortcutAction.showSettings: _settings,
    ShortcutAction.focusPaneLeft: () => app.focusPaneHorizontally(-1),
    ShortcutAction.focusPaneRight: () => app.focusPaneHorizontally(1),
    ShortcutAction.focusPaneAbove: () => app.focusPaneVertically(-1),
    ShortcutAction.focusPaneBelow: () => app.focusPaneVertically(1),
    ShortcutAction.movePaneLeft: () => app.movePaneDirection(dx: -1, dy: 0),
    ShortcutAction.movePaneRight: () => app.movePaneDirection(dx: 1, dy: 0),
    ShortcutAction.movePaneUp: () => app.movePaneDirection(dx: 0, dy: -1),
    ShortcutAction.movePaneDown: () => app.movePaneDirection(dx: 0, dy: 1),
    ShortcutAction.nextAgent: () => _stepHistory(1),
    ShortcutAction.previousAgent: () => _stepHistory(-1),
    ShortcutAction.showHistory: () => _jump(historyOnly: true),
    ShortcutAction.findTerminal: () =>
        app.focusedPane?.session?.find(TerminalFindAction.open),
    ShortcutAction.findNext: () =>
        app.focusedPane?.session?.find(TerminalFindAction.next),
    ShortcutAction.findPrevious: () =>
        app.focusedPane?.session?.find(TerminalFindAction.previous),
    ShortcutAction.lastPane: app.focusLastPane,
    ShortcutAction.zoomPane: app.toggleZoomPane,
    ShortcutAction.switchAgent: _jump,
    ShortcutAction.showAttention: _notifications,
    ShortcutAction.addAgent: _addAgent,
    ShortcutAction.closePane: () {
      if (app.focusedPaneId != null) {
        app.closePane(app.focusedPaneId!);
      }
    },
    ShortcutAction.newAgent: _newAgent,
    ShortcutAction.routeTask: () =>
        _dialog(() => showTaskPalette(context, app)),
    ShortcutAction.reload: app.retryMachines,
    ShortcutAction.showLayout: () =>
        _dialog(() => showLayoutPalette(context, app)),
    ShortcutAction.pinPane: () {
      if (app.focusedPaneId != null) {
        app.togglePinPane(app.focusedPaneId!);
      }
    },
    ShortcutAction.showShortcuts: () =>
        _dialog(() => showShortcutsSheet(context)),
    ShortcutAction.showDebug: () => _dialog(
      () => showSettingsScreen(
        context,
        app,
        source: 'shortcut',
        initialSection: SettingsSection.debug,
      ),
    ),
  };

  late final Map<String, VoidCallback> _commands = {
    for (final command in harnessCommands)
      if (command.action != null && _actionHandlers.containsKey(command.action))
        command.id: _actionHandlers[command.action]!,
    for (var i = 1; i <= kAgentDigitCount; i++)
      'pane.focus_$i': () => app.focusPaneByIndex(i - 1),
    'navigation.commands': () {
      _openSearch();
      _search?.setQuery('> ');
      _focusSearch();
    },
    'machine.link': () => _dialog(() => showSwarmLinkDialog(context, app)),
    'project.add': _addProject,
    'keyboard.open_config': () => openKeyboardConfig(context),
    'pane.resize': app.beginPaneResize,
    'pane.reset_sizes': app.resetPaneSizes,
    'pane.split_right': () => _splitAgent(PaneResizeAxis.x),
    'pane.split_down': () => _splitAgent(PaneResizeAxis.y),
  };

  bool _canExecuteCommand(String id) {
    if (!_commands.containsKey(id) ||
        !_routeIsCurrent ||
        _dialogOpen ||
        _spokenPaletteOpen) {
      return false;
    }
    if (id == 'keyboard.open_config') return _keymap.store != null;
    if (id == 'pane.layout' || id == 'task.route') return true;
    if (id == 'swarm.new') return app.swarms.length < AppNotifier.maxSwarms;
    if (id == 'swarm.reopen') return app.canReopenLastClosed;
    if (id == 'swarm.next' || id == 'swarm.previous') {
      return app.swarms.length > 1;
    }
    if (id == 'navigation.back') return _navigation.canGoBack(app);
    if (id == 'navigation.forward') return _navigation.canGoForward(app);
    if (id.startsWith('terminal.')) return _canFindTerminal;
    if (id == 'pane.resize') {
      return app.panes.length > 1 && app.zoomedPaneId == null;
    }
    if (id == 'pane.split_right') {
      return app.preparePaneSplit(PaneResizeAxis.x) != null;
    }
    if (id == 'pane.split_down') {
      return app.preparePaneSplit(PaneResizeAxis.y) != null;
    }
    if (id == 'pane.reset_sizes') {
      return app.activeSwarm.paneSizes.keys.any(
        (key) => key.startsWith('${app.panes.length}:'),
      );
    }
    if (id.startsWith('pane.') || id == 'task.route') {
      return app.focusedPane != null;
    }
    return true;
  }

  List<SwarmDestination> _searchCommands() => [
    for (final command in harnessCommands)
      if (command.id != 'navigation.quick_open' &&
          command.id != 'navigation.commands' &&
          !RegExp(r'^pane\.focus_[1-9]$').hasMatch(command.id) &&
          _canExecuteCommand(command.id))
        SwarmDestination(
          id: 'command:${command.id}',
          title: command.label,
          detail: command.group.label,
          swarmId: null,
          current: false,
          commandId: command.id,
          shortcut: _keymap.hint(command.id),
          searchFields: [command.id],
        ),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([app, _projects]),
    builder: (context, _) {
      grid.AppTheme.watch(context);
      _maybeLink();
      if (app.panes.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _restoreEmptyFocus(),
        );
      }
      return KeymapProvider(
        keymap: _keymap,
        child: KeymapHost(
          keymap: _keymap,
          enabled: () => _shortcutsEnabled,
          canExecute: _canExecuteCommand,
          actions: {
            for (final id in _commands.keys) id: () => _runShortcut(id),
          },
          onPending: (keys) => setState(() => _pendingKeys = keys),
          child: Focus(
            focusNode: _shellFocus,
            autofocus: true,
            child: Scaffold(
              backgroundColor: grid.AppPalette.swarmField,
              body: Column(
                children: [
                  if (!_native) _tabStrip(),
                  if (_keymap.error != null)
                    Material(
                      color: grid.AppPalette.panelBg,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Keyboard config has an error. Using the last working shortcuts.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _dialog(() => showShortcutsSheet(context)),
                              child: const Text('Details'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_pendingKeys.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$_pendingKeys …  Esc to cancel',
                          style: TextStyle(
                            fontSize: 12,
                            color: grid.AppPalette.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  if (_projects.error != null || app.lastError != null)
                    Material(
                      color: grid.AppPalette.panelBg,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.orangeAccent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _projects.error ?? app.lastError!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (_projects.error == null &&
                                app.lastErrorRetryable)
                              TextButton(
                                onPressed: app.retryMachines,
                                child: const Text('Retry'),
                              ),
                            IconButton(
                              onPressed: _projects.error != null
                                  ? _projects.dismissError
                                  : app.dismissError,
                              tooltip: 'Dismiss',
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (app.panes.isEmpty)
                          const RepaintBoundary(child: SwarmWallpaper()),
                        Padding(
                          padding: app.panes.isEmpty
                              ? EdgeInsets.zero
                              : const EdgeInsets.all(10),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: PaneGrid(
                                  notifier: app,
                                  swarmMode: true,
                                  empty: SwarmWelcome(
                                    key: ValueKey(app.activeSwarmId),
                                    notifier: app,
                                    projects: _projects.projects,
                                    onNewAgent: _newAgent,
                                    onAgent: (entry) => _activateSearch(
                                      SwarmSearchSelection(
                                        SwarmDestination(
                                          id: agentDestinationId(
                                            entry.machineId,
                                            entry.agent.id,
                                          ),
                                          title: entry.agent.name,
                                          detail:
                                              entry.machine.machine.displayName,
                                          swarmId: null,
                                          current: false,
                                          machineId: entry.machineId,
                                          agentId: entry.agent.id,
                                          engine: entry.agent.engine,
                                        ),
                                      ),
                                      app.activeSwarmId,
                                    ),
                                    searchField: SwarmInlineSearch(
                                      key: ValueKey(
                                        'welcome-search:${app.activeSwarmId}',
                                      ),
                                      app: app,
                                      projects: _projects,
                                      recent: _navigation.recent,
                                      commands: _searchCommands,
                                      onChoose: _activateSearch,
                                    ),
                                    onAddProject: _addProject,
                                    onLinkMachine: () => _dialog(
                                      () => showSwarmLinkDialog(context, app),
                                    ),
                                    onMachine: _machine,
                                    onProject: _project,
                                    onProjectAgents: _projectAgents,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _tabStrip() => Container(
    height: 44,
    color: grid.AppPalette.swarmTabBar,
    child: Row(
      children: [
        const SizedBox(width: 10),
        Expanded(
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            itemCount: app.swarms.length,
            onReorderItem: (old, to) =>
                app.reorderSwarm(app.swarms[old].id, to),
            itemBuilder: (context, index) {
              final swarm = app.swarms[index];
              return ReorderableDragStartListener(
                key: ValueKey(swarm.id),
                index: index,
                child: GestureDetector(
                  onDoubleTap: () => _rename(swarm.id),
                  child: Container(
                    width: 186,
                    margin: const EdgeInsets.only(top: 6, right: 2),
                    decoration: BoxDecoration(
                      color: app.activeSwarmId == swarm.id
                          ? grid.AppPalette.swarmField
                          : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(9),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => app.selectSwarm(swarm.id),
                            style: TextButton.styleFrom(
                              animationDuration: Duration.zero,
                              foregroundColor: app.activeSwarmId == swarm.id
                                  ? Colors.white
                                  : Colors.white70,
                            ),
                            child: Text(
                              swarm.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close ${swarm.name}',
                          onPressed: () => app.closeSwarm(swarm.id),
                          icon: const Icon(Icons.close, size: 13),
                          constraints: const BoxConstraints.tightFor(
                            width: 30,
                            height: 30,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        IconButton(
          tooltip: withEffectiveShortcutHint(
            context,
            'New swarm',
            ShortcutAction.newSwarm,
          ),
          onPressed: app.swarms.length < AppNotifier.maxSwarms
              ? app.newSwarm
              : null,
          icon: const Icon(Icons.add, size: 18),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 8, top: 6),
          child: CompositedTransformTarget(
            link: _searchAnchor,
            child: SizedBox(
              width: _searchWidth(MediaQuery.sizeOf(context).width),
              height: 38,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _search == null
                      ? null
                      : grid.AppPalette.swarmSearchSurface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    height: 32,
                    child: ListenableBuilder(
                      listenable: _search ?? _searchText,
                      builder: (context, _) => SwarmSearchKeys(
                        search: _search,
                        editing: _searchText,
                        onChoose: _chooseSearch,
                        onClose: _closeSearch,
                        child: Listener(
                          onPointerDown: (_) => _openSearch(),
                          child: TextField(
                            key: const ValueKey('swarm-search-input'),
                            controller: _searchText,
                            focusNode: _searchFocus,
                            onChanged: (query) => _search?.setQuery(query),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xffebebeb),
                            ),
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: _search?.hint ?? 'Search…',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                size: 16,
                                color: Colors.white60,
                              ),
                              prefixIconConstraints:
                                  const BoxConstraints.tightFor(
                                    width: 36,
                                    height: 32,
                                  ),
                              suffixIcon:
                                  _search == null &&
                                      _keymap.hint('navigation.quick_open') !=
                                          null
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 12),
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 80,
                                        ),
                                        child: Text(
                                          _keymap.hint(
                                            'navigation.quick_open',
                                          )!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    )
                                  : null,
                              suffixIconConstraints: const BoxConstraints(
                                minWidth: 24,
                              ),
                              filled: true,
                              fillColor: grid.AppPalette.swarmSearchSurface,
                              hintStyle: const TextStyle(color: Colors.white60),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0x29ffffff),
                                ),
                              ),
                              enabledBorder: _search != null
                                  ? const OutlineInputBorder(
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(10),
                                      ),
                                      borderSide: BorderSide.none,
                                    )
                                  : OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: Color(0x29ffffff),
                                      ),
                                    ),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(10),
                                ),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: withEffectiveShortcutHint(
            context,
            'Settings',
            ShortcutAction.showSettings,
          ),
          onPressed: _settings,
          icon: const Icon(Icons.settings_outlined, size: 18),
        ),
        const SizedBox(width: 6),
      ],
    ),
  );
}
