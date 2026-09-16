import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/empty_state.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/state/attention.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';

import 'phone_card.dart';
import 'phone_header.dart';
import 'phone_navigation.dart';
import 'phone_status.dart';

/// Every agent, on every machine, that has stopped to ask the person something.
///
/// The desktop reaches the same list with ⇧⌘I and draws it as a searchable picker
/// (`widgets/swarm_attention.dart`); a phone gets a page instead, because there is no keyboard to
/// open it with and nothing else to look at while it is open. The badge on the Agents tab already
/// says HOW MANY are waiting — this is the screen that says which.
///
/// ⚠️ It is the one list that does not fall back to the whole roster. A page that showed idle
/// agents once everything had been answered would be a second, worse Agents tab; when there is
/// nothing waiting, the right answer is to say so and send the person back.
class AttentionPage extends StatelessWidget {
  const AttentionPage({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final entries = attentionEntries(notifier);
      final groups = attentionGroups(entries);
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              PhoneHeader(
                title: 'Needs input',
                subtitle: entries.isEmpty
                    ? null
                    : Text(
                        entries.length == 1
                            ? '1 agent waiting'
                            : '${entries.length} agents waiting',
                        style: TextStyle(
                          color: AppPalette.textSecondary,
                          fontSize: 13,
                        ),
                      ),
              ),
              Expanded(
                child: _Body(notifier: notifier, groups: groups),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.notifier, required this.groups});

  final AppNotifier notifier;
  final List<AttentionGroup> groups;

  /// Whether anything is still on its way in — a machine connecting, or its agents not yet
  /// answered. "Loading" and "nobody is waiting" must not render the same, which is the one thing
  /// this page's empty state has to get right: the second is good news and the first is not news
  /// at all.
  bool get _stillArriving {
    if (notifier.machines.isEmpty && notifier.machinesLoading) return true;
    for (final machine in notifier.machines) {
      final state = notifier.stateOf(machine.machineId);
      if (state == null) return true;
      if (phoneMachineStatusOf(state) == PhoneMachineStatus.connecting) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      if (_stillArriving) return const PhoneListSkeleton();
      return const EmptyState(
        icon: LucideIcons.circleCheck300,
        title: 'No agents waiting',
        message: 'Nothing has stopped to ask you anything right now.',
      );
    }
    // Every waiting agent across the whole page, in the order the rows are drawn — so a swipe on
    // the terminal this opens walks THIS list rather than the Agents tab's. Built from the groups
    // rather than recomputed, so the two cannot disagree about the order.
    final ordered = [
      for (final group in groups)
        for (final entry in group.entries) entry.agent,
    ];
    return RefreshIndicator(
      onRefresh: notifier.retryMachines,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: phoneListPadding(context),
        children: [
          for (final group in groups) ...[
            _MachineLabel(group.machineName),
            for (final entry in group.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: kPhoneCardGap),
                child: _AttentionRow(
                  entry: entry,
                  onTap: () => openAgentPager(
                    context,
                    notifier,
                    ordered,
                    entry.agent,
                  ),
                ),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// One waiting agent: its engine, its name, and what it is asking.
///
/// Taller than the app's other rows on purpose — [PhoneCard]'s fixed 70pt fits a name and a status
/// line, and the QUESTION is the whole reason to come here. A row that cropped it to a status pill
/// would send the person into the terminal to find out what the tap was for.
class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.entry, required this.onTap});

  final AttentionEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final agent = entry.agent.agent;
    final prompt = entry.promptLine;
    // Held to the same rule as every other row: an agent with no terminal to attach cannot be
    // opened. It still draws — it IS waiting, and hiding it would make the tab's badge count
    // rows this page does not have.
    final open = agent.terminalAvailable;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: open ? onTap : null,
        borderRadius: BorderRadius.circular(AppCard.radius),
        child: Opacity(
          opacity: open ? 1 : 0.55,
          child: Container(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            decoration: BoxDecoration(
              color: AppGlass.rowFill,
              borderRadius: BorderRadius.circular(AppCard.radius),
              // The attention rim every waiting row wears, matching [AgentRow] — the same agent
              // seen on two screens must not be marked two different ways.
              border: Border.all(color: AppPalette.warn.withValues(alpha: 0.42)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PhoneCardGlyph(
                  child: EngineMark(
                    engine: agent.engine,
                    displayName: agent.engineDisplayName,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppPalette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        entry.machineName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppPalette.textFaint,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                      // ⚠️ Two lines, never more. The prompt is already collapsed to one line by
                      // [AttentionEntry.promptLine]; letting it run further would turn a list into
                      // a transcript and push the next waiting agent off the screen.
                      Text(
                        prompt ?? 'Waiting for you',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: prompt == null
                              ? AppPalette.textFaint
                              : AppPalette.textSecondary,
                          fontSize: 13.5,
                          height: 1.35,
                          fontStyle: prompt == null
                              ? FontStyle.italic
                              : FontStyle.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (open)
                  Padding(
                    padding: const EdgeInsets.only(top: 11),
                    child: Icon(
                      LucideIcons.chevronRight300,
                      size: 22,
                      color: AppPalette.textFaint,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The machine a group of rows belongs to.
///
/// The rows name their machine as well, because one is read on its own the moment the page
/// scrolls past this heading — the heading is what makes the grouping visible, not what carries
/// the fact.
class _MachineLabel extends StatelessWidget {
  const _MachineLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppPalette.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
