import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shortcuts/app_keymap.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'swarm_switcher.dart';

/// New swarm owns its input and caret. Only the catalog and result actions are
/// shared with the title bar; typing here never activates the native field.
class SwarmInlineSearch extends StatefulWidget {
  const SwarmInlineSearch({
    super.key,
    required this.app,
    required this.projects,
    required this.recent,
    required this.onChoose,
    this.commands,
  });

  final AppNotifier app;
  final SwarmProjectStore projects;
  final List<String> recent;
  final List<SwarmDestination> Function()? commands;
  final void Function(SwarmSearchSelection choice, String target) onChoose;

  @override
  State<SwarmInlineSearch> createState() => _SwarmInlineSearchState();
}

class _SwarmInlineSearchState extends State<SwarmInlineSearch> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'New swarm search');
  final _overlay = OverlayPortalController();
  final _tapGroup = Object();
  SwarmSearchController? _search;
  AppKeymap? _keymap;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    // New swarm gives the field its caret immediately, but the welcome
    // choices stay visible until a click, edit or result-navigation key.
    if (!_focus.hasFocus) _close();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = KeymapTheme.of(context);
    if (next == _keymap) return;
    _keymap?.removeListener(_keymapChanged);
    _keymap = next;
    _keymap?.addListener(_keymapChanged);
  }

  void _keymapChanged() => _search?.refreshCommands();

  void _begin() {
    if (_search != null) return;
    _search = SwarmSearchController(
      widget.app,
      widget.recent,
      projects: widget.projects,
      commands: widget.commands,
    )..setQuery(_text.text);
    _search!.addListener(_changed);
    _overlay.show();
    setState(() {});
  }

  void _changed() => setState(() {});

  void _close() {
    if (_search == null) return;
    _overlay.hide();
    _search!.removeListener(_changed);
    _search!.dispose();
    _search = null;
    setState(() {});
  }

  void _choose(SwarmSearchSelection choice) {
    final target = _search?.targetId;
    if (target == null) return;
    _close();
    widget.onChoose(choice, target);
  }

  @override
  void dispose() {
    _keymap?.removeListener(_keymapChanged);
    _search?.removeListener(_changed);
    _search?.dispose();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _search != null;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.vertical(
        top: const Radius.circular(8),
        bottom: Radius.circular(open ? 0 : 8),
      ),
      borderSide: BorderSide(color: open ? Colors.transparent : Colors.white24),
    );
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: (context, info) {
        final search = _search!;
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final scale = MediaQuery.textScalerOf(context);
        final available = math.max(
          0.0,
          info.overlaySize.height - anchor.bottom - 16,
        );
        final height = math.min(
          available,
          swarmSearchResultsHeight(search, scale),
        );
        return Positioned(
          top: anchor.bottom,
          left: anchor.left,
          width: anchor.width,
          height: height,
          child: TextFieldTapRegion(
            groupId: _tapGroup,
            child: ExcludeFocus(
              child: Material(
                key: const ValueKey('swarm-welcome-search-results'),
                color: grid.AppPalette.swarmSearchSurface,
                elevation: 8,
                shadowColor: Colors.black54,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SwarmSearchResults(
                    search: search,
                    onChoose: _choose,
                    onRefocus: _focus.requestFocus,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: SwarmSearchKeys(
        search: _search,
        editing: _text,
        onChoose: _choose,
        onClose: _close,
        onOpen: _begin,
        child: TextField(
          key: const ValueKey('swarm-welcome-search-input'),
          groupId: _tapGroup,
          controller: _text,
          focusNode: _focus,
          autofocus: true,
          onTap: _begin,
          onTapAlwaysCalled: true,
          onTapOutside: (_) => _close(),
          onChanged: (value) {
            _begin();
            _search!.setQuery(value);
          },
          style: const TextStyle(fontSize: 13, color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search agents, swarms, machines, projects…',
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xffc5bece)),
            prefixIcon: const Icon(
              Icons.search,
              size: 18,
              color: Color(0xffc5bece),
            ),
            filled: true,
            fillColor: open
                ? grid.AppPalette.swarmSearchSurface
                : const Color(0xa6111521),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            isDense: true,
            border: border,
            enabledBorder: border,
            focusedBorder: border,
          ),
        ),
      ),
    );
  }
}
