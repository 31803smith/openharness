import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'engine_identity.dart';
import 'search_result_text.dart';
import 'swarm_icon.dart';
import 'swarm_switcher.dart';

/// A directory of existing places. Unlike Add agent, navigation has no output
/// preview or creation form: each group names the exact destination swarm.
class SwarmNavigator extends StatefulWidget {
  const SwarmNavigator({
    super.key,
    required this.search,
    required this.editing,
    required this.focusNode,
    required this.onChoose,
    required this.onClose,
    required this.onAdd,
    required this.onNewAgent,
  });

  final SwarmSearchController search;
  final TextEditingController editing;
  final FocusNode focusNode;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onClose, onAdd, onNewAgent;

  @override
  State<SwarmNavigator> createState() => _SwarmNavigatorState();
}

class _SwarmNavigatorState extends State<SwarmNavigator> {
  final _scroll = ScrollController();
  final _offsets = <double>[];
  double _rowHeight = 60;
  bool _scheduled = false;
  SwarmSearchController get search => widget.search;

  @override
  void initState() {
    super.initState();
    search.addListener(_changed);
  }

  void _changed() {
    setState(() {});
    _measure();
    _reveal();
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _reveal();
    });
  }

  void _measure() {
    _offsets.clear();
    var offset = 8.0;
    for (var i = 0; i < search.rows.length; i++) {
      _offsets.add(offset);
      offset += _rowHeight;
    }
    _offsets.add(offset);
  }

  void _reveal() {
    if (!_scroll.hasClients ||
        search.rows.isEmpty ||
        _offsets.length <= search.cursor + 1) {
      return;
    }
    final top = _offsets[search.cursor];
    final bottom = _offsets[search.cursor + 1];
    final position = _scroll.position;
    final next = top < position.pixels
        ? top
        : bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : position.pixels;
    final target = next.clamp(0.0, position.maxScrollExtent);
    if (position.pixels != target) _scroll.jumpTo(target);
  }

  void _choose(SwarmDestination row) {
    final selection = search.submit(row);
    if (selection != null) widget.onChoose(selection);
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
    _rowHeight = 28 + scale.scale(14) + scale.scale(12);
    _measure();
    final terms = swarmQueryTerms(search.query);
    return Column(
      key: const ValueKey('swarm-navigator'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 12, 8),
          child: Row(
            children: [
              Icon(
                search.isCommandMode ? Icons.terminal : Icons.explore_outlined,
                color: grid.AppPalette.swarmAccent,
                size: 21,
              ),
              const SizedBox(width: 10),
              Text(
                search.isCommandMode ? 'Commands' : 'Navigate',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: widget.onClose,
                style: TextButton.styleFrom(foregroundColor: Colors.white60),
                child: const Text('esc', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: SwarmSearchKeys(
            search: search,
            editing: widget.editing,
            onChoose: widget.onChoose,
            onClose: widget.onClose,
            onNewAgent: widget.onNewAgent,
            child: TextField(
              key: const ValueKey('swarm-search-input'),
              controller: widget.editing,
              focusNode: widget.focusNode,
              autofocus: true,
              onChanged: search.setQuery,
              style: const TextStyle(fontSize: 16, color: Colors.white),
              cursorColor: grid.AppPalette.swarmAccent,
              decoration: InputDecoration(
                hintText: search.hint,
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 16),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 19,
                  color: Colors.white54,
                ),
                filled: true,
                fillColor: Colors.black.withValues(alpha: .15),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: grid.AppPalette.swarmAccent.withValues(alpha: .6),
                  ),
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: search.isCommandMode
              ? SwarmSearchResults(
                  search: search,
                  onChoose: widget.onChoose,
                  onRefocus: widget.focusNode.requestFocus,
                )
              : search.rows.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No matching open agents or swarms.\nAdd an agent to bring more work into this swarm.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('swarm-navigation-locations'),
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: search.rows.length,
                  itemExtent: _rowHeight,
                  itemBuilder: (context, i) {
                    final row = search.rows[i];
                    final matches = searchResultMatches(row, terms);
                    return SizedBox(
                      height: _rowHeight,
                      child: ListTile(
                        key: ValueKey(row.id),
                        contentPadding: EdgeInsets.only(
                          left: row.agentId == null ? 14 : 42,
                          right: 14,
                        ),
                        minTileHeight: _rowHeight,
                        selected: search.cursor == i,
                        selectedColor: Colors.white,
                        selectedTileColor: grid.AppPalette.swarmAccent
                            .withValues(alpha: .12),
                        hoverColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        leading: row.agentId == null
                            ? const SwarmIcon(size: 21, color: Colors.white60)
                            : EngineMark(engine: row.engine, size: 22),
                        title: SearchResultText(
                          row.title,
                          matches: matches.where((m) => m.title),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: row.agentId == null
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: SearchResultText(
                          row.detail,
                          matches: matches.where((m) => !m.title),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                        trailing: row.agentId == null && row.current
                            ? const Text(
                                'Current swarm',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white54,
                                ),
                              )
                            : row.current
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white38,
                              )
                            : search.cursor == i
                            ? const Icon(
                                Icons.keyboard_return,
                                size: 17,
                                color: Colors.white60,
                              )
                            : null,
                        onTap: () => _choose(row),
                      ),
                    );
                  },
                ),
        ),
        if (!search.isCommandMode) ...[
          const Divider(height: 1, color: Colors.white12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: widget.onAdd,
                  key: const ValueKey('navigation-add-agent'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white70),
                  child: const Text(
                    'Add an agent…',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: search.selected == null
                      ? null
                      : () => _choose(search.selected!),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: const SwarmSearchActionLabel('Go to'),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
