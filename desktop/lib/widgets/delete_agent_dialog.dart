import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';

/// The one "Delete agent" confirmation, opened from every place an agent can
/// be deleted: the rail's row menu and the pane's ⋯ menu.
///
/// Pulled out of the rail for the reason the rename dialog was: two copies
/// would have been two wordings of one irreversible act, and two ways of
/// reporting that it failed. Returns once the agent is gone or the person
/// backed out; a failure is shown as a snackbar, the way the rail always did.
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
      title: const Text('Delete agent'),
      content: SizedBox(
        width: 360,
        child: Text(
          "Delete “$name”? This can't be undone.",
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
  final error = await notifier.deleteAgent(machineId, agentId);
  if (error != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }
}
