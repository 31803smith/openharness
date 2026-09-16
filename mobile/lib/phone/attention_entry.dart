import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/app_icon_button.dart';
import 'package:harness_mobile/state/app_state.dart';

import 'agent_index.dart';
import 'attention_page.dart';
import 'phone_navigation.dart';

/// Pushes [AttentionPage].
///
/// Separate from the button so anything else that should land there — a notification tap, a
/// future shortcut — opens the same route rather than pushing its own.
void openAttentionPage(BuildContext context, AppNotifier notifier) =>
    Navigator.of(context).push(
      phoneRoute((_) => AttentionPage(notifier: notifier)),
    );

/// The way into [AttentionPage], drawn in the Agents tab header's `trailing`.
///
/// ⚠️ **Absent when nothing is waiting**, rather than drawn disabled or drawn with a zero badge.
/// The page's own answer for that case is an empty state, and a glyph whose only outcome is being
/// told "nothing here" is worse than no glyph — the same rule the search button in that header
/// keeps. It is also why the count lives on the button rather than beside it: the button only
/// exists while the count is worth reading.
Widget buildAttentionButton(BuildContext context, AppNotifier notifier) {
  final waiting = waitingAgents(agentIndex(notifier)).length;
  if (waiting == 0) return const SizedBox.shrink();
  return _AttentionButton(notifier: notifier, count: waiting);
}

class _AttentionButton extends StatelessWidget {
  const _AttentionButton({required this.notifier, required this.count});

  final AppNotifier notifier;
  final int count;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Stack(
        // The badge overhangs the glyph's box on both axes, the way the tab bar's does.
        clipBehavior: Clip.none,
        children: [
          AppIconButton(
            icon: LucideIcons.bell300,
            size: 22,
            tooltip: count == 1 ? '1 agent waiting' : '$count agents waiting',
            // The glyph itself carries the attention colour: it is only on screen because
            // something IS waiting, so drawing it in the quiet ink every other header control
            // uses would hide the one control worth noticing.
            color: AppPalette.warn,
            onPressed: () => openAttentionPage(context, notifier),
          ),
          Positioned(
            top: -3,
            right: -5,
            // Ignores pointers so the badge cannot eat a tap meant for the button under it —
            // it overhangs the glyph's box, so it sits over the row's padding as well.
            child: IgnorePointer(child: _Badge(count: count)),
          ),
        ],
      ),
    );
  }
}

/// The count, drawn the same way the Agents tab's own badge is.
///
/// Deliberately a second, private copy of `phone_tab_bar.dart`'s `_Badge` rather than a shared
/// one: that badge rims itself in the tab bar's `panelBg` so it reads as separate from the icon it
/// overlaps, and this one sits on the page background instead. One widget carrying both would
/// need a colour argument at every call site to say which surface it is on, which is more moving
/// parts than the eleven lines it would save.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppPalette.warn,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppPalette.windowBg, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        // Past 99 the exact figure stops meaning anything and the pill would widen off the glyph.
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          // Follows the theme because the fill does — see the tab bar's badge for the contrast
          // measurements behind this pair.
          color: AppTheme.pick(Colors.white, const Color(0xFF181818)),
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w700,
          fontFeatures: AppFont.tabularFigures,
        ),
      ),
    );
  }
}
