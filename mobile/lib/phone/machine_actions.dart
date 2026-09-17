import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/state/app_state.dart';

import 'link_page.dart';
import 'machine_index.dart';
import 'phone_navigation.dart';
import 'phone_sheet.dart';
import 'phone_status.dart';
import 'unlink_machine.dart';

/// Every machine on the account as sheet rows, for the terminal's `⋯` menu — where machines are
/// reached now that search lists agents only.
///
/// Each row carries its state as a word, and does what that state calls for: a password form, a
/// sheet of actions, or — offline — nothing, drawn dimmed so its absence is not a mystery.
List<PhoneSheetAction> machineSheetRows(
  BuildContext context,
  AppNotifier notifier,
) => [
  for (final machine in visibleMachines(notifier))
    PhoneSheetAction(
      icon: LucideIcons.laptopMinimal300,
      label: machine.machine.displayName,
      value: _stateWord(machine),
      valueColor: _stateColor(machine),
      enabled: phoneMachineStatusOf(machine) != PhoneMachineStatus.offline,
      onTap: () =>
          openMachineActions(context, notifier, machine.machine.machineId),
    ),
];

/// Green for a machine that answers, yellow for one waiting on its password — the two states worth
/// telling apart at a glance. The rest keep the row's faint colour.
Color? _stateColor(MachineState machine) =>
    switch (phoneMachineStatusOf(machine)) {
      PhoneMachineStatus.ready => AppPalette.online,
      PhoneMachineStatus.needsPassword => AppPalette.warn,
      PhoneMachineStatus.connecting => AppPalette.accent,
      PhoneMachineStatus.offline => null,
    };

String _stateWord(MachineState machine) =>
    switch (phoneMachineStatusOf(machine)) {
      PhoneMachineStatus.ready => 'Connected',
      PhoneMachineStatus.connecting => 'Connecting…',
      PhoneMachineStatus.needsPassword => 'Unlock',
      PhoneMachineStatus.offline => 'Offline',
    };

/// A machine that wants its password opens the form for it. One that is linked opens a sheet of
/// what can be done TO it — reload its agents, re-enter its password, unlink this phone.
///
/// Read at the tap, not when the row was drawn, so a machine that got linked in between gets the
/// sheet rather than a form it no longer needs.
void openMachineActions(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
) {
  final machine = notifier.stateOf(machineId);
  if (machine == null) return;
  switch (phoneMachineStatusOf(machine)) {
    case PhoneMachineStatus.offline:
      return;
    case PhoneMachineStatus.needsPassword:
      openMachine(context, notifier, machineId);
      return;
    case PhoneMachineStatus.connecting || PhoneMachineStatus.ready:
      break;
  }
  showPhoneSheet(
    context,
    title: machine.machine.displayName,
    actions: [
      PhoneSheetAction(
        icon: LucideIcons.refreshCw300,
        label: 'Reload agents',
        onTap: () => unawaited(notifier.reloadMachineData(machineId)),
      ),
      PhoneSheetAction(
        icon: LucideIcons.keyRound300,
        label: 'Re-enter password…',
        onTap: () => Navigator.of(context).push(
          phoneRoute((_) => LinkPage(notifier: notifier, machineId: machineId)),
        ),
      ),
      // No confirmation, the same as the Machines tab: this sheet is the step between the tap and
      // the unlink.
      PhoneSheetAction(
        icon: LucideIcons.unlink300,
        label: 'Unlink this phone',
        destructive: true,
        onTap: () => unawaited(unlinkThisPhone(context, notifier, machine)),
      ),
    ],
  );
}
