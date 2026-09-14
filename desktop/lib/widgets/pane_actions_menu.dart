import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_menu.dart';

class PaneActionsMenu extends StatefulWidget {
  const PaneActionsMenu({
    super.key,
    required this.name,
    this.onSplitRight,
    this.onSplitDown,
    this.onTogglePin,
    this.onToggleComposer,
    this.onClose,
    this.pinned = false,
    this.composerVisible = false,
  });
  final String name;
  final VoidCallback? onSplitRight,
      onSplitDown,
      onTogglePin,
      onToggleComposer,
      onClose;
  final bool pinned, composerVisible;
  @override
  State<PaneActionsMenu> createState() => _PaneActionsMenuState();
}

class _PaneActionsMenuState extends State<PaneActionsMenu> {
  final _menu = MenuController();
  Widget _action(String label, IconData icon, VoidCallback callback) =>
      AppMenuItem(
        label: label,
        icon: icon,
        onPressed: () {
          _menu.close();
          callback();
        },
      );

  @override
  Widget build(BuildContext context) => MenuAnchor(
    controller: _menu,
    style: grid.AppMenu.style(minWidth: 220),
    menuChildren: [
      if (widget.onSplitRight != null)
        _action(
          'Split right',
          Icons.vertical_split_outlined,
          widget.onSplitRight!,
        ),
      if (widget.onSplitDown != null)
        _action(
          'Split down',
          Icons.horizontal_split_outlined,
          widget.onSplitDown!,
        ),
      if (widget.onSplitRight != null || widget.onSplitDown != null)
        const AppMenuDivider(),
      if (widget.onTogglePin != null)
        _action(
          widget.pinned ? 'Unpin agent' : 'Pin agent',
          Icons.push_pin_outlined,
          widget.onTogglePin!,
        ),
      if (widget.onToggleComposer != null)
        _action(
          widget.composerVisible
              ? 'Hide message composer'
              : 'Show message composer',
          Icons.edit_note,
          widget.onToggleComposer!,
        ),
      if (widget.onClose != null)
        _action('Close agent', Icons.close, widget.onClose!),
    ],
    builder: (_, menu, _) => IconButton(
      tooltip: 'Actions for ${widget.name}',
      onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      icon: const Icon(Icons.more_horiz, size: 18),
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
    ),
  );
}
