import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Relaunches the same harness through the existing CLI restart action.
Future<void> restartHarness(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  String agentId,
) async {
  final result = await notifier.restartAgent(machineId, agentId);
  if (!context.mounted) return;
  final message =
      result.error ??
      (result.resumed
          ? null
          : 'Restarted with a new session — the previous one could not be resumed.');
  if (message != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
