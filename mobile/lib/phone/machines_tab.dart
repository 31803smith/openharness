import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/empty_state.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'machine_tile.dart';
import 'phone_card.dart';
import 'phone_header.dart';
import 'phone_navigation.dart';
import 'phone_status.dart';

/// The machines on the account, grouped by what they need.
///
/// The desktop lists machines in account order, because its rail shows every one at once and the
/// order is the only stable thing about it. A phone screen holds five or six rows, so the order
/// has to carry meaning instead: the machines that are linked and working go first, because those
/// are the ones somebody opens day to day. The machines that want something — a password, a
/// Harness that is not running — collect underneath, where they read as a to-do list rather than
/// as the thing standing between you and the machine you actually came for.
class MachinesTab extends StatelessWidget {
  const MachinesTab({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const PhoneHeader(large: true, title: 'Machines'),
              Expanded(child: _Body(notifier: notifier)),
            ],
          ),
        ),
      );
    },
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final states = [
      for (final machine in notifier.machines)
        ?notifier.stateOf(machine.machineId),
    ];
    if (states.isEmpty && notifier.machinesLoading) {
      return const PhoneListSkeleton();
    }
    if (states.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.laptopMinimal300,
        title: 'No machines yet',
        message:
            'Run Harness on a computer signed in to this account and it will '
            'appear here.',
      );
    }

    // Two runs, by whether the machine is usable as it stands. A machine that is merely connecting
    // belongs with the working ones: it needs nothing from anybody, it is just not ready yet.
    // The runs are built in this order and rendered working-first; see the class comment.
    final needsAttention = <MachineState>[];
    final working = <MachineState>[];
    for (final state in states) {
      switch (phoneMachineStatusOf(state)) {
        case PhoneMachineStatus.needsPassword:
        case PhoneMachineStatus.offline:
          needsAttention.add(state);
        case PhoneMachineStatus.connecting:
        case PhoneMachineStatus.ready:
          working.add(state);
      }
    }

    return RefreshIndicator(
      onRefresh: notifier.retryMachines,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: phoneListPadding(context),
        children: [
          if (working.isNotEmpty) ...[
            const _SectionLabel('Linked'),
            for (final state in working) _tile(context, state),
            const SizedBox(height: 6),
          ],
          if (needsAttention.isNotEmpty) ...[
            if (working.isNotEmpty)
              const _SectionLabel('Needs your attention'),
            for (final state in needsAttention) _tile(context, state),
          ],
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, MachineState state) => Padding(
    padding: const EdgeInsets.only(bottom: kPhoneCardGap),
    child: MachineTile(
      machine: state,
      onTap: () => openMachine(context, notifier, state.machine.machineId),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppPalette.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
