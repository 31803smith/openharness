import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_checkbox.dart';
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';

/// The one place the "Run a local model" flow is explained.
///
/// Both doors — the pane picker's last row and the window's Models menu — go
/// through [AppNotifier.runLocalModel], which opens this and creates the agent
/// on Start. The dialog itself creates nothing: it answers with what the
/// person decided, and the notifier does the rest, so the two doors cannot
/// drift into two definitions of what Start means.
///
/// Null is Not now (or Escape, or a click outside). A record is Start, with
/// whether the person asked not to see this again — persisted by the caller,
/// not here, because the store belongs to the notifier.
Future<({bool skipNextTime})?> showRunLocalModelDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
) => showAppDialog<({bool skipNextTime})>(
  context: context,
  // Lighter than the app's default veil: this is a two-second yes/no in front
  // of the swarm the person was just looking at, not a screen of its own, and
  // the 90% default read as the window going dark. The blur stays, so what is
  // behind is felt rather than read. Same weight the swarm rename uses.
  veilTint: const Color(0x99000000),
  builder: (_) =>
      _RunLocalModelDialog(notifier: notifier, machineId: machineId),
);

/// Prerequisites are said only when one is missing, as one sentence in the
/// machine line's place, with Start disabled. Present and satisfied, nothing
/// is said — a checklist of green ticks would make a two-second decision look
/// like a setup screen.
enum _Prerequisite { opencode, gridCli, grid }

class _RunLocalModelDialog extends StatefulWidget {
  const _RunLocalModelDialog({required this.notifier, required this.machineId});

  final AppNotifier notifier;
  final String machineId;

  @override
  State<_RunLocalModelDialog> createState() => _RunLocalModelDialogState();
}

class _RunLocalModelDialogState extends State<_RunLocalModelDialog> {
  /// Whether the machine has a private grid to serve on. Null until the
  /// machine answers; the sentence is only earned by an answer, the same rule
  /// New Agent keeps for a missing engine.
  bool? _hasGrid;

  /// Which `grid` the machine would run, once it answers — null until then,
  /// and null from a daemon too old to say, which claims nothing.
  GridCli? _gridCli;

  bool _skipNextTime = false;
  bool _skipHovered = false;

  @override
  void initState() {
    super.initState();
    // Two reads, fired on open and not waited for: the dialog is readable at
    // once, and a missing prerequisite appears as it is found. Deferred a frame
    // so a probe's first notifyListeners() does not land mid-build. `force` on
    // the engine probe for the reason New Agent gives — opencode arrives and
    // leaves through a terminal this app never sees, and a stored answer is
    // worth nothing here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(widget.notifier.probeEngines(widget.machineId, force: true));
      unawaited(_readGrid());
    });
  }

  Future<void> _readGrid() async {
    final models = await widget.notifier.gridModels(widget.machineId);
    if (!mounted) return;
    setState(() {
      _hasGrid = models.gridName != null;
      _gridCli = models.gridCli;
    });
  }

  /// The first missing prerequisite, or null when nothing has been found
  /// missing — which includes "not answered yet".
  _Prerequisite? get _missing {
    final machine = widget.notifier.stateOf(widget.machineId);
    if (machine != null && machine.engines.loaded) {
      final opencode = machine.engines['opencode'];
      if (opencode != null && !opencode.installed) {
        return _Prerequisite.opencode;
      }
    }
    // The machine's own gap before the account's: a sign-in cannot help until
    // there is a `grid` on this computer to sign in with.
    if (_gridCli == GridCli.missing) return _Prerequisite.gridCli;
    if (_hasGrid == false) return _Prerequisite.grid;
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
        final status = switch (missing) {
          _Prerequisite.opencode => 'Needs opencode on this machine first.',
          _Prerequisite.gridCli =>
            "Harness Compute isn't installed on this machine.",
          _Prerequisite.grid => 'Sign in to Harness again to set this up.',
          null => null,
        };
        return AlertDialog(
          title: const Text('Models that live on your machine'),
          content: SizedBox(
            width: 440,
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
                const SizedBox(height: 16),
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
                  ? () =>
                        Navigator.of(context).pop((skipNextTime: _skipNextTime))
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
