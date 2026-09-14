import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_navigation.dart';
import 'engine_identity.dart';

class SwarmWelcome extends StatefulWidget {
  const SwarmWelcome({
    super.key,
    required this.notifier,
    required this.onNewAgent,
    required this.searchField,
    required this.onLinkMachine,
    this.onChooseFirstFolder,
    this.recent = const [],
    this.onRecent,
  });

  final AppNotifier notifier;
  final VoidCallback onNewAgent, onLinkMachine;
  final VoidCallback? onChooseFirstFolder;
  final Widget searchField;
  final List<String> recent;
  final ValueChanged<SwarmDestination>? onRecent;

  @override
  State<SwarmWelcome> createState() => _SwarmWelcomeState();
}

/// One quiet starting point for first launch and every empty tab.
class _SwarmWelcomeState extends State<SwarmWelcome> {
  bool _reconnecting = false;
  final _catalog = SwarmSearchCatalog();

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
    final catalog = _catalog.read(app, const [], recent: widget.recent);
    final agents = {
      for (final row in catalog)
        if (row.agentId != null) row.id: row,
    };
    final recent = <SwarmDestination>[
      for (final id in {
        ...widget.recent,
        ...agents.values.where((row) => row.hasView).map((row) => row.id),
      })
        ?agents[id],
    ].take(6).toList();
    final create = FilledButton.icon(
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
      icon: Icon(canCreate ? Icons.add : Icons.computer_outlined, size: 20),
      label: Text(
        canCreate
            ? 'Create harness'
            : finding
            ? 'Finding computers…'
            : needsLink
            ? 'Link a machine'
            : 'Reconnect',
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size(180, 56),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        backgroundColor: grid.AppPalette.swarmAccent,
        foregroundColor: grid.AppPalette.swarmTabBar,
        textStyle: TextStyle(
          fontFamily: grid.AppFont.sans,
          fontFamilyFallback: grid.AppFont.sansFallback,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: const StadiumBorder(),
      ),
    );

    return FocusScope(
      // An empty tab must not take keyboard input from an open dialog.
      canRequestFocus: ModalRoute.isCurrentOf(context) != false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
          final padding = constraints.maxWidth < 600 ? 24.0 : 48.0;
          final recentWidth =
              ((constraints.maxWidth - padding * 2 - 60) / 6).clamp(
                104.0,
                128.0,
              ) *
              textScale.clamp(1.0, 1.5);
          return SingleChildScrollView(
            key: const ValueKey('swarm-welcome-scroll'),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  padding,
                  (constraints.maxHeight * .16).clamp(40.0, 132.0),
                  padding,
                  40,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'New Harness',
                          key: ValueKey('welcome-title'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 44,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -1,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 32),
                        LayoutBuilder(
                          builder: (context, size) {
                            if (size.maxWidth < 700 * textScale) {
                              return Column(
                                children: [
                                  widget.searchField,
                                  const SizedBox(height: 16),
                                  create,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: widget.searchField),
                                const SizedBox(width: 14),
                                create,
                              ],
                            );
                          },
                        ),
                        if (!canCreate && !finding) ...[
                          const SizedBox(height: 14),
                          Text(
                            needsLink
                                ? 'Connect a computer to create your first harness.'
                                : 'Your computers are offline. Reconnect to start something new.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                        if (recent.isNotEmpty && widget.onRecent != null) ...[
                          const SizedBox(height: 32),
                          const Text(
                            'Recent harnesses',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white60,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final row in recent)
                                SizedBox(
                                  width: recentWidth,
                                  child: _RecentHarness(
                                    key: ValueKey('welcome-recent:${row.id}'),
                                    entry: row,
                                    onPressed: () => widget.onRecent!(row),
                                  ),
                                ),
                            ],
                          ),
                        ],
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

class _RecentHarness extends StatelessWidget {
  const _RecentHarness({
    super.key,
    required this.entry,
    required this.onPressed,
  });
  final SwarmDestination entry;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '${entry.title}\n${entry.detail}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        hoverColor: Colors.white.withValues(alpha: .05),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: grid.AppPalette.swarmSearchSurface,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: EngineMark(engine: entry.engine, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                entry.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                entry.machineLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
