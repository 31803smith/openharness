import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
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
import '../widgets/swarm_search_input.dart';
import '../widgets/swarm_project_agents.dart';
import '../widgets/swarm_attention.dart';
import '../widgets/swarm_switcher.dart';
import '../widgets/swarm_tab_strip.dart';
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
  final _searchFocus = FocusNode(debugLabel: 'Search agents and swarms');
  SwarmSearchController? _search;
  OverlayEntry? _searchOverlay;
  FocusNode? _searchReturnFocus;
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
        // Acknowledge after the form opens so the titlebar can hand its native
        // keyboard focus to Flutter while the user edits the name.
        if (args['id'] is String) unawaited(_rename(args['id']));
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
        unawaited(_newAgent(swarmId: app.activeSwarmId));
      case 'splitRight':
        unawaited(_splitAgent(PaneResizeAxis.x));
      case 'splitDown':
        unawaited(_splitAgent(PaneResizeAxis.y));
      case 'zoomPane':
        app.toggleZoomPane();
      case 'pinPane':
        if (app.focusedPaneId != null) app.togglePinPane(app.focusedPaneId!);
      case 'addProject':
        await _addProject();
      case 'linkMachine':
        await _dialog(() => showSwarmLinkDialog(context, app));
      case 'jump':
        await _jump();
      case 'commands':
        _showSearchCommands();
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
        unawaited(_notifications());
      case 'settings':
        await _settings();
    }
    if (mounted &&
        const {
          'select',
          'close',
          'new',
          'rename',
          'jump',
          'commands',
          'notifications',
          'newAgent',
          'splitRight',
          'splitDown',
          'zoomPane',
          'pinPane',
        }.contains(call.method)) {
      // Native tab controls wait for this reply before releasing keyboard
      // ownership. The destination's actual focus tree must be ready first.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) FocusManager.instance.applyFocusChangesIfNeeded();
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
    bool chooseFolderFirst = false,
  }) => _dialog(() async {
    final focused = app.focusedPane;
    final inherit =
        machineId == null && !chooseFolderFirst && focused?.agentId != null;
    final focusedMachine = inherit
        ? app.machineStates[focused!.machineId]
        : null;
    final focusedAgent = focusedMachine?.agents
        .where((agent) => agent.id == focused?.agentId)
        .firstOrNull;
    final local = app.machineStates.values
        .where((m) => m.isLocalMachine)
        .firstOrNull;
    final id =
        machineId ??
        focusedMachine?.machine.machineId ??
        local?.machine.machineId ??
        app.machineStates.keys.firstOrNull;
    if (id == null) {
      await showSwarmLinkDialog(context, app);
      return;
    }
    final targetId = swarmId ?? app.activeSwarmId;
    final machine = app.machineStates[id];
    var selectedFolder =
        folder ??
        (focusedAgent == null
            ? null
            : focusedMachine?.projectOf(focusedAgent)?.cwd);
    Future<void>? initialEngineProbe;
    if (chooseFolderFirst && machine != null && machine.isLocalMachine) {
      // Read availability while the user chooses a folder, so the form can
      // prefer an installed agent without adding a second probe or wait.
      initialEngineProbe = app.probeEngines(id, force: true);
      try {
        selectedFolder = await getDirectoryPath(
          confirmButtonText: 'Use folder',
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open the folder picker: $error')),
          );
        }
        return;
      }
      if (!mounted ||
          selectedFolder == null ||
          app.activeSwarmId != targetId ||
          app.machineStates[id] != machine ||
          !machine.isLocalMachine ||
          machine.nodeOnline == false ||
          machine.needsLink) {
        return;
      }
    }
    await showNewAgentDialog(
      context,
      app,
      id,
      source: chooseFolderFirst ? 'first_folder' : 'swarm',
      initialFolder: selectedFolder,
      initialEngineProbe: initialEngineProbe,
      swarmId: targetId,
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
      previewInitiallyEnabled: true,
    );
    _search!.addListener(_syncSearch);
    _searchOverlay = OverlayEntry(builder: _buildSearchOverlay);
    Overlay.of(context).insert(_searchOverlay!);
    _syncSearch();
    setState(() {});
    _focusSearch();
  }

  void _focusSearch({bool selectAll = false}) {
    if (_search == null) return;
    _searchFocus.requestFocus();
    if (selectAll) {
      _searchText.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchText.text.length,
      );
    }
  }

  void _showSearchCommands() {
    _openSearch();
    _search?.setQuery('> ');
    _focusSearch();
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
    _searchOverlay?.markNeedsBuild();
  }

  void _closeSearch({bool restoreFocus = true}) {
    if (_search == null) return;
    _searchOverlay?.remove();
    _searchOverlay?.dispose();
    _searchOverlay = null;
    _search!.removeListener(_syncSearch);
    _search!.dispose();
    _search = null;
    _searchText.clear();
    _searchFocus.unfocus();
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

  Widget _buildSearchOverlay(BuildContext context) {
    final search = _search!;
    return KeymapProvider(
      keymap: _keymap,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearch,
                child: const ColoredBox(color: Color(0x66000000)),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.12),
              child: SizedBox(
                width: (constraints.maxWidth - 64).clamp(280.0, 1040.0),
                height: (constraints.maxHeight - 96).clamp(220.0, 540.0),
                child: Material(
                  key: const ValueKey('swarm-search-results'),
                  elevation: 16,
                  shadowColor: Colors.black54,
                  color: grid.AppPalette.swarmSearchSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwarmSearchInput(
                        inputKey: const ValueKey('swarm-search-input'),
                        controller: _searchText,
                        focusNode: _searchFocus,
                        search: search,
                        onChoose: _chooseSearch,
                        onClose: _closeSearch,
                        onChanged: search.setQuery,
                        showClose: true,
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      Expanded(
                        child: SwarmSearchResults(
                          search: search,
                          onChoose: _chooseSearch,
                          onRefocus: _focusSearch,
                          onCommands: _showSearchCommands,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
    'navigation.commands': _showSearchCommands,
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
            autofocus: app.panes.isNotEmpty,
            child: Scaffold(
              backgroundColor: grid.AppPalette.swarmField,
              body: Column(
                children: [
                  if (!_native)
                    SwarmTabStrip(
                      notifier: app,
                      attention: _attention,
                      onRename: _rename,
                      onSearch: _jump,
                      onNewAgent: _newAgent,
                      onNotifications: _notifications,
                    ),
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
                                  onSplit: (paneId, axis) {
                                    app.focusPane(paneId);
                                    unawaited(_splitAgent(axis));
                                  },
                                  empty: SwarmWelcome(
                                    key: ValueKey(app.activeSwarmId),
                                    notifier: app,
                                    projects: _projects.projects,
                                    onNewAgent: _newAgent,
                                    onChooseFirstFolder: () =>
                                        _newAgent(chooseFolderFirst: true),
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
}
