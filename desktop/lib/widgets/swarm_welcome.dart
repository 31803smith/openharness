import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/skeleton.dart';
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';
import 'engine_identity.dart';

class SwarmWelcome extends StatelessWidget {
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
    this.onAgent,
    this.onProjectAgents,
  });
  final AppNotifier notifier;
  final List<SavedSwarmProject> projects;
  final VoidCallback onNewAgent;
  final VoidCallback? onChooseFirstFolder;
  final Widget searchField;
  final VoidCallback onAddProject;
  final VoidCallback onLinkMachine;
  final ValueChanged<MachineState> onMachine;
  final ValueChanged<SwarmProjectGroup> onProject;
  final ValueChanged<SwarmAgentRef>? onAgent;
  final ValueChanged<SwarmProjectGroup>? onProjectAgents;
  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final app = notifier;
    final groups = swarmProjects(app, projects);
    final firstWorkspace =
        app.swarms.every((swarm) => swarm.panes.isEmpty) &&
        app.closedHistory.isEmpty;
    final agents = firstWorkspace ? swarmAgents(app) : const <SwarmAgentRef>[];
    final noAgents =
        firstWorkspace &&
        !app.machinesLoading &&
        agents.isEmpty &&
        groups.isEmpty &&
        app.machineStates.length == 1 &&
        app.machineStates.values.first.isLocalMachine &&
        app.machineStates.values.first.agentLoadStatus ==
            AgentLoadStatus.loaded &&
        app.machineStates.values.first.nodeOnline != false &&
        !app.machineStates.values.first.needsLink;
    final chooseFirstFolder = noAgents && onChooseFirstFolder != null;
    final readyAgents =
        agents
            .where(
              (entry) =>
                  !entry.machine.needsLink &&
                  entry.machine.nodeOnline != false &&
                  entry.agent.terminalAvailable,
            )
            .toList()
          ..sort((a, b) {
            if (a.machine.isLocalMachine != b.machine.isLocalMachine) {
              return a.machine.isLocalMachine ? -1 : 1;
            }
            return a.agent.name.toLowerCase().compareTo(
              b.agent.name.toLowerCase(),
            );
          });
    return Stack(
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  padding: const EdgeInsets.fromLTRB(56, 40, 56, 62),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        noAgents ? 'Start with one agent' : 'Start a swarm',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.7,
                          color: Colors.white,
                          shadows: [
                            Shadow(blurRadius: 16, color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        noAgents
                            ? 'Choose a project folder and an agent. Add more whenever you want to work side by side.'
                            : 'A swarm keeps related agents together. Open a machine or project to bring its agents into this tab.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xffe0dce3),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(child: searchField),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: chooseFirstFolder
                                ? onChooseFirstFolder
                                : onNewAgent,
                            icon: Icon(
                              chooseFirstFolder
                                  ? Icons.folder_open_outlined
                                  : Icons.add,
                              size: 17,
                            ),
                            label: Text(
                              chooseFirstFolder
                                  ? 'Choose folder…'
                                  : 'New agent',
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(126, 44),
                              backgroundColor: grid.AppPalette.swarmAccent,
                              foregroundColor: grid.AppPalette.swarmTabBar,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
                      if (noAgents)
                        _Glass(
                          child: _FirstAgentGuide(onLinkMachine: onLinkMachine),
                        )
                      else ...[
                        if (onAgent != null && readyAgents.isNotEmpty) ...[
                          _Glass(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Go to an agent',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (final entry in readyAgents.take(3))
                                  ListTile(
                                    key: ValueKey(
                                      'welcome-agent:${entry.machineId}:${entry.agent.id}',
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    leading: EngineMark(
                                      engine: entry.agent.engine,
                                      size: 22,
                                    ),
                                    title: Text(
                                      entry.agent.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      [
                                        entry.machine.machine.displayName,
                                        entry.project?.name,
                                      ].whereType<String>().join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    onTap: () => onAgent!(entry),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        _Glass(
                          child: LayoutBuilder(
                            builder: (context, size) {
                              final machines = _section(
                                'Machines',
                                'Link machine',
                                onLinkMachine,
                                [
                                  if (app.machinesLoading &&
                                      app.machineStates.isEmpty)
                                    const SkeletonList(rows: 3),
                                  for (final machine
                                      in app.machineStates.values)
                                    _StarterRow(
                                      icon: Icons.computer_outlined,
                                      name: machine.machine.displayName,
                                      note: machine.needsLink
                                          ? 'Link required'
                                          : machine.nodeOnline == false
                                          ? 'Offline'
                                          : machine.isLocalMachine
                                          ? 'Local'
                                          : null,
                                      count: machine.agents.length,
                                      onTap: () => onMachine(machine),
                                    ),
                                  if (!app.machinesLoading &&
                                      app.machineStates.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        'Link a machine to find its agents.',
                                      ),
                                    ),
                                ],
                              );
                              final projects = _section(
                                'Projects',
                                'Add project',
                                onAddProject,
                                [
                                  for (final group in groups)
                                    _StarterRow(
                                      icon: Icons.folder_outlined,
                                      name: group.name,
                                      count: group.agents.length,
                                      onTap: () => onProject(group),
                                      onManage: onProjectAgents == null
                                          ? null
                                          : () => onProjectAgents!(group),
                                    ),
                                  if (groups.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        'Add a working folder to start a project.',
                                        style: TextStyle(
                                          color: Color(0xffc5bece),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              );
                              return size.maxWidth < 570
                                  ? Column(
                                      children: [
                                        machines,
                                        const SizedBox(height: 24),
                                        projects,
                                      ],
                                    )
                                  : Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: machines),
                                        const SizedBox(width: 36),
                                        Expanded(child: projects),
                                      ],
                                    );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(
    String title,
    String action,
    VoidCallback onAction,
    List<Widget> children,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            child: Text(action, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      ...children,
    ],
  );
}

class _FirstAgentGuide extends StatelessWidget {
  const _FirstAgentGuide({required this.onLinkMachine});
  final VoidCallback onLinkMachine;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Your first workspace',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 16),
      for (final (number, title, detail) in const [
        ('1', 'Choose a folder', 'Use a project you already work on.'),
        (
          '2',
          'Pick your agent',
          'Claude Code, Codex, or another coding agent.',
        ),
        (
          '3',
          'Start working',
          'Your agent opens here. Sign in if needed, then give it a task.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white10,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      TextButton(
        onPressed: onLinkMachine,
        child: const Text(
          'Link another machine',
          style: TextStyle(color: Colors.white70),
        ),
      ),
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
    required this.icon,
    required this.name,
    required this.count,
    required this.onTap,
    this.note,
    this.onManage,
  });
  final IconData icon;
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
            Icon(icon, size: 17, color: Colors.white60),
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

class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0x80111522),
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    ),
  );
}
