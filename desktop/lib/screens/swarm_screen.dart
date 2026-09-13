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
import '../state/app_state.dart';
import '../terminal/terminal_viewport.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_attention.dart';
import '../state/swarm_navigation.dart';
import '../widgets/layout_palette.dart';
import '../widgets/link_machine_screen.dart';
import '../widgets/new_agent_dialog.dart';
import '../widgets/pane_grid.dart';
import '../widgets/shortcuts_sheet.dart';
import '../widgets/swarm_dialogs.dart';
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
  });
  final AppNotifier notifier;
  final bool? nativeTabs;
  final SwarmProjectStore? projectStore;
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
  bool _spokenPaletteOpen = false;
  bool _dialogOpen = false;
  bool _routeIsCurrent = true;
  String? _linkDialogMachineId;
  String? _nativeState;
  AppNotifier get app => widget.notifier;

  @override
  void initState() {
    super.initState();
    app.hasNavigationRail = false;
    app.railFocused = false;
    _recordNavigation();
    app.addListener(_recordNavigation);
    FocusManager.instance.addListener(_restoreEmptyFocus);
    unawaited(_projects.load());
    _spokenTasks = app.spokenTasks.listen(_openSpokenTask);
    if (_native) {
      _channel.setMethodCallHandler(_onNative);
      app.addListener(_syncNative);
      _syncNative();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.isCurrentOf(context) ?? true;
    if (_routeIsCurrent == current) return;
    _routeIsCurrent = current;
    if (_native) _syncNative();
  }

  @override
  void dispose() {
    app.removeListener(_recordNavigation);
    FocusManager.instance.removeListener(_restoreEmptyFocus);
    _shellFocus.dispose();
    unawaited(_spokenTasks?.cancel());
    if (_native) {
      app.removeListener(_syncNative);
      _channel.setMethodCallHandler(null);
      unawaited(
        _channel.invokeMethod<void>('update', {'tabs': [], 'enabled': false}),
      );
    }
    if (widget.projectStore == null) _projects.dispose();
    super.dispose();
  }

  void _recordNavigation() => _navigation.record(app);

  int get _attention =>
      app.machineStates.values.fold(0, (n, m) => n + m.blockedAgents.length);

  void _restoreEmptyFocus() {
    if (!mounted ||
        app.panes.isNotEmpty ||
        _dialogOpen ||
        _spokenPaletteOpen ||
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

  void _syncNative() {
    final payload = {
      'enabled': _routeIsCurrent && !_dialogOpen && !_spokenPaletteOpen,
      'activeId': app.activeSwarmId,
      'canReopen': app.canReopenClosedSwarm,
      'canFind': _canFindTerminal,
      'canClosePane': app.focusedPane != null,
      'canChangeWallpaper': app.panes.isEmpty,
      'canGoBack': _navigation.canGoBack(app),
      'canGoForward': _navigation.canGoForward(app),
      'closedHistory': [
        for (final entry in closedSwarmDestinations(app))
          {
            'id': entry.id,
            'title': entry.title,
            'detail': entry.detail,
            'swarm': true,
          },
      ],
      'attention': _attention,
      'history': [
        for (final entry in _navigation.menuDestinations(app))
          {
            'id': entry.id,
            'title': entry.isSwarm
                ? entry.title
                : '${entry.title} — ${app.stateOf(entry.machineId!)?.machine.displayName ?? entry.machineId}',
            'detail': entry.detail,
            'swarm': entry.isSwarm,
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

  Future<void> _onNative(MethodCall call) async {
    if (!mounted ||
        _dialogOpen ||
        _spokenPaletteOpen ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final args = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'new':
        app.newSwarm();
      case 'reopen':
        app.reopenClosedSwarm();
      case 'reopenHistory':
        if (args['id'] is String) app.reopenClosedSwarm(historyId: args['id']);
      case 'historyBack':
        _stepHistory(-1);
      case 'historyForward':
        _stepHistory(1);
      case 'showHistory':
        await _jump(historyOnly: true);
      case 'nextWallpaper':
        if (app.panes.isEmpty) app.nextSwarmWallpaper();
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
    );
  });
  Future<void> _jump({bool historyOnly = false}) async {
    final target = app.activeSwarmId;
    SwarmDestination? selected;
    await _dialog(() async {
      selected = await showSwarmSwitcher(
        context,
        app,
        _navigation,
        historyOnly: historyOnly,
      );
    });
    if (!mounted || selected == null) return;
    _preparePaneFocus();
    await activateSwarmDestination(app, selected!, destinationSwarmId: target);
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
    final target = app.activeSwarmId;
    bool create = false;
    SwarmAgentRef? selected;
    await _dialog(() async {
      selected = await showSwarmAgentPicker(context, app, () => create = true);
    });
    if (!mounted) return;
    if (create) {
      await _newAgent(swarmId: target);
    } else if (selected != null) {
      await app.addAgentToSwarm(
        selected!.machineId,
        selected!.agent.id,
        swarmId: target,
      );
    }
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
      return CallbackShortcuts(
        bindings: {
          ...buildShortcutBindings(
            handlers: {
              ShortcutAction.newSwarm: app.newSwarm,
              ShortcutAction.reopenClosedSwarm: app.reopenClosedSwarm,
              ShortcutAction.closeSwarm: () =>
                  app.closeSwarm(app.activeSwarmId),
              ShortcutAction.renameSwarm: () => _rename(app.activeSwarmId),
              ShortcutAction.nextSwarm: () => app.stepSwarm(1),
              ShortcutAction.previousSwarm: () => app.stepSwarm(-1),
              ShortcutAction.showSettings: _settings,
              ShortcutAction.focusPaneLeft: () => app.focusPaneHorizontally(-1),
              ShortcutAction.focusPaneRight: () => app.focusPaneHorizontally(1),
              ShortcutAction.focusPaneAbove: () => app.focusPaneVertically(-1),
              ShortcutAction.focusPaneBelow: () => app.focusPaneVertically(1),
              ShortcutAction.movePaneLeft: () =>
                  app.movePaneDirection(dx: -1, dy: 0),
              ShortcutAction.movePaneRight: () =>
                  app.movePaneDirection(dx: 1, dy: 0),
              ShortcutAction.movePaneUp: () =>
                  app.movePaneDirection(dx: 0, dy: -1),
              ShortcutAction.movePaneDown: () =>
                  app.movePaneDirection(dx: 0, dy: 1),
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
            },
            onSelectPaneIndex: app.focusPaneByIndex,
          ),
        },
        child: Focus(
          focusNode: _shellFocus,
          autofocus: true,
          child: Scaffold(
            backgroundColor: grid.AppPalette.swarmField,
            body: Column(
              children: [
                if (!_native) _tabStrip(),
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
                          if (_projects.error == null && app.lastErrorRetryable)
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
                        RepaintBoundary(
                          child: SwarmWallpaper(
                            index: app.activeSwarm.wallpaper,
                          ),
                        ),
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
                                  onAddProject: _addProject,
                                  onLinkMachine: () => _dialog(
                                    () => showSwarmLinkDialog(context, app),
                                  ),
                                  onMachine: _machine,
                                  onProject: _project,
                                  onProjectAgents: _projectAgents,
                                  onAgent: (entry) => app.addAgentToSwarm(
                                    entry.machineId,
                                    entry.agent.id,
                                  ),
                                ),
                              ),
                            ),
                            if (app.panes.isNotEmpty)
                              Positioned(
                                right: 10,
                                bottom: 10,
                                child: Material(
                                  color: grid.AppPalette.swarmTabBar,
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(8),
                                  child: IconButton(
                                    tooltip: withShortcutHint(
                                      'Add agent',
                                      ShortcutAction.addAgent,
                                    ),
                                    onPressed: _addAgent,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 34,
                                      height: 34,
                                    ),
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      Icons.add,
                                      size: 21,
                                      color: grid.AppPalette.swarmAccent,
                                    ),
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
      );
    },
  );

  Widget _tabStrip() => Container(
    height: 44,
    color: grid.AppPalette.swarmTabBar,
    child: Row(
      children: [
        const SizedBox(width: 10),
        Flexible(
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
                            child: Text(
                              swarm.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
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
          tooltip: withShortcutHint('New swarm', ShortcutAction.newSwarm),
          onPressed: app.swarms.length < AppNotifier.maxSwarms
              ? app.newSwarm
              : null,
          icon: const Icon(Icons.add, size: 18),
        ),
        const Spacer(),
        IconButton(
          tooltip: withShortcutHint(
            _attention == 0 ? 'Needs input' : '$_attention agents need input',
            ShortcutAction.showAttention,
          ),
          onPressed: _notifications,
          icon: Badge(
            isLabelVisible: _attention > 0,
            label: Text('$_attention'),
            child: const Icon(Icons.notifications_none, size: 19),
          ),
        ),
        IconButton(
          tooltip: withShortcutHint('Settings', ShortcutAction.showSettings),
          onPressed: _settings,
          icon: const Icon(Icons.settings_outlined, size: 18),
        ),
        const SizedBox(width: 6),
      ],
    ),
  );
}
