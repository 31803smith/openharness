import 'package:harness_mobile/phone/agent_index.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/state/pending_question.dart';

/// One agent that has stopped to ask the person something, together with everything needed to
/// draw it and to open it.
///
/// The desktop's equivalent (`state/swarm_attention.dart`) is built out of `SwarmDestination`s,
/// because there a selection has to decide WHICH pane of WHICH swarm the agent lands in. A phone
/// has neither: one tap, one full-screen terminal. So this carries the agent itself instead, and
/// the whole destination/ranking half of the desktop file is dropped rather than ported into a
/// shape nothing here would read.
class AttentionEntry {
  const AttentionEntry({required this.agent, required this.question});

  /// The agent and its machine, from the same [agentIndex] the Agents tab and the tab badge are
  /// built from — so a row here cannot exist for an agent the list refuses to draw.
  final AgentEntry agent;

  /// What it is asking, when the question is still on screen at the other end.
  ///
  /// ⚠️ Nullable on purpose, and not the same thing as "no question". `blockedAgents` is what marks
  /// an agent as waiting in the first place, so in practice this is set — but the entry is built
  /// from the agent index rather than from the question map, and a row that vanished because its
  /// prompt text was momentarily unavailable would be worse than one drawn without its prompt.
  final PendingQuestion? question;

  String get machineId => agent.machineId;
  String get machineName => agent.machineName;
  String get agentId => agent.agent.id;

  /// Stable across rebuilds — a machine and an agent, the pair the app keys everything else on.
  String get id => '$machineId/$agentId';

  /// The question as a row prints it: one line, whitespace collapsed.
  ///
  /// A prompt arrives as whatever the pane held, newlines and runs of spaces included, and a
  /// `maxLines: 2` `Text` of that draws a mostly-empty box. Collapsing here rather than in the
  /// widget keeps the trimming with the data, the way the desktop keeps its search fields.
  String? get promptLine {
    final prompt = question?.prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    return prompt == null || prompt.isEmpty ? null : prompt;
  }
}

/// Every agent waiting on an answer, oldest question first.
///
/// Ordered by [PendingQuestion.since] like the desktop's picker, for the same reason: the one that
/// has been waiting longest is the one holding work up. Ties — and an agent whose question is not
/// in the map — fall back to [AttentionEntry.id] so the list cannot reshuffle itself under a
/// finger already reaching for a row.
List<AttentionEntry> attentionEntries(AppNotifier notifier) {
  final entries = [
    for (final agent in waitingAgents(agentIndex(notifier)))
      AttentionEntry(
        agent: agent,
        question: notifier.questionFor(agent.machineId, agent.agent.id),
      ),
  ];
  entries.sort((a, b) {
    final aSince = a.question?.since;
    final bSince = b.question?.since;
    if (aSince != null && bSince != null) {
      final age = aSince.compareTo(bSince);
      if (age != 0) return age;
    } else if (aSince != bSince) {
      // An entry with no question sorts last: it is the one we know least about.
      return aSince == null ? 1 : -1;
    }
    return a.id.compareTo(b.id);
  });
  return entries;
}

/// The same entries, grouped by machine and keeping the order above within each group.
///
/// The machines themselves are ordered by their most urgent entry — the first one [attentionEntries]
/// produced for them — so a machine whose agent has waited longest heads the page. Anything else
/// (account order, alphabetical) would bury the row the page exists to surface.
List<AttentionGroup> attentionGroups(List<AttentionEntry> entries) {
  final byMachine = <String, List<AttentionEntry>>{};
  for (final entry in entries) {
    (byMachine[entry.machineId] ??= []).add(entry);
  }
  return [
    for (final rows in byMachine.values)
      AttentionGroup(
        machineId: rows.first.machineId,
        machineName: rows.first.machineName,
        entries: List.unmodifiable(rows),
      ),
  ];
}

/// One machine's worth of waiting agents.
class AttentionGroup {
  const AttentionGroup({
    required this.machineId,
    required this.machineName,
    required this.entries,
  });

  final String machineId;
  final String machineName;
  final List<AttentionEntry> entries;
}
