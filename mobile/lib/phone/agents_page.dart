import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shared/widgets/app_icon_button.dart';
import 'package:harness/shared/widgets/empty_state.dart';
import 'package:harness/state/app_state.dart';

import 'agent_tile.dart';
import 'link_page.dart';
import 'phone_card.dart';
import 'new_agent_page.dart';
import 'phone_header.dart';
import 'phone_navigation.dart';
import 'phone_sheet.dart';
import 'phone_status.dart';
import 'status_pill.dart';

/// One machine's agents. A tap opens that agent full screen, and it is the only one open.
class AgentsPage extends StatelessWidget {
  const AgentsPage({
    super.key,
    required this.notifier,
    required this.machineId,
  });

  final AppNotifier notifier;
  final String machineId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final machine = notifier.stateOf(machineId);
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PhoneHeader(
                title: machine?.machine.displayName ?? 'Machine',
                subtitle: machine == null
                    ? null
                    : StatusPill(summary: phoneMachineSummary(machine)),
                trailing: [
                  // Only once the machine is answering: creating needs it to
                  // list its folders and say which engines it has, and a button
                  // that opens a page with neither is a dead end.
                  if (machine != null &&
                      phoneMachineStatusOf(machine) == PhoneMachineStatus.ready)
                    AppIconButton(
                      icon: LucideIcons.plus300,
                      size: 20,
                      tooltip: 'New agent',
                      color: AppPalette.textSecondary,
                      onPressed: () =>
                          _openNewAgent(context, notifier, machineId),
                    ),
                  if (machine != null)
                    AppIconButton(
                      icon: LucideIcons.ellipsis300,
                      size: 20,
                      tooltip: 'Machine actions',
                      color: AppPalette.textSecondary,
                      onPressed: () =>
                          _showMachineActions(context, notifier, machine),
                    ),
                ],
              ),
              if (machine != null)
                Expanded(
                  child: _AgentsBody(notifier: notifier, machine: machine),
                ),
            ],
          ),
        ),
      );
    },
  );

  void _showMachineActions(
    BuildContext context,
    AppNotifier notifier,
    MachineState machine,
  ) {
    final machineId = machine.machine.machineId;
    final linked = !machine.needsLink;
    showPhoneSheet(
      context,
      title: machine.machine.displayName,
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.refreshCw300,
          label: 'Reload agents',
          onTap: () => unawaited(notifier.reloadMachineData(machineId)),
        ),
        // Only where there is a link to replace. A machine that never had one reaches its form by
        // being tapped, which is the same screen this would open.
        if (linked)
          PhoneSheetAction(
            icon: LucideIcons.keyRound300,
            label: 'Re-enter password…',
            onTap: () => Navigator.of(context).push(
              phoneRoute(
                (_) => LinkPage(notifier: notifier, machineId: machineId),
              ),
            ),
          ),
        if (linked)
          PhoneSheetAction(
            icon: LucideIcons.unlink300,
            label: 'Unlink this phone…',
            destructive: true,
            onTap: () => unawaited(_confirmUnlink(context, notifier, machine)),
          ),
      ],
    );
  }

  /// Unlinking drops THIS device's trust pin for the machine — see `AppNotifier.unlinkMachine`,
  /// which is deliberately not `deleteMachine`. The wording says so, because "Unlink" alone reads
  /// as removing the machine from the account, which is a different and much larger thing.
  Future<void> _confirmUnlink(
    BuildContext context,
    AppNotifier notifier,
    MachineState machine,
  ) async {
    final name = machine.machine.displayName;
    final confirmed = await confirmPhoneAction(
      context,
      title: 'Unlink $name?',
      message:
          'This phone will need $name\'s password again to open its agents. '
          'The machine itself is not changed, and its agents keep running.',
      confirmLabel: 'Unlink',
    );
    if (!confirmed || !context.mounted) return;
    final error = await notifier.unlinkMachine(machine.machine.machineId);
    if (!context.mounted) return;
    if (error != null) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // The page is now showing a machine this phone can no longer open; the list behind it is where
    // the re-link starts.
    Navigator.of(context).maybePop();
  }
}

class _AgentsBody extends StatelessWidget {
  const _AgentsBody({required this.notifier, required this.machine});

  final AppNotifier notifier;
  final MachineState machine;

  String get _machineId => machine.machine.machineId;

  @override
  Widget build(BuildContext context) {
    final agents = machine.agents;
    final status = phoneMachineStatusOf(machine);
    if (status == PhoneMachineStatus.needsPassword) {
      return EmptyState(
        icon: LucideIcons.lockKeyhole300,
        title: 'This machine needs its password',
        message: 'Every machine has its own. Enter it once to link this phone.',
        action: FilledButton(
          onPressed: () => Navigator.of(context).pushReplacement(
            phoneRoute(
              (_) => LinkPage(notifier: notifier, machineId: _machineId),
            ),
          ),
          child: const Text('Enter password'),
        ),
      );
    }
    if (status == PhoneMachineStatus.offline) {
      return EmptyState(
        icon: LucideIcons.cloudOff300,
        title: "Harness isn't running there",
        message:
            'Start Harness on ${machine.machine.displayName} and its agents '
            'will show up here.',
      );
    }
    if (agents.isEmpty && status == PhoneMachineStatus.connecting) {
      return const PhoneListSkeleton();
    }
    final loadError = machine.agentsLoadError;
    if (agents.isEmpty && loadError != null) {
      return EmptyState(
        icon: LucideIcons.circleAlert300,
        title: "Couldn't load its agents",
        message: loadError,
        action: FilledButton(
          onPressed: () => notifier.reloadMachineData(_machineId),
          child: const Text('Try again'),
        ),
      );
    }
    if (agents.isEmpty) {
      return EmptyState(
        icon: LucideIcons.squareTerminal300,
        title: 'No agents yet',
        message: 'Start one here, or from Harness on that machine.',
        action: FilledButton(
          onPressed: () => _openNewAgent(context, notifier, _machineId),
          child: const Text('New agent'),
        ),
      );
    }
    return PhoneCardList(
      onRefresh: () => notifier.reloadMachineData(_machineId),
      itemCount: agents.length,
      itemBuilder: (context, index) => AgentTile(
        machine: machine,
        agent: agents[index],
        onTap: () => openAgent(context, notifier, _machineId, agents[index].id),
        onLongPress: () =>
            showAgentActions(context, notifier, _machineId, agents[index]),
      ),
    );
  }
}

/// One agent's `⋯`, reached by holding its row.
///
/// The desktop offers this from the rail row's menu and the pane's; a phone has neither, so the
/// hold is the whole door. Kept public and out of [_AgentsBody] so the terminal page can open the
/// same sheet if it ever grows one, rather than writing a second wording of the same act.
Future<void> showAgentActions(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  Agent agent,
) => showPhoneSheet(
  context,
  title: agent.name,
  actions: [
    PhoneSheetAction(
      icon: LucideIcons.trash2300,
      label: 'Delete agent…',
      destructive: true,
      onTap: () =>
          unawaited(_confirmDeleteAgent(context, notifier, machineId, agent)),
    ),
  ],
);

/// ⚠️ Deletion destroys the agent on the machine — unlike unlinking above, which only forgets a
/// password. The wording has to carry that, because both arrive through the same red sheet row.
///
/// Nothing here removes the row: `AppNotifier.deleteAgent` drops the agent from the machine's list
/// and detaches every pane still showing it, and this page rebuilds off that notifier.
Future<void> _confirmDeleteAgent(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  Agent agent,
) async {
  final confirmed = await confirmPhoneAction(
    context,
    title: 'Delete ${agent.name}?',
    message:
        'The agent and its terminal session are removed from the machine, '
        "along with any work it has not finished. This can't be undone.",
    confirmLabel: 'Delete',
  );
  if (!confirmed || !context.mounted) return;
  final error = await notifier.deleteAgent(machineId, agent.id);
  if (error == null || !context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(error)));
}

/// The one way into [NewAgentPage], so the header's button and the empty
/// state's cannot drift into opening it two different ways.
void _openNewAgent(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
) => Navigator.of(context).push(
  phoneRoute((_) => NewAgentPage(notifier: notifier, machineId: machineId)),
);
