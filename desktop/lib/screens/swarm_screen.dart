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
import '../shared/widgets/app_dialog.dart';
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
import '../state/swarm.dart';
import '../widgets/layout_palette.dart';
import '../widgets/engine_identity.dart';
import '../widgets/harness_start_page.dart';
import '../widgets/link_machine_screen.dart';
import '../widgets/machines_manager.dart';
import '../widgets/new_agent_dialog.dart';
import '../widgets/pane_grid.dart';
import '../widgets/shortcuts_sheet.dart';
import '../widgets/swarm_dialogs.dart';
import '../widgets/swarm_search_input.dart';
import '../widgets/swarm_attention.dart';
import '../widgets/swarm_switcher.dart';
import '../widgets/swarm_icon.dart';
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
  final _canvasFocus = FocusNode(
    debugLabel: 'Swarm canvas',
    canRequestFocus: false,
    skipTraversal: true,
  );
  final _navigation = SwarmNavigationHistory();
  final _searchCatalog = SwarmSearchCatalog();
  final _searchText = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Find a harness');
  SwarmSearchController? _search;
  OverlayEntry? _searchOverlay;
  (String, bool, bool)? _searchHeaderState;
  FocusNode? _searchReturnFocus;
  (String, bool)? _lastWorkspace;
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
    _canvasFocus.dispose();
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
    if (id == 'agent.new' && _search != null) {
      final target = _search!.targetId;
      final split = _search!.split;
      _closeSearch();
      unawaited(_newAgent(swarmId: target, split: split));
      return;
    }
    if (!_canExecuteCommand(id)) return;
    if (id != 'navigation.commands') {
      _closeSearch();
    }
    _commands[id]?.call();
  }

  void _recordNavigation() {
    _navigation.record(app);
    if (_search != null &&
        (_search!.targetId != app.activeSwarmId ||
            (_lastWorkspace?.$2 == true && app.panes.isNotEmpty))) {
      _closeSearch(restoreFocus: false);
    }
    final workspace = (app.activeSwarmId, app.panes.isEmpty);
    if (_lastWorkspace == workspace) return;
    _lastWorkspace = workspace;
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

  String? _tabEngine(Swarm tab) {
    if (tab.panes.length != 1) return null;
    final pane = tab.panes.single;
    return app
            .stateOf(pane.machineId)
            ?.agents
            .where((agent) => agent.id == pane.agentId)
            .firstOrNull
            ?.engine ??
        pane.session?.engineId;
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
            'agentCount': entry.isSwarm ? entry.members.length : 1,
            'engine': entry.engine,
            'iconAsset': engineIdentity(entry.engine).asset,
            'canReopen': app.canReopenClosed(entry.id),
          },
      ],
      'attention': _attention,
      'machines': [
        for (final machine in app.machineStates.values)
          {
            'id': machine.machine.machineId,
            'name': machine.machine.displayName,
            'local': machine.isLocalMachine,
            'status': machine.needsLink
                ? 'Link required'
                : machine.nodeOnline == false
                ? 'Offline'
                : machine.nodeOnline == true
                ? 'Online'
                : 'Connecting…',
          },
      ],
      'history': [
        for (final entry in _navigation.menuDestinations(app))
          {
            'id': entry.id,
            'title': entry.title,
            'machineName': entry.machineLabel,
            'detail': entry.detail,
            'swarm': entry.isSwarm,
            'agentCount': entry.isSwarm ? entry.members.length : 1,
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
            'agentCount': swarm.panes.length,
            'engine': _tabEngine(swarm),
            'iconAsset': engineIdentity(_tabEngine(swarm)).asset,
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
    final nativeCommand = switch (call.method) {
      'keymapCommand' =>
        args['command'] is String ? args['command'] as String : null,
      'commands' => 'navigation.commands',
      'newAgent' => 'agent.new',
      _ => null,
    };
    if (nativeCommand != null) {
      final focus = FocusManager.instance.primaryFocus?.context;
      final region = focus == null ? null : KeymapRegion.of(focus);
      final action = region?.actions?[nativeCommand];
      if (action != null) {
        // Match keyboard dispatch: the focused picker owns its commands and
        // closes its own results before opening creation. Bypassing it stacks
        // another search or leaves the start-page dropdown under the dialog.
        if (region?.composing?.call() == true) return;
        action();
        if (call.method != 'keymapCommand') {
          await WidgetsBinding.instance.endOfFrame;
          if (mounted) FocusManager.instance.applyFocusChangesIfNeeded();
        }
        return;
      }
    }
    if (call.method == 'keymapCommand' &&
        nativeCommand?.startsWith('picker.') != true) {
      if (nativeCommand != null) _runShortcut(nativeCommand);
      return;
    }
    if (call.method == 'searchCommand' || call.method == 'keymapCommand') {
      final search = _search;
      if (search == null) return;
      final command =
          const {
            'picker.next': 'next',
            'picker.previous': 'previous',
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
        case 'submit':
          final choice = search.submit();
          if (choice != null) await _chooseSearch(choice);
        case 'add':
          final choice = search.addHere();
          if (choice != null) await _chooseSearch(choice);
        case 'close':
          _dismissSearch();
      }
      return;
    }
    if (call.method == 'newAgent' && _search != null) {
      _runShortcut('agent.new');
      await WidgetsBinding.instance.endOfFrame;
      return;
    }
    _closeSearch(restoreFocus: false);
    switch (call.method) {
      case 'new':
        _newTab();
      case 'reopen':
        app.reopenClosed();
      case 'reopenHistory':
        if (args['id'] is String) app.reopenClosed(historyId: args['id']);
      case 'historyBack':
        _stepHistory(-1);
      case 'historyForward':
        _stepHistory(1);
      case 'showHistory':
        await _showHistory();
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
      case 'manageMachines':
        unawaited(_dialog(() => showMachinesManager(context, app)));
      case 'refreshMachines':
        unawaited(app.retryMachines());
      case 'machineDestination':
        final machine = args['id'] is String ? app.stateOf(args['id']) : null;
        if (machine != null) {
          _openSearch(adding: true, query: machine.machine.displayName);
        }
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
          'commands',
          'notifications',
          'addAgent',
          'newAgent',
          'manageMachines',
          'splitRight',
          'splitDown',
          'zoomPane',
          'pinPane',
          'machineDestination',
        }.contains(call.method)) {
      // Native tab controls wait for this reply before releasing keyboard
      // ownership. The destination's actual focus tree must be ready first.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) FocusManager.instance.applyFocusChangesIfNeeded();
    }
  }

  Future<void> _dialog(
    Future<void> Function() action, {
    bool restoreEntry = true,
  }) async {
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
    if (restoreEntry) await _ensureEmptyEntry();
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
  }) async {
    final targetId = swarmId ?? app.activeSwarmId;
    await _dialog(() async {
      final focused = app.focusedPane;
      // A general New Agent action starts on this computer. Most launches are
      // local, and silently inheriting a remote focused pane makes the uncommon
      // destination look like the default. Splitting a pane is contextual by
      // definition, so it keeps the focused agent's machine and folder.
      final inherit =
          machineId == null &&
          split != null &&
          !chooseFolderFirst &&
          focused?.agentId != null;
      final focusedMachine = inherit
          ? app.machineStates[focused!.machineId]
          : null;
      final focusedAgent = focusedMachine?.agents
          .where((agent) => agent.id == focused?.agentId)
          .firstOrNull;
      final local = app.machineStates.values
          .where(
            (m) =>
                m.isLocalMachine &&
                (!chooseFolderFirst || (!m.needsLink && m.nodeOnline != false)),
          )
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
      final machine = app.machineStates[id];
      if (chooseFolderFirst &&
          (machine == null ||
              !machine.isLocalMachine ||
              machine.needsLink ||
              machine.nodeOnline == false)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This computer is unavailable. Reconnect and try again.',
            ),
          ),
        );
        return;
      }
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
              SnackBar(
                content: Text('Could not choose a working folder: $error'),
              ),
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
    }, restoreEntry: false);
    await _ensureEmptyEntry();
  }

  Future<void> _splitAgent(PaneResizeAxis axis, {int? paneId}) async {
    final split = app.preparePaneSplit(axis, paneId: paneId);
    if (split == null) return;
    if (paneId != null) app.focusPane(split.paneId);
    _openSearch(adding: true, split: split);
  }

  Future<void> _showHistory() async {
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
    String target, {
    PaneSplitRequest? split,
  }) async {
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
      split: split,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That result is no longer available. Search again.'),
        ),
      );
    }
  }

  void _openSearch({
    bool adding = false,
    PaneSplitRequest? split,
    String query = '',
  }) {
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
    // Search is an overlay, so late pane attachment needs an explicit focus
    // boundary to keep its programmatic focus request out of the picker.
    _canvasFocus.descendantsAreFocusable = false;
    _search = SwarmSearchController(
      app,
      _navigation.recent,
      projects: _projects,
      commands: _searchCommands,
      adding: adding,
      commandsOnly: !adding,
      split: split,
      catalog: _searchCatalog,
    )..setQuery(query);
    _search!.addListener(_syncSearch);
    _searchOverlay = OverlayEntry(builder: _buildSearchOverlay);
    Overlay.of(context).insert(_searchOverlay!);
    _syncSearch();
    // The overlay and focus nodes update independently of the retained canvas.
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
    if (_search?.adding == true) _closeSearch(restoreFocus: false);
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
    // Results listen to their controller directly. Rebuilding the entire
    // overlay on every arrow also rebuilt the unchanged text editor/button.
    final header = (search.hint, search.canCreate, _canDismissSearch);
    if (_searchHeaderState != header) {
      _searchHeaderState = header;
      _searchOverlay?.markNeedsBuild();
    }
  }

  void _closeSearch({bool restoreFocus = true}) {
    if (_search == null) return;
    // Enable the chosen terminal synchronously, before activation requests its
    // focus and before the following frame rebuilds the canvas.
    _canvasFocus.descendantsAreFocusable = true;
    _searchOverlay?.remove();
    _searchOverlay?.dispose();
    _searchOverlay = null;
    _search!.removeListener(_syncSearch);
    _search!.dispose();
    _search = null;
    _searchHeaderState = null;
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
  }

  bool get _canDismissSearch => true;

  void _dismissSearch() => _closeSearch();

  Future<void> _ensureEmptyEntry() async {
    if (!mounted || app.panes.isNotEmpty) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _shortcutsEnabled && app.panes.isEmpty) {
      _restoreEmptyFocus();
    }
  }

  Future<void> _chooseSearch(SwarmSearchSelection choice) async {
    final target = _search?.targetId;
    final split = _search?.split;
    if (target == null) return;
    _closeSearch(restoreFocus: choice.destination.isCommand);
    await _activateSearch(choice, target, split: split);
    if (mounted) {
      if (app.activeSwarmId != target) app.cancelSwarmDraft(target);
      await _ensureEmptyEntry();
    }
  }

  Widget _buildSearchOverlay(BuildContext context) {
    final search = _search!;
    // Keep the command editor mounted as its query changes so every keystroke
    // retains focus and text editing ownership.
    final commandsOnly = search.commandsOnly;
    return KeymapProvider(
      keymap: _keymap,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismissSearch,
                child: const ColoredBox(color: kDialogVeilTint),
              ),
            ),
            Align(
              alignment: const Alignment(0, -0.12),
              child: SizedBox(
                width: (constraints.maxWidth - 64).clamp(280.0, 720.0),
                height: (constraints.maxHeight - 96).clamp(220.0, 540.0),
                child: Column(
                  children: [
                    Expanded(
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
                            if (commandsOnly)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Commands',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            SwarmSearchInput(
                              inputKey: const ValueKey('swarm-search-input'),
                              controller: _searchText,
                              focusNode: _searchFocus,
                              search: search,
                              onChoose: _chooseSearch,
                              onClose: _dismissSearch,
                              onChanged: search.setQuery,
                              showClose: _canDismissSearch || commandsOnly,
                              onNewAgent: () => _runShortcut('agent.new'),
                            ),
                            const Divider(height: 1, color: Colors.white12),
                            Expanded(
                              child: SwarmSearchResults(
                                search: search,
                                onChoose: _chooseSearch,
                                onRefocus: _focusSearch,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
    if (_search != null) _closeSearch(restoreFocus: false);
    _openSearch(adding: true);
  }

  void _newTab() {
    if (app.panes.isNotEmpty) app.newSwarm();
  }

  Future<void> _addProject() => _dialog(() async {
    final project = await showSwarmProjectDialog(context, app);
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
    ShortcutAction.newSwarm: _newTab,
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
    ShortcutAction.showHistory: _showHistory,
    ShortcutAction.findTerminal: () =>
        app.focusedPane?.session?.find(TerminalFindAction.open),
    ShortcutAction.findNext: () =>
        app.focusedPane?.session?.find(TerminalFindAction.next),
    ShortcutAction.findPrevious: () =>
        app.focusedPane?.session?.find(TerminalFindAction.previous),
    ShortcutAction.lastPane: app.focusLastPane,
    ShortcutAction.zoomPane: app.toggleZoomPane,
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
    for (var i = 1; i <= kTabDigitCount; i++)
      'swarm.select_$i': () => app.selectSwarmByIndex(i - 1),
    for (var i = 1; i <= 9; i++)
      'pane.focus_$i': () => app.focusPaneByIndex(i - 1),
    'navigation.commands': _showSearchCommands,
    'machine.link': () => _dialog(() => showSwarmLinkDialog(context, app)),
    'machines.manage': () => _dialog(() => showMachinesManager(context, app)),
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
    if (id.startsWith('swarm.select_')) {
      final number = int.tryParse(id.substring('swarm.select_'.length));
      return number != null && number >= 1 && number <= app.swarms.length;
    }
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
      if (command.id != 'navigation.commands' &&
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
                          ColoredBox(
                            color: grid.AppPalette.swarmField,
                            key: const ValueKey('harness-start-background'),
                          ),
                        Padding(
                          padding: app.panes.isEmpty
                              ? EdgeInsets.zero
                              : const EdgeInsets.all(10),
                          child: Focus.withExternalFocusNode(
                            focusNode: _canvasFocus,
                            includeSemantics: false,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: PaneGrid(
                                    notifier: app,
                                    swarmMode: true,
                                    onSplit: (paneId, axis) => unawaited(
                                      _splitAgent(axis, paneId: paneId),
                                    ),
                                    empty: app.panes.isEmpty
                                        ? HarnessStartPage(
                                            key: ValueKey(
                                              'harness-start:${app.activeSwarmId}',
                                            ),
                                            createSearch: () =>
                                                SwarmSearchController(
                                                  app,
                                                  _navigation.recent,
                                                  projects: _projects,
                                                  commands: _searchCommands,
                                                  adding: true,
                                                  catalog: _searchCatalog,
                                                ),
                                            onNew: _newAgent,
                                            onChoose: (selection) =>
                                                _activateSearch(
                                                  selection,
                                                  app.activeSwarmId,
                                                ),
                                          )
                                        : null,
                                  ),
                                ),
                              ],
                            ),
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
        IconButton(
          key: const ValueKey('swarm-notifications-button'),
          tooltip: withEffectiveShortcutHint(
            context,
            'Harnesses needing input',
            ShortcutAction.showAttention,
          ),
          onPressed: _notifications,
          icon: Badge(
            isLabelVisible: _attention > 0,
            child: const Icon(Icons.notifications_none, size: 20),
          ),
        ),
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
                            child: Row(
                              children: [
                                if (swarm.panes.length == 1)
                                  EngineMark(
                                    key: ValueKey('tab-engine:${swarm.id}'),
                                    engine: _tabEngine(swarm),
                                    size: 16,
                                  )
                                else if (swarm.panes.length > 1)
                                  SwarmIcon(
                                    key: ValueKey('tab-group:${swarm.id}'),
                                    size: 16,
                                    color: Colors.white70,
                                  )
                                else
                                  const Icon(Icons.add_box_outlined, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    swarm.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
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
          key: const ValueKey('swarm-new-tab-button'),
          tooltip: withEffectiveShortcutHint(
            context,
            'New Tab',
            ShortcutAction.newSwarm,
          ),
          onPressed: app.swarms.length < AppNotifier.maxSwarms ? _newTab : null,
          icon: const Icon(Icons.add, size: 18),
        ),
        _harnessButton(create: true),
        const SizedBox(width: 8),
        _harnessButton(create: false),
        const SizedBox(width: 6),
      ],
    ),
  );

  Widget _harnessButton({required bool create}) {
    final label = create ? 'New Harness' : 'Open Harness';
    return Tooltip(
      message: withEffectiveShortcutHint(
        context,
        label,
        create ? ShortcutAction.newAgent : ShortcutAction.addAgent,
      ),
      child: TextButton(
        key: ValueKey(
          create ? 'swarm-new-harness-button' : 'swarm-open-harness-button',
        ),
        onPressed: create ? _newAgent : _addAgent,
        style: TextButton.styleFrom(
          minimumSize: Size(create ? 106 : 108, 28),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          backgroundColor: create
              ? grid.AppPalette.swarmAccent
              : grid.AppPalette.swarmSearchSurface,
          foregroundColor: create
              ? grid.AppPalette.swarmTabBar
              : grid.AppPalette.swarmAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(label),
      ),
    );
  }
}
