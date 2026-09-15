import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../usage/models_menu_controller.dart';
import 'engine_identity.dart';

/// The pane header's model picker, in two sections: **Subscription** and **Local**.
///
/// The shape is the app's own Models menu, deliberately — that menu already answers "what could this
/// run on" for the whole window, and a second control answering the same question in a different
/// visual language would read as a different KIND of question. It carries only two of that menu's
/// sections: the engine's own login, and the models the account's private grid is serving. There is
/// no API section here because this picker cannot put an agent on one.
///
/// **Only the private harness grid.** Not every grid this computer's `grid` CLI happens to be signed
/// into — the question the header asks is "which of MY machines could answer for this agent", and a
/// catalogue of other people's grids is a different question with a different blast radius.
///
/// The list is fetched when the menu opens rather than held in state, because it is live: an engine
/// can join or leave a grid between two openings, and an offer nobody is serving any more is worse
/// than a moment's spinner.
class GridModelPicker extends StatefulWidget {
  final AppNotifier notifier;
  final String machineId;

  /// Called with the chosen grid model.
  final ValueChanged<GridModel>? onSelected;

  /// Called to put the agent back on its own vendor login. Offered FIRST and always — a picker that
  /// can only move an agent ONTO a grid is a one-way door, and the way back must not be a thing you
  /// have to know a command for.
  final VoidCallback? onUseOwnLogin;

  /// The grid model this agent is on right now, or null when it is on its own login. Drives the
  /// filled row, so the menu answers "where am I" as well as "where could I go".
  final String? currentModel;

  /// Whether the agent can search the web on [currentModel], as the daemon decided when it built
  /// the launch. Shown as a subtitle under the current Local row and in the control's tooltip —
  /// only for the two degraded values; `on` and null (nothing said) show nothing. Read only when
  /// [currentModel] is set: it is a fact about a Local-model launch, and the Subscription row has
  /// its own web tools.
  final GridWebSearch? webSearch;

  /// The agent's engine, for the subscription row's icon and label.
  final String? engineLabel;

  const GridModelPicker({
    super.key,
    required this.notifier,
    required this.machineId,
    this.onSelected,
    this.onUseOwnLogin,
    this.currentModel,
    this.webSearch,
    this.engineLabel,
  });

  @override
  State<GridModelPicker> createState() => _GridModelPickerState();
}

class _GridModelPickerState extends State<GridModelPicker> {
  bool _loading = false;
  ModelsMenuController? _usage;
  GridModels? _last;

  @override
  void initState() {
    super.initState();
    // Warm the answer as soon as the control exists, so a click lands on a memo rather than on two
    // subprocess spawns and two network round trips — measured at ~1.4s, which is a person watching
    // a header do nothing. Fire-and-forget: nothing here waits on it, and a failure just means the
    // first open pays what it used to.
    unawaited(_prefetch());
  }

  Future<void> _prefetch() async {
    // Created here, not only on the cold path: a warm open reads `_usage.rows` for the subscription
    // row's provider name and percentage, and skipping it left that row falling back to the bare
    // engine label with no status beside it.
    _usage ??= ModelsMenuController(remote: widget.notifier.readRemoteUsage);
    unawaited(_usage!.refresh().catchError((_) {}));
    final answer = await widget.notifier.gridModels(widget.machineId);
    if (mounted) _last = answer;
  }

  @override
  void dispose() {
    _usage?.dispose();
    super.dispose();
  }

  /// The sentence about web search on the current Local model, or null when there is none to
  /// show. Null off a grid whatever the daemon said: a frame can lag a move home by a beat, and
  /// the Subscription row must never wear a sentence about a launch it was no part of.
  String? get _webSearchSentence =>
      widget.currentModel == null ? null : widget.webSearch?.sentence;

  /// The subtitle under one Local row: the sentence for the CURRENT model only. The status is about
  /// this agent's launch, and the other rows are places it could go, about which nothing is known.
  String? _subtitleFor(GridModel model) =>
      widget.currentModel == model.id ? _webSearchSentence : null;

  /// The subscription reading for THIS agent's engine, or null when there is none to show.
  ///
  /// Built from the same controller the window's own Models menu uses, so the percentage here and
  /// the percentage up there cannot disagree. Its refresh is capped at once a minute and it answers
  /// from cache in between, which is why opening this menu does not cost a request.
  Map<String, Object?>? _subscriptionRow() {
    final engine = widget.engineLabel?.trim().toLowerCase();
    if (engine == null || engine.isEmpty) return null;
    for (final row in _usage?.rows ?? const <Map<String, Object?>>[]) {
      if (row['engine'] == engine) return row;
    }
    return null;
  }

  Future<void> _open() async {
    if (_loading) return;
    // A warm answer opens the menu with no wait at all. It is at most seconds old — the daemon's own
    // memo is what bounds that — and the refresh below lands in time for the next open.
    final GridModels answer;
    if (_last != null) {
      answer = _last!;
      unawaited(_prefetch());
      await _show(answer);
      return;
    }
    setState(() => _loading = true);
    try {
      _usage ??= ModelsMenuController(remote: widget.notifier.readRemoteUsage);
      // ⚠️ The usage read is NOT awaited. It is decoration — a percentage beside the subscription
      // row — while the grid list is the menu's actual content, and a menu that waits on a credential
      // read to draw a list it already has is a menu that feels broken whenever that source is slow.
      // This open uses whatever is cached; the refresh lands for the next one. `refresh()` is itself
      // capped at once a minute, so opening the menu repeatedly costs nothing.
      unawaited(_usage!.refresh().catchError((_) {}));
      answer = await widget.notifier.gridModels(widget.machineId);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _last = answer;
    if (!mounted) return;
    await _show(answer);
  }

  /// Draw the menu for an answer already in hand. Split from [_open] so a warm open shares exactly
  /// the same menu as a cold one rather than a second copy of it.
  Future<void> _show(GridModels answer) async {
    if (!mounted) return;

    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy + box.size.height + 6,
      overlay.size.width - origin.dx - box.size.width,
      0,
    );

    final subscription = _subscriptionRow();
    final chosen = await showMenu<_Choice>(
      context: context,
      position: position,
      color: AppColors.surface,
      // Wide enough that a status can sit right-aligned against a model id without the two meeting.
      // Wide enough for a full GGUF-style model id beside its node without either being cut.
      constraints: const BoxConstraints(minWidth: 340, maxWidth: 540),
      items: [
        _header('Subscription'),
        PopupMenuItem<_Choice>(
          value: const _Choice.ownLogin(),
          height: 32,
          padding: EdgeInsets.zero,
          child: _Row(
            selected: widget.currentModel == null,
            engine: widget.engineLabel,
            title: (subscription?['title'] as String?) ?? engineIdentity(widget.engineLabel).label,
            detail: (subscription?['account'] as String?) ?? '',
            // Absent rather than "unknown": a row that cannot say how much is left says nothing,
            // which reads as "no figure" instead of as a figure that happens to be missing.
            status: subscription?['status'] as String?,
          ),
        ),
        const PopupMenuDivider(),
        _header('Local'),
        // An engine with no way onto a Local model (Cursor talks only to its own API; the daemon
        // refuses the move) is told so here, instead of being offered rows whose click would do
        // nothing. The daemon names the capable engines beside the list; an older daemon names
        // none, and then every row is offered as before.
        if (!answer.canRunLocally(widget.engineLabel))
          PopupMenuItem<_Choice>(
            enabled: false,
            height: 30,
            padding: const EdgeInsets.only(left: _menuInset + _rowPadding),
            child: Text(
              '${engineIdentity(widget.engineLabel).label} can only run on its own login.',
              style: TextStyle(fontSize: 11, color: AppColors.textSoft),
            ),
          )
        // An empty grid and no grid at all are different facts, and each gets its own sentence: one
        // is "nobody is serving yet", the other "there is nothing to serve on". A single "no models"
        // would send a person looking in the wrong place.
        else if (answer.models.isEmpty)
          PopupMenuItem<_Choice>(
            enabled: false,
            height: 30,
            padding: const EdgeInsets.only(left: _menuInset + _rowPadding),
            child: Text(
              // "Local models", in the user's own vocabulary: the grid is how a Local model is
              // served, not a thing this menu asks anyone to know about.
              answer.gridName == null
                  ? 'No local models on this account yet — sign in again to set them up.'
                  : 'Nothing is being served yet.',
              style: TextStyle(fontSize: 11, color: AppColors.textSoft),
            ),
          ),
        if (answer.canRunLocally(widget.engineLabel))
          for (final model in answer.models)
            PopupMenuItem<_Choice>(
              value: _Choice.model(model),
              // Taller only for the current row carrying a sentence; every other row keeps its
              // height so the menu does not grow for a fact about one agent.
              height: _subtitleFor(model) != null ? 46 : 32,
              padding: EdgeInsets.zero,
              child: _Row(
                selected: widget.currentModel == model.id,
                title: model.id,
                // Which of the user's machines answers it — the part that makes a private grid
                // legible, and the reason `node` is carried through at all.
                status: model.node.isEmpty ? null : model.node,
                subtitle: _subtitleFor(model),
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
  }

  /// A section label. Non-interactive and short, so the two groups read as groups rather than as
  /// entries someone failed to make clickable.
  PopupMenuItem<_Choice> _header(String label) => PopupMenuItem<_Choice>(
    enabled: false,
    height: 22,
    padding: EdgeInsets.zero,
    child: Padding(
      // The row's margin plus its internal padding, so a header sits directly above the text it
      // heads rather than a few pixels to either side of it.
      padding: const EdgeInsets.only(left: _menuInset + _rowPadding),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: .3,
          color: AppColors.mutedStrong,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sentence = _webSearchSentence;
    return Tooltip(
      // The same sentence the menu shows, one line under the control's own — so a person can learn
      // the agent has no web search without opening the menu at all.
      message: sentence == null ? 'Where this agent runs' : 'Where this agent runs\n$sentence',
      waitDuration: const Duration(milliseconds: 700),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // No leading glyph: the word carries the control, and a header this dense reads better
              // with one fewer mark in it. The spinner takes that space only while a read is in
              // flight, so the label does not shift when nothing is happening.
              if (_loading) ...[
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 5),
              ],
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

/// One menu row: optional engine mark, title, a quiet detail beside it, and a right-aligned
/// status — filled when it is the current one. The same column order in both sections, so the eye
/// can run straight down the menu. A [subtitle], when there is one, sits under the title inside
/// the same fill.
class _Row extends StatelessWidget {
  final bool selected;
  final String? engine;
  final String title;
  final String detail;
  final String? status;
  final String? subtitle;

  const _Row({
    required this.selected,
    required this.title,
    this.engine,
    this.detail = '',
    this.status,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        if (engine != null) ...[
          EngineMark(engine: engine, size: 14),
          const SizedBox(width: 7),
        ],
        // ⚠️ Expanded on the TITLE, not on the status. The status is a handful of characters and
        // wants only what it needs; giving it the flexible half truncated
        // `Qwen3.6-35B-A3B-UD-Q5_K_XL` to `Qwen3.6-35B-A3B-UD-Q5_K…` while empty space sat beside
        // it. The long string here is the model id, so the model id is what gets the room.
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              // Stated rather than inherited: a PopupMenuItem's default text style is heavier than
              // this menu wants, which read as every row being emphasised.
              fontWeight: FontWeight.w400,
              color: AppColors.text,
            ),
          ),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(detail, style: TextStyle(fontSize: 11, color: AppColors.mutedStrong)),
        ],
        if (status != null) ...[
          const SizedBox(width: 14),
          Text(
            status!,
            style: TextStyle(fontSize: 11, color: AppColors.mutedStrong),
          ),
        ],
      ],
    );
    return Container(
      // The highlight is the row, so it needs the row's own inset rather than the item's padding —
      // which is why the `PopupMenuItem`s around these set `padding: EdgeInsets.zero`.
      margin: const EdgeInsets.symmetric(horizontal: _menuInset),
      padding: const EdgeInsets.symmetric(horizontal: _rowPadding, vertical: 5),
      decoration: selected
          // Subtle on purpose: one row in the menu is already the current one, and a mark loud
          // enough to announce that would compete with the thing a person opened the menu to read.
          ? BoxDecoration(
              color: AppColors.selected,
              borderRadius: BorderRadius.circular(5),
            )
          : null,
      // The subtitle sits INSIDE the fill, under the title: it is about this row, and a sentence
      // hanging below the highlight would read as belonging to the next one.
      child: subtitle == null
          ? row
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row,
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: AppColors.textSoft),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The row's own inset from the menu edge, and the padding inside its highlight. A section header
/// carries their SUM as a left inset, so header text sits exactly above the row text it heads.
const double _menuInset = 6;
const double _rowPadding = 8;

/// One row's meaning: a grid model, or the engine's own login. A sealed pair rather than a nullable
/// `GridModel`, because `null` already means "the menu was dismissed" in `showMenu`'s own result.
class _Choice {
  final GridModel? model;
  const _Choice.model(GridModel this.model);
  const _Choice.ownLogin() : model = null;
}
