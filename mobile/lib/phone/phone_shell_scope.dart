import 'package:flutter/widgets.dart';

/// What a page deep inside one tab can ask of the shell around all three.
///
/// The pages live in per-tab navigators, so none of them can switch tabs or push onto another tab's
/// stack by itself. A password form finishing is the one moment that has to: the form is on the
/// Machines tab, and what the person came for is the agent, on the Agents tab.
class PhoneShellScope extends InheritedWidget {
  const PhoneShellScope({
    super.key,
    required this.onMachineLinked,
    required super.child,
  });

  /// Called once a machine's password has been accepted — the shell takes the person to that
  /// machine's first agent as soon as the machine answers.
  final void Function(String machineId) onMachineLinked;

  /// Null outside the shell — a page pumped on its own in a test simply has nowhere to go.
  static PhoneShellScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PhoneShellScope>();

  @override
  bool updateShouldNotify(PhoneShellScope oldWidget) => false;
}
