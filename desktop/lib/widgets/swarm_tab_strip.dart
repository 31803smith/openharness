import 'package:flutter/material.dart';

import '../shared/layouts/window_size.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shortcuts/app_keymap.dart';
import '../shortcuts/app_shortcuts.dart';
import '../state/app_state.dart';

/// What the overflow menu can run when the strip is too narrow to show the
/// actions as buttons.
enum _StripAction { newSwarm, navigate, settings }

/// The swarm tabs, and the shell's global actions beside them.
///
/// Split out of `screens/swarm_screen.dart` because it is the one piece of
/// shell chrome that has to answer for its own width. The grid below it already
/// measures the window — `_SwarmGeometry` reads the viewport and `auto` picks
/// its column count from it (`widgets/pane_grid.dart`) — while this strip was
/// drawn at one fixed size: every tab 186pt whether four or twenty-four were
/// open, and four icon buttons holding ~176pt of the row no matter how little
/// was left. Below roughly 700pt that left the tabs a sliver to scroll inside.
///
/// Two things move with the width, and nothing else does:
///
///  * A tab shrinks, from [maxTabWidth] down to [minTabWidth], before the strip
///    starts scrolling. A window with room for full-width tabs is laid out
///    exactly as it was, so nothing changes on the size this was drawn for.
///  * At [WindowSizeClass.compact] the actions that are only shortcuts for
///    something reachable elsewhere fold into one overflow button.
///    Notifications stays out, because its badge is the only part of this strip
///    that carries state the user cannot see anywhere else.
class SwarmTabStrip extends StatelessWidget {
  const SwarmTabStrip({
    super.key,
    required this.notifier,
    required this.attention,
    required this.onRename,
    required this.onNavigate,
    required this.onNotifications,
    required this.onSettings,
  });

  /// Unchanged by width — only what sits in the strip moves, never its height.
  static const double height = 44;

  /// What a tab is drawn at when the row has room for it.
  static const double maxTabWidth = 186;

  /// Past this a tab has no room left for a name, so the strip scrolls rather
  /// than shrinking into a row of identical stubs.
  static const double minTabWidth = 112;

  final AppNotifier notifier;
  final int attention;
  final ValueChanged<String> onRename;
  final VoidCallback onNavigate;
  final VoidCallback onNotifications;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    color: grid.AppPalette.swarmTabBar,
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          const SizedBox(width: 10),
          // The tabs measure what is left AFTER the actions have taken theirs,
          // which is why this is an inner LayoutBuilder and not the outer one.
          Expanded(child: _tabs()),
          ..._actions(context, WindowSizeClass.fromWidth(constraints.maxWidth)),
          const SizedBox(width: 6),
        ],
      ),
    ),
  );

  Widget _tabs() => LayoutBuilder(
    builder: (context, constraints) {
      final count = notifier.swarms.length;
      final width = count == 0
          ? maxTabWidth
          : (constraints.maxWidth / count)
                .clamp(minTabWidth, maxTabWidth)
                .toDouble();
      return ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        buildDefaultDragHandles: false,
        itemCount: count,
        onReorderItem: (old, to) =>
            notifier.reorderSwarm(notifier.swarms[old].id, to),
        itemBuilder: (context, index) => _tab(index, width),
      );
    },
  );

  Widget _tab(int index, double width) {
    final swarm = notifier.swarms[index];
    final active = notifier.activeSwarmId == swarm.id;
    return ReorderableDragStartListener(
      key: ValueKey(swarm.id),
      index: index,
      child: GestureDetector(
        onDoubleTap: () => onRename(swarm.id),
        child: Container(
          width: width,
          margin: const EdgeInsets.only(top: 6, right: 2),
          decoration: BoxDecoration(
            color: active ? grid.AppPalette.swarmField : Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => notifier.selectSwarm(swarm.id),
                  style: TextButton.styleFrom(
                    animationDuration: Duration.zero,
                    foregroundColor: active ? Colors.white : Colors.white70,
                  ),
                  child: Text(
                    swarm.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close ${swarm.name}',
                onPressed: () => notifier.closeSwarm(swarm.id),
                icon: const Icon(Icons.close, size: 13),
                constraints: const BoxConstraints.tightFor(
                  width: 30,
                  height: 30,
                ),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WindowSizeClass size) => [
    if (!size.isCompact) ...[
      IconButton(
        tooltip: withEffectiveShortcutHint(
          context,
          'New swarm',
          ShortcutAction.newSwarm,
        ),
        onPressed: _canAddSwarm ? notifier.newSwarm : null,
        icon: const Icon(Icons.add, size: 18),
      ),
      IconButton(
        key: const ValueKey('swarm-search-button'),
        tooltip: withEffectiveShortcutHint(
          context,
          'Navigate',
          ShortcutAction.switchAgent,
        ),
        onPressed: onNavigate,
        icon: const Icon(Icons.explore_outlined, size: 20),
      ),
    ],
    IconButton(
      key: const ValueKey('swarm-notifications-button'),
      tooltip: withEffectiveShortcutHint(
        context,
        'Agents needing input',
        ShortcutAction.showAttention,
      ),
      onPressed: onNotifications,
      icon: Badge(
        isLabelVisible: attention > 0,
        child: const Icon(Icons.notifications_none, size: 20),
      ),
    ),
    // Last, after the ones that act on THIS swarm. Settings is the one action
    // here that leaves the swarm behind, so it keeps the edge rather than
    // sitting among them — and it folds away with the rest, since the overflow
    // menu carries it too and two ways to the same screen is one too many.
    if (!size.isCompact)
      IconButton(
        key: const ValueKey('swarm-settings-button'),
        tooltip: withEffectiveShortcutHint(
          context,
          'Settings',
          ShortcutAction.showSettings,
        ),
        onPressed: onSettings,
        icon: const Icon(Icons.settings_outlined, size: 20),
      ),
    if (size.isCompact) _overflow(),
  ];

  Widget _overflow() => PopupMenuButton<_StripAction>(
    key: const ValueKey('swarm-overflow-button'),
    tooltip: 'More',
    constraints: const BoxConstraints(minWidth: 180),
    icon: const Icon(Icons.more_vert, size: 20),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: _StripAction.newSwarm,
        enabled: _canAddSwarm,
        child: const Text('New swarm'),
      ),
      const PopupMenuItem(
        value: _StripAction.navigate,
        child: Text('Navigate'),
      ),
      const PopupMenuItem(
        value: _StripAction.settings,
        child: Text('Settings'),
      ),
    ],
    onSelected: (action) {
      switch (action) {
        case _StripAction.newSwarm:
          notifier.newSwarm();
        case _StripAction.navigate:
          onNavigate();
        case _StripAction.settings:
          onSettings();
      }
    },
  );

  bool get _canAddSwarm => notifier.swarms.length < AppNotifier.maxSwarms;
}
