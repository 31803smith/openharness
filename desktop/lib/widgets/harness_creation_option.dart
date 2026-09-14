import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';

/// A separate creation choice below the shared search card.
class HarnessCreationOption extends StatefulWidget {
  const HarnessCreationOption({
    super.key,
    required this.buttonKey,
    required this.onPressed,
    required this.notifier,
    required this.onLinkMachine,
  });

  final Key buttonKey;
  final VoidCallback? onPressed;
  final AppNotifier notifier;
  final VoidCallback onLinkMachine;

  @override
  State<HarnessCreationOption> createState() => _HarnessCreationOptionState();
}

class _HarnessCreationOptionState extends State<HarnessCreationOption> {
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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) {
      final app = widget.notifier;
      bool ready(MachineState machine) =>
          !machine.needsLink && machine.nodeOnline != false;
      final canCreate =
          app.machineStates.values.any(ready) ||
          app.allPanes.any((pane) => pane.agentId != null) ||
          swarmAgents(app).any((entry) => entry.agent.terminalAvailable);
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
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 160,
            child: Row(
              children: [
                Expanded(child: Divider(color: Colors.white12)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'or',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ),
                Expanded(child: Divider(color: Colors.white12)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          NewHarnessButton(
            key: widget.buttonKey,
            onPressed: widget.onPressed == null
                ? null
                : canCreate
                ? widget.onPressed
                : finding
                ? null
                : needsLink
                ? widget.onLinkMachine
                : _reconnect,
            icon: canCreate ? Icons.add : Icons.computer_outlined,
            label: canCreate
                ? 'New Harness'
                : finding
                ? 'Finding computers…'
                : needsLink
                ? 'Link a machine'
                : 'Reconnect',
          ),
        ],
      );
    },
  );
}

/// The fresh-harness action below search results.
class NewHarnessButton extends StatelessWidget {
  const NewHarnessButton({
    super.key,
    required this.onPressed,
    this.label = 'New Harness',
    this.icon = Icons.add,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, textAlign: TextAlign.center),
      style: FilledButton.styleFrom(
        minimumSize: const Size(180, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        backgroundColor: grid.AppPalette.swarmAccent,
        foregroundColor: grid.AppPalette.swarmTabBar,
        disabledBackgroundColor: Colors.white12,
        disabledForegroundColor: Colors.white38,
        textStyle: TextStyle(
          fontFamily: grid.AppFont.sans,
          fontFamilyFallback: grid.AppFont.sansFallback,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
