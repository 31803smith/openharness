import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shortcuts/app_keymap.dart';
import '../shortcuts/keymap.dart';
import 'search_result_text.dart';

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

/// Centered search, inline search and History share editing and navigation keys.
class SwarmSearchKeys extends StatelessWidget {
  const SwarmSearchKeys({
    super.key,
    required this.search,
    required this.editing,
    required this.onChoose,
    required this.onClose,
    this.onOpen,
    required this.child,
  });
  final SwarmSearchController? search;
  final TextEditingController editing;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onClose;

  /// A focused field may be ready for typing while its suggestions are closed.
  /// The first navigation/accept key reveals them without choosing unseen work.
  final VoidCallback? onOpen;
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
      if (search == null) {
        onOpen?.call();
        return;
      }
      final choice = add ? search.addHere() : search.submit();
      if (choice != null) onChoose(choice);
    });
    void move(int delta) => run(() {
      if (search == null) {
        onOpen?.call();
      } else {
        search.move(delta);
      }
    });
    if (KeymapTheme.of(context) != null) {
      return KeymapRegion(
        contextKind: KeymapContext.picker,
        composing: composing,
        actions: {
          if (search != null || onOpen != null) ...{
            'picker.accept': () => choose(false),
            'picker.add_here': () => choose(true),
            'picker.next': () => move(1),
            'picker.previous': () => move(-1),
            if (search != null) 'picker.preview': search.togglePreview,
            'picker.cancel': onClose,
            if (search?.history == null)
              'navigation.commands': () {
                editing.value = const TextEditingValue(
                  text: '> ',
                  selection: TextSelection.collapsed(offset: 2),
                );
                if (search == null) {
                  onOpen?.call();
                } else {
                  search.setQuery('> ');
                }
              },
          },
        },
        child: child,
      );
    }
    return CallbackShortcuts(
      bindings: search == null && onOpen == null
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
                  move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => move(-1),
              if (search != null)
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
                  move(1),
              const SingleActivator(
                LogicalKeyboardKey.keyP,
                control: true,
              ): () =>
                  move(-1),
              const SingleActivator(
                LogicalKeyboardKey.keyJ,
                control: true,
              ): () =>
                  move(1),
              const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () =>
                  move(-1),
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
    ? (scale.scale(14) + 20).clamp(40, double.infinity)
    : (scale.scale(14) + scale.scale(12) + 30).clamp(56, double.infinity);

double swarmSearchResultsHeight(
  SwarmSearchController search,
  TextScaler scale,
) =>
    search.rows.length.clamp(4, 7) *
        swarmSearchRowHeight(scale, commands: search.isCommandMode) +
    52;

/// Shared results for the title bar, New swarm field and History.
class SwarmSearchResults extends StatefulWidget {
  const SwarmSearchResults({
    super.key,
    required this.search,
    required this.onChoose,
    required this.onRefocus,
    this.onCommands,
  });
  final SwarmSearchController search;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onRefocus;
  final VoidCallback? onCommands;
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
    final top = 8 + search.cursor * _rowHeight;
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
    final terms = swarmQueryTerms(
      search.isCommandMode
          ? search.query.trimLeft().substring(1)
          : search.query,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final showPreview =
            search.previewVisible && constraints.maxWidth >= 600;
        return Semantics(
          container: true,
          label: 'Search results',
          child: Column(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: search.rows.isEmpty
                          ? Center(
                              child: Text(
                                search.isCommandMode
                                    ? 'No matching commands'
                                    : 'No matching results',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white60,
                                ),
                              ),
                            )
                          : ListView.builder(
                              key: const ValueKey('swarm-search-result-list'),
                              padding: const EdgeInsets.all(8),
                              controller: _scroll,
                              itemCount: search.rows.length,
                              itemExtent: _rowHeight,
                              itemBuilder: (context, index) {
                                final row = search.rows[index];
                                final matches = searchResultMatches(row, terms);
                                return ListTile(
                                  key: ValueKey(row.id),
                                  minTileHeight: _rowHeight,
                                  enabled: search.canSubmit(row),
                                  selected: index == search.cursor,
                                  selectedColor: Colors.white,
                                  selectedTileColor: Colors.white.withValues(
                                    alpha: .075,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  leading: row.isCommand
                                      ? const Icon(
                                          Icons.keyboard_command_key,
                                          size: 20,
                                          color: Colors.white60,
                                        )
                                      : row.agentId != null
                                      ? EngineMark(
                                          engine: row.engine,
                                          size: 22,
                                          enabled: search.canSubmit(row),
                                        )
                                      : const SwarmIcon(
                                          size: 22,
                                          color: Colors.white60,
                                        ),
                                  title: SearchResultText(
                                    row.title,
                                    matches: matches.where(
                                      (match) => match.title,
                                    ),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: row.isCommand
                                      ? null
                                      : SearchResultText(
                                          row.detail,
                                          matches: matches.where(
                                            (match) => !match.title,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white60,
                                          ),
                                        ),
                                  trailing: row.shortcut == null
                                      ? null
                                      : Text(
                                          row.shortcut!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white60,
                                          ),
                                        ),
                                  onTap: search.canSubmit(row)
                                      ? () => _submit(row)
                                      : null,
                                );
                              },
                            ),
                    ),
                    if (showPreview) ...[
                      const VerticalDivider(width: 1, color: Colors.white12),
                      Expanded(
                        flex: 4,
                        child: _OutputPreview(
                          row: selected!,
                          text: search.preview?.text ?? '',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      if (widget.onCommands != null)
                        TextButton(
                          key: const ValueKey('swarm-search-commands'),
                          onPressed: widget.onCommands,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: const Text(
                            '> Commands',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      if (selected != null && !search.canSubmit(selected))
                        Expanded(
                          child: Text(
                            selected.isGroup &&
                                    selected.members.length >
                                        AppNotifier.maxPanes
                                ? 'A swarm supports up to ${AppNotifier.maxPanes} agents'
                                : 'No room to open this ${selected.isSwarm || selected.isGroup ? 'swarm' : 'agent'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (constraints.maxWidth >= 600 &&
                          (search.canPreview ||
                              search.previewEnabled && !search.isCommandMode))
                        IconButton(
                          key: const ValueKey('swarm-search-preview-toggle'),
                          tooltip: [
                            search.previewEnabled
                                ? 'Hide preview'
                                : 'Show preview',
                            if (effectiveCommandHint(
                                  context,
                                  'picker.preview',
                                  contextKind: KeymapContext.picker,
                                )
                                case final hint?)
                              '($hint)',
                          ].join(' '),
                          onPressed: () {
                            search.togglePreview();
                            widget.onRefocus();
                          },
                          icon: Icon(
                            search.previewEnabled
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: Colors.white60,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (search.canAdd(selected))
                        TextButton(
                          onPressed: () => widget.onChoose(search.addHere()!),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                          ),
                          child: const _SearchActionLabel(
                            'Add to this swarm',
                            command: 'picker.add_here',
                          ),
                        ),
                      TextButton(
                        onPressed: search.canSubmit(selected) ? _submit : null,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: _SearchActionLabel(
                          selected == null
                              ? 'Go to'
                              : SwarmSearchController.action(selected),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchActionLabel extends StatelessWidget {
  const _SearchActionLabel(this.label, {this.command = 'picker.accept'});
  final String label;
  final String command;

  @override
  Widget build(BuildContext context) {
    final hint = effectiveCommandHint(
      context,
      command,
      contextKind: KeymapContext.picker,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        if (hint != null) ...[
          const SizedBox(width: 8),
          if (RegExp(r'^[⌃⌥⇧⌘]*↵$').hasMatch(hint)) ...[
            if (hint.length > 1)
              Text(
                hint.substring(0, hint.length - 1),
                style: const TextStyle(fontSize: 11),
              ),
            const Icon(Icons.keyboard_return, size: 14),
          ] else
            Tooltip(
              message: hint,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  hint.replaceAll('↵', 'Return').replaceAll('⇥', 'Tab'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _OutputPreview extends StatelessWidget {
  const _OutputPreview({required this.row, required this.text});
  final SwarmDestination row;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('swarm-search-preview'),
    color: Colors.black.withValues(alpha: 0.10),
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.agentId == null ? 'SWARM PREVIEW' : 'AGENT PREVIEW',
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 1.3,
            color: Colors.white54,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            if (row.agentId == null)
              const SwarmIcon(size: 20, color: Colors.white70)
            else
              EngineMark(engine: row.engine, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                row.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          row.detail,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: SingleChildScrollView(
            primary: false,
            child: Text(
              row.agentId == null
                  ? 'Work with the agents in this swarm side by side.'
                  : text.isEmpty
                  ? 'No recent output available.'
                  : text,
              style: TextStyle(
                fontFamily: text.isEmpty
                    ? grid.AppFont.sans
                    : grid.AppFont.mono,
                fontFamilyFallback: text.isEmpty
                    ? grid.AppFont.sansFallback
                    : grid.AppFont.monoFallback,
                fontSize: 12,
                height: 1.65,
                color: text.isEmpty
                    ? Colors.white60
                    : Colors.white.withValues(alpha: .85),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
