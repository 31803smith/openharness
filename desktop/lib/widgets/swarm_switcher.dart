import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'engine_identity.dart';
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
              if (search.scoped)
                const SingleActivator(
                  LogicalKeyboardKey.arrowLeft,
                  alt: true,
                ): () =>
                    run(search.back),
            },
      child: child,
    );
  }
}

/// Results only: global search keeps its one editable input in the title bar.
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
    _rowHeight = (scale.scale(13) + scale.scale(11) + 32).clamp(
      56,
      double.infinity,
    );
    final scope = search.scope;
    final selected = search.selected;
    return Semantics(
      container: true,
      label: 'Search results',
      child: Column(
        children: [
          if (search.scoped)
            Row(
              children: [
                IconButton(
                  tooltip: 'All results',
                  onPressed: () {
                    search.back();
                    widget.onRefocus();
                  },
                  icon: const Icon(Icons.arrow_back, size: 16),
                ),
                Expanded(
                  child: Text(
                    scope?.title ?? 'Group no longer available',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: !search.canOpenGroup
                      ? null
                      : () => widget.onChoose(
                          SwarmSearchSelection(
                            scope!,
                            SwarmSearchAction.openGroup,
                          ),
                        ),
                  child: Text(
                    'Open ${scope?.members.length ?? 0} agents as swarm',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          Expanded(
            child: search.rows.isEmpty
                ? Center(
                    child: Text(
                      search.scoped && search.query.isEmpty
                          ? 'No available agents in this group'
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
                        selected: index == search.cursor,
                        selectedColor: Colors.white,
                        selectedTileColor: Colors.white10,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        leading: row.agentId != null
                            ? EngineMark(engine: row.engine, size: 20)
                            : Icon(
                                row.isMachine
                                    ? Icons.computer_outlined
                                    : row.isProject
                                    ? Icons.folder_outlined
                                    : Icons.tab,
                                size: 19,
                                color: Colors.white60,
                              ),
                        title: Text(
                          row.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          row.detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                        trailing: Text(
                          row.current
                              ? 'Current'
                              : SwarmSearchController.action(row),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                        onTap: () => _submit(row),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    selected?.agentId != null && !selected!.hasView
                        ? 'Open agent in ${search.targetName}'
                        : '↑↓ choose · Esc close',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
              ),
              if (search.canAdd(selected))
                TextButton(
                  onPressed: () => widget.onChoose(search.addHere()!),
                  child: const Text(
                    'Add to this swarm  ⌘↵',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              TextButton(
                onPressed: selected == null ? null : _submit,
                child: Text(
                  '${selected == null ? 'Open' : SwarmSearchController.action(selected)}  ↵',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
