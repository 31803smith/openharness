import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';

/// Shared Stop Harness confirmation. The legacy agent_delete request stops the
/// engine and removes its active entry, preserving files and saved history.
Future<void> confirmDeleteAgent(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  String agentId,
  String name,
) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Stop Harness'),
      content: SizedBox(
        width: 360,
        child: Text(
          'Stop “$name”? This ends the running agent and removes it from your '
          'active harnesses. Project files and saved conversation history are kept.',
          style: TextStyle(fontFamily: grid.AppFont.sans, fontSize: 13.5),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: grid.AppPalette.dangerFill,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Stop Harness'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final error = await notifier.deleteAgent(machineId, agentId);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
