import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';

/// Shared "Delete machine" confirmation, used by the sidebar rail's context
/// menu and the native Machines menu. Delete disconnects the machine's agents
/// and drops the link (see [AppNotifier.deleteMachine]); it cannot be undone.
Future<void> confirmDeleteMachine(
  BuildContext context,
  AppNotifier notifier, {
  required String machineId,
  required String displayName,
}) async {
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete machine'),
      content: SizedBox(
        width: 360,
        child: Text(
          'Delete "$displayName"? All its agents will be disconnected and '
          "it'll need to be linked again. This can't be undone.",
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
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final error = await notifier.deleteMachine(machineId);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
