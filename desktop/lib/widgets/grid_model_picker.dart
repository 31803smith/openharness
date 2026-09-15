import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

/// The pane header's model picker: what this agent could be run on, from the account's own grid.
///
/// **Only the private harness grid.** Not every grid this computer's `grid` CLI happens to be signed
/// into — the question the header is asking is "which of MY machines could answer for this agent",
/// and a catalogue of other people's grids is a different question with a different blast radius.
///
/// The list is fetched when the menu is opened rather than held in state, because it is live: an
/// engine can join or leave a grid between two openings, and an offer nobody is serving any more is
/// worse than a moment's spinner.
class GridModelPicker extends StatefulWidget {
  final AppNotifier notifier;
  final String machineId;

  /// Called with the chosen model id.
  final ValueChanged<GridModel>? onSelected;

  /// Called to put the agent back on its own vendor login. Offered FIRST and always — a picker that
  /// can only move an agent ONTO a grid is a one-way door, and the way back must not be a thing you
  /// have to know a command for.
  final VoidCallback? onUseOwnLogin;

  /// The grid model this agent is on right now, or null when it is on its own login. Drives the
  /// checkmark, so the menu answers "where am I" as well as "where could I go".
  final String? currentModel;

  /// What this engine's own login is called, for the first row's label.
  final String? engineLabel;

  const GridModelPicker({
    super.key,
    required this.notifier,
    required this.machineId,
    this.onSelected,
    this.onUseOwnLogin,
    this.currentModel,
    this.engineLabel,
  });

  @override
  State<GridModelPicker> createState() => _GridModelPickerState();
}

class _GridModelPickerState extends State<GridModelPicker> {
  bool _loading = false;

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    final GridModels answer;
    try {
      answer = await widget.notifier.gridModels(widget.machineId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;

    // Anchored to this widget, so the menu opens where the eye already is.
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height + 4,
      overlay.size.width - origin.dx - box.size.width,
      0,
    );

    // The own-login row is built the same way whether or not the grid has anything on it: an agent
    // that is ON a grid must always be able to come back, and a grid that has gone empty is exactly
    // when someone most needs that.
    final ownLogin = PopupMenuItem<_Choice>(
      value: const _Choice.ownLogin(),
      height: 34,
      child: Row(
        children: [
          _check(widget.currentModel == null),
          Flexible(
            child: Text(
              widget.engineLabel == null
                  ? 'Own login (subscription)'
                  : '${widget.engineLabel} login (subscription)',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
        ],
      ),
    );

    // An empty grid and no grid at all are different facts, and each gets its own sentence: one is
    // "nobody is serving yet", the other is "there is nothing to serve on". A single "no models"
    // would send a person looking in the wrong place.
    final chosen = await showMenu<_Choice>(
      context: context,
      position: position,
      color: AppColors.surface,
      items: [
        ownLogin,
        const PopupMenuDivider(),
        PopupMenuItem<_Choice>(
          enabled: false,
          height: 26,
          child: Text(
            answer.gridName ?? 'no grid on this account yet',
            style: TextStyle(fontSize: 10, color: AppColors.mutedStrong),
          ),
        ),
        if (answer.models.isEmpty)
          PopupMenuItem<_Choice>(
            enabled: false,
            child: Text(
              answer.gridName == null
                  ? 'Sign in again to set one up.'
                  : 'Nothing is being served yet.',
              style: TextStyle(fontSize: 11, color: AppColors.textSoft),
            ),
          ),
        for (final model in answer.models)
          PopupMenuItem<_Choice>(
            value: _Choice.model(model),
            height: 34,
            child: Row(
              children: [
                _check(widget.currentModel == model.id),
                Flexible(
                  child: Text(
                    model.id,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.text),
                  ),
                ),
                // Which of the user's machines answers it — the part that makes a private grid
                // legible, and the reason `node` is carried through at all.
                if (model.node.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    model.node,
                    style: TextStyle(fontSize: 10, color: AppColors.mutedStrong),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
    if (chosen == null) return;
    // Selecting what is already selected respawns the pane for no reason — do nothing instead.
    if (chosen.model == null) {
      if (widget.currentModel != null) widget.onUseOwnLogin?.call();
      return;
    }
    if (chosen.model!.id != widget.currentModel) widget.onSelected?.call(chosen.model!);
    return;

  }

  /// A fixed-width tick column, so every row's label starts at the same x whether or not it is the
  /// active one — a menu whose text shifts by a few pixels between rows reads as misaligned.
  Widget _check(bool on) => SizedBox(
    width: 18,
    child: on ? Icon(Icons.check, size: 13, color: AppColors.accent) : null,
  );

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Models on your private grid',
      waitDuration: const Duration(milliseconds: 700),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_loading)
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                )
              else
                Icon(Icons.memory, size: 13, color: AppColors.mutedStrong),
              const SizedBox(width: 5),
              Text(
                'Model',
                style: TextStyle(fontSize: 11, color: AppColors.textSoft),
              ),
              Icon(Icons.arrow_drop_down, size: 14, color: AppColors.mutedStrong),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row's meaning: a grid model, or the engine's own login. A sealed pair rather than a nullable
/// `GridModel`, because `null` already means "the menu was dismissed" in `showMenu`'s own result.
class _Choice {
  final GridModel? model;
  const _Choice.model(GridModel this.model);
  const _Choice.ownLogin() : model = null;
}
