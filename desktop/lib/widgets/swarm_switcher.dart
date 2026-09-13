import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'engine_identity.dart';
import 'swarm_icon.dart';
import 'swarm_welcome.dart';

Future<SwarmSearchSelection?> showSwarmHistory(
  BuildContext context,
  AppNotifier app,
  SwarmNavigationHistory history,
) async {
  final search = SwarmSearchController(app, history.recent, history: history);
  try {
    return await showAppDialog<SwarmSearchSelection>(
      context: context,
      transitionDuration: Duration.zero,
      veilBlur: 0,
      veilTint: const Color(0x66000000),
      builder: (_) => _SwarmHistory(search: search),
    );
  } finally {
    search.dispose();
  }
}

class _SwarmHistory extends StatefulWidget {
  const _SwarmHistory({required this.search});
  final SwarmSearchController search;
  @override
  State<_SwarmHistory> createState() => _SwarmHistoryState();
}

class _SwarmHistoryState extends State<_SwarmHistory> {
  final _query = TextEditingController();
  final _focus = FocusNode(debugLabel: 'History search');
  void _choose(SwarmSearchSelection choice) => Navigator.pop(context, choice);
  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    alignment: const Alignment(0, -0.5),
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
    child: SizedBox(
      width: 680,
      height: 480,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Row(
              children: [
                Text(
                  'History',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                ),
                Spacer(),
                Text(
                  'This session',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwarmSearchKeys(
              search: widget.search,
              editing: _query,
              onChoose: _choose,
              onClose: () => Navigator.pop(context),
              child: SwarmSearchField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                hintText: 'Search history…',
                onChanged: widget.search.setQuery,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SwarmSearchResults(
                search: widget.search,
                onChoose: _choose,
                onRefocus: _focus.requestFocus,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The Flutter field and History use the same keys. The native field sends
/// these commands to the same controller after AppKit has handled composition.
class SwarmSearchKeys extends StatelessWidget {
  const SwarmSearchKeys({
    super.key,
    required this.search,
    required this.editing,
    required this.onChoose,
    required this.onClose,
    required this.child,
  });
  final SwarmSearchController? search;
  final TextEditingController editing;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final search = this.search;
    bool composing() =>
        editing.value.composing.isValid && !editing.value.composing.isCollapsed;
    void run(VoidCallback action) {
      if (!composing()) action();
    }

    void choose(bool add) => run(() {
      final choice = add ? search?.addHere() : search?.submit();
      if (choice != null) onChoose(choice);
    });
    return CallbackShortcuts(
      bindings: search == null
          ? {}
          : {
              const SingleActivator(
                LogicalKeyboardKey.enter,
                includeRepeats: false,
              ): () =>
                  choose(false),
              const SingleActivator(
                LogicalKeyboardKey.numpadEnter,
                includeRepeats: false,
              ): () =>
                  choose(false),
              const SingleActivator(
                LogicalKeyboardKey.enter,
                meta: true,
                includeRepeats: false,
              ): () =>
                  choose(true),
              const SingleActivator(
                LogicalKeyboardKey.numpadEnter,
                meta: true,
                includeRepeats: false,
              ): () =>
                  choose(true),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  run(() => search.move(1)),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  run(() => search.move(-1)),
              const SingleActivator(
                LogicalKeyboardKey.keyI,
                meta: true,
                includeRepeats: false,
              ): () =>
                  run(search.togglePreview),
              const SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
              ): () =>
                  run(() => search.move(1)),
              const SingleActivator(
                LogicalKeyboardKey.keyP,
                control: true,
              ): () =>
                  run(() => search.move(-1)),
              const SingleActivator(
                LogicalKeyboardKey.keyJ,
                control: true,
              ): () =>
                  run(() => search.move(1)),
              const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () =>
                  run(() => search.move(-1)),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  run(onClose),
              const SingleActivator(
                LogicalKeyboardKey.keyG,
                control: true,
              ): () =>
                  run(onClose),
            },
      child: child,
    );
  }
}

double swarmSearchRowHeight(TextScaler scale, {required bool commands}) =>
    commands
    ? (scale.scale(13) + 20).clamp(40, double.infinity)
    : (scale.scale(13) + scale.scale(11) + 32).clamp(56, double.infinity);

double swarmSearchResultsHeight(
  SwarmSearchController search,
  TextScaler scale,
) =>
    search.rows.length.clamp(1, search.previewVisible ? 4 : 7) *
        swarmSearchRowHeight(scale, commands: search.isCommandMode) +
    64 +
    (search.previewVisible ? scale.scale(11) * 10 + 24 : 0);

/// Shared results for the title bar, New swarm field and History.
class SwarmSearchResults extends StatefulWidget {
  const SwarmSearchResults({
    super.key,
    required this.search,
    required this.onChoose,
    required this.onRefocus,
  });
  final SwarmSearchController search;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onRefocus;
  @override
  State<SwarmSearchResults> createState() => _SwarmSearchResultsState();
}

class _SwarmSearchResultsState extends State<SwarmSearchResults> {
  final _scroll = ScrollController();
  double _rowHeight = 56;
  bool _revealScheduled = false;
  SwarmSearchController get search => widget.search;
  @override
  void initState() {
    super.initState();
    search.addListener(_changed);
  }

  void _changed() {
    setState(() {});
    _scrollToSelection();
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (mounted) _scrollToSelection();
    });
  }

  void _scrollToSelection() {
    if (!_scroll.hasClients || search.rows.isEmpty) return;
    final top = search.cursor * _rowHeight;
    final bottom = top + _rowHeight;
    final position = _scroll.position;
    final offset = top < position.pixels
        ? top
        : bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : position.pixels;
    final target = offset.clamp(0.0, position.maxScrollExtent);
    if (target != position.pixels) _scroll.jumpTo(target);
  }

  void _submit([SwarmDestination? row]) {
    final choice = search.submit(row);
    if (choice != null) {
      widget.onChoose(choice);
    } else {
      widget.onRefocus();
    }
  }

  @override
  void dispose() {
    search.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    _rowHeight = swarmSearchRowHeight(scale, commands: search.isCommandMode);
    final selected = search.selected;
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewHeight = (constraints.maxHeight - _rowHeight - 48).clamp(
          0.0,
          scale.scale(11) * 10 + 24,
        );
        return Semantics(
          container: true,
          label: 'Search results',
          child: Column(
            children: [
              Expanded(
                child: search.rows.isEmpty
                    ? Center(
                        child: Text(
                          search.isCommandMode
                              ? 'No matching commands'
                              : 'No matching results',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.white60,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: search.rows.length,
                        itemExtent: _rowHeight,
                        itemBuilder: (context, index) {
                          final row = search.rows[index];
                          return ListTile(
                            key: ValueKey(row.id),
                            minTileHeight: _rowHeight,
                            enabled: search.canSubmit(row),
                            selected: index == search.cursor,
                            selectedColor: Colors.white,
                            selectedTileColor: Colors.white10,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            leading: row.isCommand
                                ? const Icon(
                                    Icons.keyboard_command_key,
                                    size: 19,
                                    color: Colors.white60,
                                  )
                                : row.agentId != null
                                ? EngineMark(
                                    engine: row.engine,
                                    size: 20,
                                    enabled: search.canSubmit(row),
                                  )
                                : row.isSwarm
                                ? const SwarmIcon(color: Colors.white60)
                                : Icon(
                                    row.isMachine
                                        ? Icons.computer_outlined
                                        : Icons.folder_outlined,
                                    size: 19,
                                    color: Colors.white60,
                                  ),
                            title: Text(
                              row.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: row.isCommand
                                ? null
                                : Text(
                                    row.detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                            trailing: row.shortcut == null
                                ? null
                                : Text(
                                    row.shortcut!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                    ),
                                  ),
                            onTap: search.canSubmit(row)
                                ? () => _submit(row)
                                : null,
                          );
                        },
                      ),
              ),
              if (search.previewVisible && previewHeight >= 64)
                SizedBox(
                  height: previewHeight,
                  child: _OutputPreview(text: search.preview?.text ?? ''),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        selected != null && !search.canSubmit(selected)
                            ? selected.isGroup &&
                                      selected.members.length >
                                          AppNotifier.maxPanes
                                  ? 'A swarm supports up to ${AppNotifier.maxPanes} agents'
                                  : 'No room to open this ${selected.isSwarm || selected.isGroup ? 'swarm' : 'agent'}'
                            : selected?.closedId != null
                            ? search.canSubmit(selected)
                                  ? 'Reopen ${selected!.isSwarm ? 'swarm' : 'agent'}'
                                  : 'No room to reopen'
                            : selected?.agentId != null && !selected!.hasView
                            ? 'Opens in ${search.targetName}'
                            : search.query.isEmpty && search.commands != null
                            ? 'Type > for commands'
                            : '↑↓ choose · Esc close',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                  if (search.canPreview ||
                      search.previewEnabled && !search.isCommandMode)
                    Tooltip(
                      message: search.previewEnabled
                          ? 'Hide preview (⌘I)'
                          : 'Preview recent output (⌘I)',
                      child: IconButton(
                        key: const ValueKey('swarm-search-preview-toggle'),
                        onPressed: () {
                          search.togglePreview();
                          widget.onRefocus();
                        },
                        icon: Icon(
                          search.previewEnabled
                              ? Icons.visibility
                              : Icons.visibility_outlined,
                          size: 18,
                          color: search.previewEnabled
                              ? Colors.white
                              : Colors.white70,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  if (search.canAdd(selected))
                    TextButton(
                      onPressed: () => widget.onChoose(search.addHere()!),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: const _SearchActionLabel(
                        'Add to this swarm',
                        command: true,
                      ),
                    ),
                  TextButton(
                    onPressed: search.canSubmit(selected) ? _submit : null,
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: _SearchActionLabel(
                      selected == null
                          ? 'Go to'
                          : SwarmSearchController.action(selected),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchActionLabel extends StatelessWidget {
  const _SearchActionLabel(this.label, {this.command = false});
  final String label;
  final bool command;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 11)),
      const SizedBox(width: 8),
      if (command) const Text('⌘', style: TextStyle(fontSize: 11)),
      const Icon(Icons.keyboard_return, size: 14),
    ],
  );
}

class _OutputPreview extends StatelessWidget {
  const _OutputPreview({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('swarm-search-preview'),
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Tooltip(
          message: 'A snapshot of available output. Turn preview off and on to refresh.',
          child: Text(
            'Output preview',
            style: TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ),
        const SizedBox(height: 6),
        Flexible(
          child: SingleChildScrollView(
            primary: false,
            reverse: true,
            child: Text(
              text.isEmpty ? 'No output available for preview.' : text,
              style: TextStyle(
                fontFamily: text.isEmpty
                    ? grid.AppFont.sans
                    : grid.AppFont.mono,
                fontFamilyFallback: text.isEmpty
                    ? grid.AppFont.sansFallback
                    : grid.AppFont.monoFallback,
                fontSize: 11,
                height: 1.45,
                color: text.isEmpty ? Colors.white70 : Colors.white,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
