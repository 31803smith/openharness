import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/skeleton.dart';
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';

class SwarmWelcome extends StatelessWidget {
  const SwarmWelcome({
    super.key,
    required this.notifier,
    required this.projects,
    required this.onNewAgent,
    required this.onSearch,
    required this.onAddProject,
    required this.onLinkMachine,
    required this.onMachine,
    required this.onProject,
    this.onProjectAgents,
  });
  final AppNotifier notifier;
  final List<SavedSwarmProject> projects;
  final VoidCallback onNewAgent;
  final VoidCallback onSearch;
  final VoidCallback onAddProject;
  final VoidCallback onLinkMachine;
  final ValueChanged<MachineState> onMachine;
  final ValueChanged<SwarmProjectGroup> onProject;
  final ValueChanged<SwarmProjectGroup>? onProjectAgents;
  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final app = notifier;
    final groups = swarmProjects(app, projects);
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
                      const Text(
                        'Start a swarm',
                        style: TextStyle(
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
                      const Text(
                        'Choose a machine or project, or add agents individually.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xffe0dce3),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              autofocus: true,
                              onPressed: onSearch,
                              icon: const Icon(Icons.search, size: 18),
                              label: const Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Search agents, swarms, machines, projects…',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text('⌘P'),
                                ],
                              ),
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                minimumSize: const Size(0, 44),
                                foregroundColor: const Color(0xffc5bece),
                                backgroundColor: const Color(0xa6111521),
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: onNewAgent,
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('New agent'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(126, 44),
                              backgroundColor: grid.AppPalette.swarmAccent,
                              foregroundColor: grid.AppPalette.swarmTabBar,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 34),
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
                                for (final machine in app.machineStates.values)
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
                                    padding: EdgeInsets.symmetric(vertical: 18),
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
                                    padding: EdgeInsets.symmetric(vertical: 18),
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
            child: Text(action, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
      const SizedBox(height: 8),
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
