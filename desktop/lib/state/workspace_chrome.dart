import 'package:flutter/widgets.dart';

/// The workspace's command table as a host composition sees it: the same ids
/// and callbacks keys, native menus and the command box already run.
class WorkspaceCommands {
  const WorkspaceCommands({
    required this.enabled,
    required this.canRun,
    required this.run,
  });

  /// False while a dialog or route owns the window; bar controls go inert.
  final bool Function() enabled;
  final bool Function(String id) canRun;
  final void Function(String id) run;
}

/// What a host composition adds to the shared workspace. Desktop passes none;
/// the web build (`lib/web/`) puts its mouse-first menu before the tabs and
/// names a machine for New Harness. [leadingWidth] is reserved before the tabs
/// are measured.
class WorkspaceChrome {
  const WorkspaceChrome({
    required this.leadingWidth,
    required this.leading,
    this.newHarnessMachine,
  });

  final double Function(BuildContext context) leadingWidth;
  final Widget Function(BuildContext context, WorkspaceCommands commands)
  leading;

  /// Where New Harness starts when no machine is this computer — a browser
  /// runs none. Null (or no answer) keeps sending the person to Machines.
  final String? Function()? newHarnessMachine;
}
