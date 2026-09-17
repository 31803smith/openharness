import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';

import 'compact_age.dart';
import 'phone_search_index.dart';
import 'phone_status.dart';
import 'search_result_text.dart';
import 'status_pill.dart';

/// One result: the mark, the two lines, and what is worth knowing before a tap.
///
/// Shorter than the tabs' 70pt [PhoneCard] and without its fill. A result list
/// is read top to bottom against a query and abandoned the moment the right row
/// is seen, so it is built for scanning: more rows in a thumb's reach, and the
/// emphasis carried by the bolded match rather than by a card edge.
class PhoneSearchRow extends StatefulWidget {
  const PhoneSearchRow({
    super.key,
    required this.row,
    required this.terms,
    required this.now,
    required this.onTap,
  });

  final PhoneSearchResult row;
  final List<String> terms;

  /// One clock for the whole list, so two rows built a frame apart cannot
  /// disagree about what "4m" means.
  final DateTime now;
  final VoidCallback onTap;

  @override
  State<PhoneSearchRow> createState() => _PhoneSearchRowState();
}

class _PhoneSearchRowState extends State<PhoneSearchRow> {
  bool _pressed = false;

  /// An agent whose terminal has gone cannot be opened, the same rule
  /// [AgentRow] applies. A machine opens unless it is offline — a locked one
  /// opens on its password form, which is the thing to do about it, but a
  /// switched-off one has nothing to take a password.
  bool get _openable => switch (widget.row.kind) {
    PhoneSearchKind.agent => widget.row.entry?.agent.terminalAvailable ?? false,
    PhoneSearchKind.machine =>
      widget.row.machine == null ||
          phoneMachineStatusOf(widget.row.machine!) !=
              PhoneMachineStatus.offline,
  };

  void _press(bool pressed) {
    if (!_openable || _pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  void _open() {
    // The keyboard goes away with the screen, not a frame after it — dismissing
    // it first keeps the push from animating over a collapsing inset.
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final row = widget.row;
    final matches = phoneResultMatches(row, widget.terms);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: _openable ? _open : null,
      child: AnimatedContainer(
        duration: AppMotion.press,
        curve: AppMotion.curve,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          // No resting fill. The tabs' cards earn one because they are the
          // screen's content; a result row is a line of an answer, and forty of
          // them each in their own box is a wall rather than a list.
          color: _pressed ? AppGlass.rowFill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppCard.radius),
        ),
        child: Opacity(
          opacity: _openable ? 1 : 0.55,
          child: Row(
            children: [
              _Mark(row: row),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SearchResultText(
                      row.title,
                      matches: matches,
                      style: TextStyle(
                        color: AppPalette.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SearchResultText(
                      row.subtitle,
                      matches: matches,
                      style: TextStyle(
                        color: AppPalette.textFaint,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              _Trailing(row: row, openable: _openable, now: widget.now),
            ],
          ),
        ),
      ),
    );
  }
}

/// The square mark at the head of a result: an agent's engine, a machine's
/// screen. Smaller than the tabs' 44pt [PhoneCardGlyph], to match the shorter
/// row.
class _Mark extends StatelessWidget {
  const _Mark({required this.row});

  final PhoneSearchResult row;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppSurface.recess,
        borderRadius: BorderRadius.circular(10),
        // The same attention rim the Agents tab puts on a waiting row, so an
        // agent that has stopped to ask something is findable here too.
        border: row.entry?.isWaiting ?? false
            ? Border.all(color: AppPalette.warn.withValues(alpha: 0.42))
            : null,
      ),
      child: Center(
        child: switch (row.kind) {
          PhoneSearchKind.agent => EngineMark(
            engine: row.entry?.agent.engine,
            displayName: row.entry?.agent.engineDisplayName,
            size: 18,
          ),
          PhoneSearchKind.machine => Icon(
            LucideIcons.laptopMinimal300,
            size: 18,
            color: phoneToneColor(row.summary.tone),
          ),
        },
      ),
    );
  }
}

/// The row's trailing edge: why it cannot be opened, or else how fresh it is.
///
/// An agent that opens says when its conversation last moved — `4m` — or that
/// it is `working` right now, which is what explains a row sorted above a
/// fresher one. Unboxed and faint: it is read after the name, never instead.
///
/// A boxed word is kept for what a tap would NOT make obvious: a machine's
/// Unlock or Offline, and an agent whose terminal has gone. Dimming alone leaves
/// the person tapping a row that cannot answer and reading nothing about why.
class _Trailing extends StatelessWidget {
  const _Trailing({
    required this.row,
    required this.openable,
    required this.now,
  });

  final PhoneSearchResult row;
  final bool openable;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final badge = _badge;
    if (badge != null) return _Badge(badge);
    final entry = row.entry;
    if (entry == null) return const SizedBox.shrink();
    if (entry.isWorking) {
      return _Recency('working', color: phoneToneColor(PhoneTone.busy));
    }
    final at = entry.agent.updatedAt;
    if (at == null) return const SizedBox.shrink();
    return _Recency(compactAge(at, now), color: AppPalette.textFaint);
  }

  String? get _badge {
    final machine = row.machine;
    return switch (row.kind) {
      PhoneSearchKind.agent => openable ? null : 'No terminal',
      PhoneSearchKind.machine => switch (machine == null
          ? null
          : phoneMachineStatusOf(machine)) {
        PhoneMachineStatus.offline => 'Offline',
        PhoneMachineStatus.needsPassword => 'Unlock',
        // Its state, not a verb: the tap brings a sheet of actions, and "View"
        // promised a screen that is no longer there.
        _ => 'Connected',
      },
    };
  }
}

class _Recency extends StatelessWidget {
  const _Recency(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontFeatures: AppFont.tabularFigures,
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppGlass.hair),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: AppPalette.textFaint,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
