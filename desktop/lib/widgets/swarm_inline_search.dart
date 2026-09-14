import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../shortcuts/app_keymap.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import 'swarm_switcher.dart';
import 'swarm_search_input.dart';

/// New Harness owns its input and caret, sharing the same Add agent results and
/// actions as the floating button and splits.
class SwarmInlineSearch extends StatefulWidget {
  const SwarmInlineSearch({
    super.key,
    required this.app,
    required this.projects,
    required this.recent,
    required this.onChoose,
    this.commands,
    this.onNewAgent,
    this.catalog,
  });

  final AppNotifier app;
  final SwarmProjectStore projects;
  final List<String> recent;
  final List<SwarmDestination> Function()? commands;
  final ValueChanged<String>? onNewAgent;
  final SwarmSearchCatalog? catalog;
  final void Function(SwarmSearchSelection choice, String target) onChoose;

  @override
  State<SwarmInlineSearch> createState() => _SwarmInlineSearchState();
}

class _SwarmInlineSearchState extends State<SwarmInlineSearch> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'New Harness search');
  final _overlay = OverlayPortalController();
  final _tapGroup = Object();
  final _catalog = SwarmSearchCatalog();
  SwarmSearchController? _search;
  AppKeymap? _keymap;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    // New Harness gives the field its caret immediately, but the welcome
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
      adding: true,
      catalog: widget.catalog ?? _catalog,
    )..setQuery(_text.text);
    _search!.addListener(_changed);
    _overlay.show();
    setState(() {});
  }

  void _changed() => setState(() {});

  void _showCommands() {
    _text.value = const TextEditingValue(
      text: '> ',
      selection: TextSelection.collapsed(offset: 2),
    );
    _begin();
    _search!.setQuery('> ');
    _focus.requestFocus();
  }

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

  void _newAgent() {
    if (_search?.canCreate == false) return;
    _close();
    widget.onNewAgent?.call(_text.text);
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
                  bottom: Radius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: SwarmSearchResults(
                    search: search,
                    onChoose: _choose,
                    onRefocus: _focus.requestFocus,
                    onCommands: _showCommands,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: SwarmSearchInput(
        hintText: 'Find a harness',
        rounded: true,
        inputKey: const ValueKey('swarm-welcome-search-input'),
        controller: _text,
        focusNode: _focus,
        groupId: _tapGroup,
        search: _search,
        onChoose: _choose,
        onClose: _close,
        onOpen: _begin,
        onNewAgent: widget.onNewAgent == null ? null : _newAgent,
        onTapOutside: _close,
        onChanged: (value) {
          _begin();
          _search!.setQuery(value);
        },
      ),
    );
  }
}
