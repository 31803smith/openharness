import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';

class SwarmWelcome extends StatefulWidget {
  const SwarmWelcome({
    super.key,
    required this.notifier,
    required this.onNewAgent,
    required this.searchField,
    required this.onLinkMachine,
    this.onChooseFirstFolder,
  });

  final AppNotifier notifier;
  final VoidCallback onNewAgent, onLinkMachine;
  final VoidCallback? onChooseFirstFolder;
  final Widget searchField;

  @override
  State<SwarmWelcome> createState() => _SwarmWelcomeState();
}

/// First launch and every empty tab offer the same two entry points.
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
    final app = widget.notifier;
    bool ready(MachineState machine) =>
        !machine.needsLink && machine.nodeOnline != false;
    final existing =
        app.allPanes.any((pane) => pane.agentId != null) ||
        swarmAgents(app).any((entry) => entry.agent.terminalAvailable);
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
    final find = _AgentEntryCard(
      key: const ValueKey('welcome-find-agent'),
      icon: Icons.search_rounded,
      title: 'Find an agent',
      description:
          'Pick up where you left off. Search by agent, machine, or project.',
      action: widget.searchField,
    );
    final create = _AgentEntryCard(
      key: const ValueKey('welcome-create-agent'),
      icon: Icons.add_rounded,
      title: 'Create a new agent',
      description:
          'Start fresh. Choose an agent, a machine, and a working folder.',
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: const ValueKey('swarm-start-primary'),
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
              canCreate ? Icons.add : Icons.computer_outlined,
              size: 20,
            ),
            label: Text(
              canCreate
                  ? 'Create Agent'
                  : finding
                  ? 'Finding your computers…'
                  : needsLink
                  ? 'Link a machine'
                  : 'Reconnect',
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 58),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              backgroundColor: grid.AppPalette.swarmAccent,
              foregroundColor: grid.AppPalette.swarmTabBar,
              textStyle: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontFamilyFallback: grid.AppFont.sansFallback,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (!canCreate && !finding) ...[
            const SizedBox(height: 12),
            Text(
              needsLink
                  ? 'Connect a computer to create your first agent.'
                  : 'Your computers are offline. Reconnect to create an agent.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: Colors.white60,
              ),
            ),
          ],
        ],
      ),
    );

    return FocusScope(
      // An empty tab must not take keyboard input from an open dialog.
      canRequestFocus: ModalRoute.isCurrentOf(context) != false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final padding = constraints.maxWidth < 600 ? 24.0 : 48.0;
          return SingleChildScrollView(
            key: const ValueKey('swarm-welcome-scroll'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: padding,
                  vertical: 48,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New Agent',
                          key: ValueKey('welcome-title'),
                          style: TextStyle(
                            fontSize: 32,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Resume existing work or start something new.',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 32),
                        LayoutBuilder(
                          builder: (context, size) {
                            if (size.maxWidth < 840 * textScale) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  find,
                                  const SizedBox(height: 20),
                                  create,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: find),
                                const SizedBox(width: 24),
                                Expanded(child: create),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AgentEntryCard extends StatelessWidget {
  const _AgentEntryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
  });

  final IconData icon;
  final String title, description;
  final Widget action;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 320),
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: grid.AppPalette.swarmSearchSurface.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .16)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: grid.AppPalette.swarmAccent.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 26, color: grid.AppPalette.swarmAccent),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          style: const TextStyle(
            fontSize: 23,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 28),
        action,
      ],
    ),
  );
}
