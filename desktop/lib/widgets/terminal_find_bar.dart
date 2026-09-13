import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../terminal/terminal_search.dart';

class TerminalFindBar extends StatefulWidget {
  const TerminalFindBar({
    super.key,
    required this.search,
    required this.onQuery,
    required this.onStep,
    required this.onClose,
    required this.onFocus,
    this.readOnly = false,
  });
  final TerminalSearch search;
  final void Function(String query, bool caseSensitive) onQuery;
  final ValueChanged<int> onStep;
  final VoidCallback onClose;
  final VoidCallback onFocus;
  final bool readOnly;

  @override
  State<TerminalFindBar> createState() => TerminalFindBarState();
}

class TerminalFindBarState extends State<TerminalFindBar> {
  final _focus = FocusNode(debugLabel: 'Find in terminal');
  late final _text = TextEditingController(text: widget.search.query);

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusSearch();
    });
  }

  void _onFocus() {
    if (_focus.hasFocus) widget.onFocus();
  }

  void focusSearch({bool selectAll = true}) {
    _focus.requestFocus();
    if (selectAll) {
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      const SingleActivator(LogicalKeyboardKey.enter): () => widget.onStep(1),
      const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
          widget.onStep(-1),
      const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
          widget.onStep(1),
      const SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true): () =>
          widget.onStep(-1),
    },
    child: Material(
      color: const Color(0xff272727),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 4, top: 2, bottom: 2),
        child: ListenableBuilder(
          listenable: widget.search,
          builder: (context, _) {
            final search = widget.search;
            final status = search.query.isEmpty
                ? ''
                : search.searching && !search.hasSnapshot
                ? '…'
                : '${search.selected + 1}/${search.count}';
            Widget button(
              String label,
              Widget icon,
              VoidCallback? action, {
              bool selected = false,
            }) => SizedBox(
              width: 28,
              height: 30,
              child: IconButton(
                tooltip: label,
                onPressed: action,
                isSelected: selected,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 30,
                ),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                iconSize: 17,
                color: selected ? Colors.white : Colors.white60,
                icon: icon,
              ),
            );
            return Row(
              children: [
                if (widget.readOnly) ...[
                  const Tooltip(
                    message: 'This terminal is read only',
                    child: Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    autofocus: true,
                    textAlignVertical: TextAlignVertical.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1,
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Find in terminal…',
                      hintStyle: TextStyle(color: Colors.white54),
                      isDense: true,
                      isCollapsed: true,
                      constraints: BoxConstraints(),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) =>
                        widget.onQuery(value, search.caseSensitive),
                  ),
                ),
                const SizedBox(width: 6),
                Semantics(
                  liveRegion: true,
                  label: search.searching && !search.hasSnapshot
                      ? 'Searching terminal'
                      : search.query.isEmpty
                      ? 'Find in terminal'
                      : search.count == 0
                      ? 'No matches'
                      : 'Match ${search.selected + 1} of ${search.count}',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 56),
                    child: ExcludeSemantics(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1,
                          color:
                              search.count == 0 &&
                                  search.query.isNotEmpty &&
                                  !search.searching
                              ? const Color(0xffffb4a9)
                              : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                button(
                  'Match case',
                  Text(
                    'Aa',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1,
                      color: search.caseSensitive
                          ? Colors.white
                          : Colors.white54,
                      fontWeight: search.caseSensitive
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                  () {
                    widget.onQuery(_text.text, !search.caseSensitive);
                    _focus.requestFocus();
                  },
                  selected: search.caseSensitive,
                ),
                button(
                  'Previous match (⇧⌘G)',
                  const Icon(Icons.keyboard_arrow_up),
                  search.count > 0
                      ? () {
                          widget.onStep(-1);
                          _focus.requestFocus();
                        }
                      : null,
                ),
                button(
                  'Next match (⌘G)',
                  const Icon(Icons.keyboard_arrow_down),
                  search.count > 0
                      ? () {
                          widget.onStep(1);
                          _focus.requestFocus();
                        }
                      : null,
                ),
                button(
                  'Close find (Esc)',
                  const Icon(Icons.close),
                  widget.onClose,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
