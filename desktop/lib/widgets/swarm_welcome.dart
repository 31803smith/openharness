import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/skeleton.dart';
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';
import 'engine_identity.dart';
import 'swarm_icon.dart';
import 'welcome_workspace_preview.dart';

class SwarmWelcome extends StatefulWidget {
  const SwarmWelcome({
    super.key,
    required this.notifier,
    required this.projects,
    required this.onNewAgent,
    required this.searchField,
    required this.onAddProject,
    required this.onLinkMachine,
    required this.onMachine,
    required this.onProject,
    this.onChooseFirstFolder,
    this.onCloneRepository,
    this.onAgent,
    this.onProjectAgents,
  });

  final AppNotifier notifier;
  final List<SavedSwarmProject> projects;
  final VoidCallback onNewAgent, onAddProject, onLinkMachine;
  final VoidCallback? onChooseFirstFolder, onCloneRepository;
  final Widget searchField;
  final ValueChanged<MachineState> onMachine;
  final ValueChanged<SwarmProjectGroup> onProject;
  final ValueChanged<SwarmAgentRef>? onAgent;
  final ValueChanged<SwarmProjectGroup>? onProjectAgents;

  @override
  State<SwarmWelcome> createState() => _SwarmWelcomeState();
}

/// Every empty swarm uses this start surface. Available work, not whether the
/// user has visited another tab, determines the useful next action.
class _SwarmWelcomeState extends State<SwarmWelcome> {
  bool _reconnecting = false;

  Future<void> _reconnect() async {
    if (_reconnecting) return;
    setState(() => _reconnecting = true);
    try {
      await widget.notifier.retryMachines();
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final app = widget.notifier;
    final groups = swarmProjects(app, widget.projects);
    bool ready(MachineState machine) =>
        !machine.needsLink && machine.nodeOnline != false;
    final retained = {
      for (final pane in app.allPanes)
        if (pane.agentId != null) (pane.machineId, pane.agentId!),
    };
    final agents =
        swarmAgents(app)
            .where(
              (entry) =>
                  entry.agent.terminalAvailable ||
                  retained.contains((entry.machineId, entry.agent.id)),
            )
            .toList()
          ..sort((a, b) {
            final available =
                (ready(b.machine) ? 1 : 0) - (ready(a.machine) ? 1 : 0);
            if (available != 0) return available;
            if (a.machine.isLocalMachine != b.machine.isLocalMachine) {
              return a.machine.isLocalMachine ? -1 : 1;
            }
            return a.agent.name.toLowerCase().compareTo(
              b.agent.name.toLowerCase(),
            );
          });
    final existing =
        (agents.isNotEmpty || retained.isNotEmpty) && widget.onAgent != null;
    final local = app.machineStates.values
        .where((machine) => machine.isLocalMachine && ready(machine))
        .firstOrNull;
    final canCreate = app.machineStates.values.any(ready);
    final finding =
        _reconnecting ||
        app.machinesLoading ||
        app.machineStates.values.any(
          (machine) =>
              ready(machine) &&
              (machine.agentLoadStatus == AgentLoadStatus.idle ||
                  machine.agentLoadStatus == AgentLoadStatus.loading),
        );
    final needsLink =
        app.machineStates.isEmpty ||
        app.machineStates.values.every((machine) => machine.needsLink);
    final chooseFolder =
        !existing && local != null && widget.onChooseFirstFolder != null;
    final waiting = !canCreate && finding;

    final primary = KeyedSubtree(
      // Discovery can finish after the first autofocus attempt. Give the
      // newly enabled action its first attempt in the welcome's own scope;
      // an explicit focus elsewhere in that scope still takes precedence.
      key: ValueKey(waiting),
      child: FilledButton.icon(
        key: const ValueKey('swarm-start-primary'),
        autofocus: !existing && !waiting,
        onPressed: chooseFolder
            ? widget.onChooseFirstFolder
            : canCreate
            ? widget.onNewAgent
            : finding
            ? null
            : needsLink
            ? widget.onLinkMachine
            : _reconnect,
        icon: Icon(
          chooseFolder
              ? Icons.folder_open_outlined
              : canCreate
              ? Icons.add
              : Icons.computer_outlined,
          size: 18,
        ),
        label: Text(
          chooseFolder
              ? 'Choose folder…'
              : canCreate
              ? 'New agent'
              : finding
              ? 'Finding your computers…'
              : needsLink
              ? 'Link a machine'
              : 'Reconnect',
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size(140, 44),
          backgroundColor: grid.AppPalette.swarmAccent,
          foregroundColor: grid.AppPalette.swarmTabBar,
        ),
      ),
    );

    Widget intro() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          existing ? 'Start a swarm' : 'Start with one agent',
          style: const TextStyle(
            fontSize: 32,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -.7,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          existing ? 'Start with one agent. Add more whenever you need them.' : 'Work with Codex, Claude Code, and other agents side by side. Start in a folder you already use.',
          style: const TextStyle(
            fontSize: 14,
            height: 1.55,
            color: Colors.white70,
          ),
        ),
        if (!existing) ...[
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              primary,
              if (local != null && widget.onCloneRepository != null)
                TextButton(
                  key: const ValueKey('swarm-start-clone'),
                  onPressed: widget.onCloneRepository,
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text('Clone repository…'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            canCreate
                ? 'Choose a folder → Pick an agent → Give it a task'
                : finding
                ? 'Looking for your computers and existing agents…'
                : needsLink
                ? 'Connect a computer to start or bring in existing work.'
                : 'Your computers are offline. Reconnect to load your agents.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Colors.white60,
            ),
          ),
        ],
      ],
    );

    const example = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Work side by side · Example',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        SizedBox(height: 10),
        WelcomeWorkspacePreview(),
        SizedBox(height: 10),
        Text(
          'A swarm is a tab of agents. Use + to add another when you’re ready.',
          style: TextStyle(fontSize: 12, height: 1.5, color: Colors.white60),
        ),
      ],
    );

    return FocusScope(
      // A tab can become empty while a dialog is open. Its new autofocus
      // controls must not take keyboard input from that dialog.
      canRequestFocus: ModalRoute.isCurrentOf(context) != false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1040),
                padding: EdgeInsets.fromLTRB(
                  constraints.maxWidth < 700 ? 24 : 48,
                  36,
                  constraints.maxWidth < 700 ? 24 : 48,
                  70,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (existing) ...[
                      intro(),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, size) =>
                            size.maxWidth < 620 * textScale
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  widget.searchField,
                                  const SizedBox(height: 12),
                                  primary,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: widget.searchField),
                                  const SizedBox(width: 12),
                                  primary,
                                ],
                              ),
                      ),
                      const SizedBox(height: 18),
                      if (agents.isNotEmpty)
                        _Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
                                child: Text(
                                  'Add your first agent',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              for (final entry in agents.take(3))
                                ListTile(
                                  key: ValueKey(
                                    'welcome-agent:${entry.machineId}:${entry.agent.id}',
                                  ),
                                  leading: EngineMark(
                                    engine: entry.agent.engine,
                                    size: 22,
                                  ),
                                  title: Text(
                                    entry.agent.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: Text(
                                    [
                                      entry.machine.machine.displayName,
                                      entry.project?.name,
                                      if (!ready(entry.machine))
                                        entry.machine.needsLink
                                            ? 'Link required'
                                            : 'Offline',
                                    ].whereType<String>().join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60,
                                    ),
                                  ),
                                  trailing: const Icon(
                                    Icons.add,
                                    size: 17,
                                    color: Colors.white60,
                                  ),
                                  onTap: () => widget.onAgent!(entry),
                                ),
                            ],
                          ),
                        ),
                    ] else
                      LayoutBuilder(
                        builder: (context, size) =>
                            size.maxWidth >= 720 * textScale
                            ? Row(
                                children: [
                                  Expanded(flex: 6, child: intro()),
                                  const SizedBox(width: 40),
                                  const Expanded(flex: 5, child: example),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  intro(),
                                  const SizedBox(height: 24),
                                  example,
                                ],
                              ),
                      ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Or start with a machine or project',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ),
                    _catalog(app, groups),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _project(SwarmProjectGroup group) => _StarterRow(
    name: group.name,
    count: group.agents.length,
    onTap: () => widget.onProject(group),
    onManage: widget.onProjectAgents == null
        ? null
        : () => widget.onProjectAgents!(group),
  );

  Widget _catalog(AppNotifier app, List<SwarmProjectGroup> groups) => _Surface(
    child: LayoutBuilder(
      builder: (context, size) {
        final machines = _section(
          'Machines',
          'Link machine',
          widget.onLinkMachine,
          [
            if (app.machinesLoading && app.machineStates.isEmpty)
              const SkeletonList(rows: 3),
            for (final machine in app.machineStates.values)
              _StarterRow(
                name: machine.machine.displayName,
                note: machine.needsLink
                    ? 'Link required'
                    : machine.nodeOnline == false
                    ? 'Offline'
                    : machine.isLocalMachine
                    ? 'This computer'
                    : null,
                count: machine.agents.length,
                onTap: () => widget.onMachine(machine),
              ),
            if (!app.machinesLoading && app.machineStates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Link a computer to find its agents.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
          ],
        );
        final projects = _section(
          'Projects',
          'Add project',
          widget.onAddProject,
          [
            for (final group in groups) _project(group),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Save a working folder for quick access.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
          ],
        );
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        return size.maxWidth < 570 * textScale
            ? Column(children: [machines, const SizedBox(height: 24), projects])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: machines),
                  const SizedBox(width: 28),
                  Expanded(child: projects),
                ],
              );
      },
    ),
  );

  Widget _section(
    String title,
    String action,
    VoidCallback onAction,
    List<Widget> children,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: Text(action, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
      ...children,
    ],
  );
}

class SwarmSearchField extends StatefulWidget {
  const SwarmSearchField({
    super.key,
    required this.onChanged,
    this.onSubmitted,
    this.onMove,
    this.autofocus = false,
    this.hintText = 'Find an agent…',
    this.controller,
    this.focusNode,
  });
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;
  final ValueChanged<int>? onMove;
  final bool autofocus;
  final String hintText;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  @override
  State<SwarmSearchField> createState() => _SwarmSearchFieldState();
}

class _SwarmSearchFieldState extends State<SwarmSearchField> {
  FocusNode? _ownedFocus;
  FocusNode get _focus =>
      widget.focusNode ?? (_ownedFocus ??= FocusNode(debugLabel: 'Find agent'));

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // The dialog veil also requests fallback focus in this frame. The
        // search field must win so the first keystroke starts searching.
        if (mounted && ModalRoute.of(context)?.isCurrent != false) {
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onMove = widget.onMove;
    final onSubmitted = widget.onSubmitted;
    return CallbackShortcuts(
      bindings: {
        if (onSubmitted != null) ...{
          const SingleActivator(
            LogicalKeyboardKey.enter,
            includeRepeats: false,
          ): onSubmitted,
          const SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            includeRepeats: false,
          ): onSubmitted,
        },
        if (onMove != null) ...{
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => onMove(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => onMove(-1),
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
              onMove(1),
          const SingleActivator(LogicalKeyboardKey.keyP, control: true): () =>
              onMove(-1),
          const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
              onMove(1),
          const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
              onMove(-1),
        },
      },
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: (_) => onSubmitted?.call(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, size: 18),
          filled: true,
          fillColor: const Color(0xa6111521),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
        ),
      ),
    );
  }
}

class _StarterRow extends StatelessWidget {
  const _StarterRow({
    required this.name,
    required this.count,
    required this.onTap,
    this.note,
    this.onManage,
  });
  final String name;
  final int count;
  final VoidCallback onTap;
  final String? note;
  final VoidCallback? onManage;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: Row(
          children: [
            const SwarmIcon(size: 19, color: Colors.white60),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (note != null) ...[
              const SizedBox(width: 6),
              Text(
                note!,
                style: const TextStyle(fontSize: 10, color: Colors.white54),
              ),
            ],
            const SizedBox(width: 12),
            Text(
              '$count',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(width: 8),
            if (onManage == null)
              const Icon(Icons.chevron_right, size: 14, color: Colors.white54)
            else
              PopupMenuButton<String>(
                tooltip: 'Project options for $name',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 180),
                icon: const Icon(
                  Icons.more_horiz,
                  size: 16,
                  color: Colors.white54,
                ),
                style: IconButton.styleFrom(
                  minimumSize: const Size(24, 24),
                  maximumSize: const Size(24, 24),
                  padding: EdgeInsets.zero,
                ),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'agents', child: Text('Choose agents…')),
                ],
                onSelected: (_) => onManage!(),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: grid.AppPalette.swarmSearchSurface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}
