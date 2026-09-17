import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_checkbox.dart';
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'pane_menu.dart';

/// The one place the "Run a local model" flow is explained.
///
/// Both doors — the pane picker's last row and the window's Models menu — go
/// through [AppNotifier.runLocalModel], which opens this and creates the agent
/// on Start. The dialog itself creates nothing: it answers with what the
/// person decided, and the notifier does the rest, so the two doors cannot
/// drift into two definitions of what Start means.
///
/// Null is Not now (or Escape, or a click outside). A record is Start: the
/// machine the manager opens on, and whether the person asked not to see this
/// again — persisted by the caller, not here, because the store belongs to the
/// notifier.
///
/// [machineId] is the door's own answer to "which computer" — the pane's
/// machine, or the one the menu named — and is what the dialog starts on. With
/// more than one machine linked the dialog shows them and lets the person move
/// the choice; with one, there is nothing to choose and nothing is shown.
Future<({String machineId, bool skipNextTime})?> showRunLocalModelDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
) => showAppDialog<({String machineId, bool skipNextTime})>(
  context: context,
  // Lighter than the app's default veil: this is a two-second yes/no in front
  // of the swarm the person was just looking at, not a screen of its own, and
  // the 90% default read as the window going dark. The blur stays, so what is
  // behind is felt rather than read. Same weight the swarm rename uses.
  veilTint: const Color(0x99000000),
  builder: (_) =>
      _RunLocalModelDialog(notifier: notifier, machineId: machineId),
);

/// Two prerequisites, said only when one is missing, as one sentence with
/// Start disabled: the machine is reachable (a pane cannot open on a computer
/// that is not answering — Start used to fail afterwards with "could not find
/// the home folder", which is the same fact said too late), and it has
/// opencode, because the manager IS an opencode pane. Whether the account has
/// local models set up is NOT checked here — the manager itself says so, in
/// conversation, if it finds nothing; the dialog's job is to let the person
/// pick a machine and go.
enum _Prerequisite { unlinked, offline, opencode }

class _RunLocalModelDialog extends StatefulWidget {
  const _RunLocalModelDialog({required this.notifier, required this.machineId});

  final AppNotifier notifier;
  final String machineId;

  @override
  State<_RunLocalModelDialog> createState() => _RunLocalModelDialogState();
}

class _RunLocalModelDialogState extends State<_RunLocalModelDialog> {
  /// The machine the manager will open on. Starts as the door's answer and
  /// moves when the person picks another; every read below is about THIS one.
  late String _machineId = widget.machineId;

  bool _skipNextTime = false;
  bool _skipHovered = false;

  @override
  void initState() {
    super.initState();
    // One read, fired on open and not waited for: the dialog is readable at
    // once, and a missing opencode appears as it is found. Deferred a frame
    // so a probe's first notifyListeners() does not land mid-build. `force`
    // for the reason New Agent gives — opencode arrives and leaves through a
    // terminal this app never sees, and a stored answer is worth nothing here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _read(_machineId);
    });
  }

  void _read(String machineId) =>
      unawaited(widget.notifier.probeEngines(machineId, force: true));

  void _pickMachine(String machineId) {
    if (machineId == _machineId) return;
    setState(() => _machineId = machineId);
    _read(machineId);
  }

  /// The machines the manager could open on: this computer first, then the
  /// online ones, then the rest — New Agent's order, for the same tiles.
  List<MachineState> get _machines {
    final all = widget.notifier.machines
        .map((m) => widget.notifier.stateOf(m.machineId))
        .whereType<MachineState>()
        .toList();
    int rank(MachineState m) => m.isLocalMachine
        ? 0
        : _online(m)
        ? 1
        : 2;
    final index = {for (var i = 0; i < all.length; i++) all[i]: i};
    all.sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : index[a]!.compareTo(index[b]!);
    });
    return all;
  }

  bool _online(MachineState m) =>
      m.isLocalMachine || (m.nodeOnline == true && !m.needsLink);

  Widget _machineMark(MachineState m, {double size = 14}) => Icon(
    _online(m)
        ? (m.isLocalMachine ? LucideIcons.laptop : LucideIcons.monitor)
        : LucideIcons.monitorOff,
    size: size,
    color: _online(m)
        ? grid.AppPalette.textSecondary
        : grid.AppPalette.textFaint,
    semanticLabel: _online(m) ? 'Online' : 'Offline',
  );

  /// The machine, as one slim two-line row: the mark on the left spanning both
  /// lines, the name above, what it is below ("This machine", or online /
  /// offline for another). The row is the select's own trigger when there is
  /// more than one machine — same row, plus a chevron — and plain otherwise.
  Widget _machineRow(MachineState m, {required bool opens}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _machineMark(m, size: 22),
      const SizedBox(width: 10),
      Flexible(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.machine.displayName,
              key: const Key('run-local-model-machine'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontSize: 12.5,
                height: 1.2,
                color: grid.AppPalette.textPrimary,
              ),
            ),
            Text(
              _kind(m),
              style: TextStyle(
                fontFamily: grid.AppFont.sans,
                fontSize: 11.5,
                height: 1.2,
                color: grid.AppPalette.textSecondary,
              ),
            ),
          ],
        ),
      ),
      if (opens) ...[
        const SizedBox(width: 6),
        Icon(
          LucideIcons.chevronDown,
          size: 12,
          color: grid.AppPalette.textSecondary,
        ),
      ],
    ],
  );

  /// What a machine is, in two words, beside its name.
  String _kind(MachineState m) => m.isLocalMachine
      ? 'This machine'
      : _online(m)
      ? 'Online'
      : 'Offline';

  /// One machine: the slim row, nothing to choose. More: a row of small chips
  /// — up to three, this computer first, the chosen one filled — and a "…"
  /// that opens the pane menu (the same menu the pane's model picker draws,
  /// the current row filled rather than ticked) with every machine. One row
  /// whatever the count; the chosen machine always among the visible chips.
  Widget _machineLine(List<MachineState> machines) {
    final current = widget.notifier.stateOf(_machineId) ?? machines.firstOrNull;
    if (current == null) return const SizedBox.shrink();
    if (machines.length < 2) return _machineRow(current, opens: false);
    final visible = machines.take(3).toList();
    if (!visible.any((m) => m.machine.machineId == _machineId)) {
      visible[visible.length - 1] = current;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Pick the machine it should work on.',
            style: TextStyle(
              fontFamily: grid.AppFont.sans,
              fontSize: 12.5,
              color: grid.AppPalette.textSecondary,
            ),
          ),
        ),
        _chips(visible, machines),
      ],
    );
  }

  Widget _chips(List<MachineState> visible, List<MachineState> machines) => Row(
    children: [
      for (final m in visible) ...[
        Flexible(child: _chip(m)),
        const SizedBox(width: 8),
      ],
      if (machines.length > visible.length)
        _MoreMachines(
          key: const Key('run-local-model-machine-more'),
          onOpen: (context, position) =>
              _openMachineMenu(context, position, machines),
        ),
    ],
  );

  Widget _chip(MachineState m) {
    final selected = m.machine.machineId == _machineId;
    return InkWell(
      key: ValueKey('run-local-model-machine-${m.machine.machineId}'),
      onTap: () => _pickMachine(m.machine.machineId),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.selected : grid.AppSurface.recess,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _machineMark(m),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                m.machine.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: grid.AppFont.sans,
                  fontSize: 12.5,
                  color: grid.AppPalette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMachineMenu(
    BuildContext anchor,
    RelativeRect position,
    List<MachineState> machines,
  ) async {
    final picked = await showPaneMenu<String>(
      context: anchor,
      position: position,
      minWidth: 260,
      children: (close) => [
        paneMenuHeader('Machines'),
        for (final m in machines)
          paneMenuItem(
            onTap: () => close(m.machine.machineId),
            child: PaneMenuRow(
              selected: m.machine.machineId == _machineId,
              leading: _machineMark(m),
              title: m.machine.displayName,
              status: _kind(m),
            ),
          ),
      ],
    );
    if (picked != null && mounted) _pickMachine(picked);
  }

  /// The first missing prerequisite, or null when nothing has been found
  /// missing — which includes "not answered yet".
  _Prerequisite? get _missing {
    final machine = widget.notifier.stateOf(_machineId);
    // Two different facts, two sentences: a machine this computer has no
    // link to is refused by the relay however alive it is, and "offline"
    // would send the person to wake a computer that is already awake.
    if (machine != null && machine.needsLink) return _Prerequisite.unlinked;
    if (machine != null && !_online(machine)) return _Prerequisite.offline;
    if (machine != null && machine.engines.loaded) {
      final opencode = machine.engines['opencode'];
      if (opencode != null && !opencode.installed) {
        return _Prerequisite.opencode;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Lives in an Overlay, so a theme flip never reaches it top-down.
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        final missing = _missing;
        // Said only when something is missing. Satisfied, the dialog says
        // nothing about the machine: the body is the whole message.
        final name =
            widget.notifier.stateOf(_machineId)?.machine.displayName ??
            'That machine';
        final status = switch (missing) {
          _Prerequisite.unlinked =>
            '$name isn’t linked to this computer yet. Link it from the '
                'Machines menu, then come back.',
          _Prerequisite.offline =>
            '$name is offline right now. Wake it up, or pick another machine.',
          _Prerequisite.opencode => 'Needs opencode on this machine first.',
          null => null,
        };
        final machines = _machines;
        return AlertDialog(
          title: const Text('Models that live on your machine'),
          content: SizedBox(
            // Wider than the app's small dialogs: the machine row below wants
            // three names across before it folds the rest behind "…".
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Local model manager',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(
                        text:
                            " is an agent that looks after the models on this "
                            "computer. Say what you need and it helps you pick "
                            "one that fits both this machine and the work, then "
                            "sets it up for you. Once one is up, pick it in any "
                            "agent's model picker.",
                      ),
                    ],
                  ),
                  style: TextStyle(
                    fontFamily: grid.AppFont.sans,
                    fontSize: 13.5,
                    height: 1.5,
                    color: grid.AppPalette.textPrimary,
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    status,
                    key: const Key('run-local-model-status'),
                    style: TextStyle(
                      fontFamily: grid.AppFont.sans,
                      fontSize: 12.5,
                      color: grid.AppPalette.textPrimary,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                // Which computer, as one slim row at the foot of the message:
                // the manager looks after ONE machine's models, so the machine
                // is always named, and never as a control unless there is a
                // choice. With one machine linked it is a mark and two lines;
                // with more, the same row opens a list, this computer first —
                // one row whatever the count, so a long list never spreads
                // through the dialog.
                _machineLine(machines),
                const SizedBox(height: 12),
                _SkipCheck(
                  value: _skipNextTime,
                  hovered: _skipHovered,
                  onHover: (value) => setState(() => _skipHovered = value),
                  onChanged: (value) => setState(() => _skipNextTime = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('run-local-model-not-now'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
            FilledButton(
              key: const Key('run-local-model-start'),
              onPressed: missing == null
                  ? () => Navigator.of(
                      context,
                    ).pop((machineId: _machineId, skipNextTime: _skipNextTime))
                  : null,
              child: const Text('Start'),
            ),
          ],
        );
      },
    );
  }
}

/// "Don't show this again", box and label under one tap target — the rule
/// [AppCheckbox] states for every row that carries one.
class _SkipCheck extends StatelessWidget {
  const _SkipCheck({
    required this.value,
    required this.hovered,
    required this.onHover,
    required this.onChanged,
  });

  final bool value;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        key: const Key('run-local-model-skip'),
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppCheckbox(value: value, hovered: hovered, onChanged: onChanged),
              const SizedBox(width: 10),
              Text(
                "Don't show this again",
                style: TextStyle(
                  fontFamily: grid.AppFont.sans,
                  fontSize: 13,
                  color: grid.AppPalette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "…" beside the chips: a small recessed square that opens the machine menu anchored under
/// itself. Its own widget so it has a context to measure from — the menu is positioned from the
/// button's box, exactly as the pane's picker positions from its control.
class _MoreMachines extends StatelessWidget {
  const _MoreMachines({super.key, required this.onOpen});

  final void Function(BuildContext context, RelativeRect position) onOpen;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'More machines',
    child: InkWell(
      onTap: () {
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;
        final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
        onOpen(
          context,
          RelativeRect.fromLTRB(
            origin.dx,
            origin.dy + box.size.height + 6,
            overlay.size.width - origin.dx - box.size.width,
            0,
          ),
        );
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: grid.AppSurface.recess,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          Icons.more_horiz,
          size: 18,
          color: grid.AppPalette.textSecondary,
        ),
      ),
    ),
  );
}
