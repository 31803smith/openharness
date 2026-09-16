import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';

import 'agent_context_line.dart';
import 'agent_index.dart';
import 'phone_card.dart';
import 'status_pill.dart';

/// One agent in the Agents tab: who it is, what it is doing, and where it is.
///
/// The same three lines [AgentTile] draws on a machine's own page — the two rows differ now only in
/// where they get their agent from, and both end in [AgentContextLine] so one agent reached two
/// ways is not described two ways.
class AgentRow extends StatelessWidget {
  const AgentRow({
    super.key,
    required this.entry,
    required this.onTap,
    this.onLongPress,
  });

  final AgentEntry entry;
  final VoidCallback onTap;

  /// The row's `⋯`, held rather than tapped — the same door [AgentTile] opens on a machine's own
  /// page. Optional for the same reason it is there: a row that cannot be OPENED can still be
  /// acted on, and an agent whose terminal has gone is exactly the one somebody wants to delete.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final agent = entry.agent;
    return PhoneCard(
      height: kPhoneAgentCardHeight,
      onTap: agent.terminalAvailable ? onTap : null,
      onLongPress: onLongPress,
      // A rim in the attention colour, so a waiting agent is findable in a long list without
      // reading a word of it — the list's whole job on a phone.
      border: entry.isWaiting
          ? Border.all(color: AppPalette.warn.withValues(alpha: 0.42))
          : null,
      child: Row(
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
              mainAxisAlignment: MainAxisAlignment.center,
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
                StatusPill(summary: entry.summary),
                const SizedBox(height: 3),
                AgentContextLine(
                  project: entry.project,
                  machineName: entry.machineName,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (agent.terminalAvailable)
            Icon(
              LucideIcons.chevronRight300,
              size: 22,
              color: AppPalette.textFaint,
            ),
        ],
      ),
    );
  }
}
