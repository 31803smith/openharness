import 'package:harness_mobile/core/fuzzy_match.dart';
import 'package:harness_mobile/state/app_state.dart';

import 'agent_index.dart';
import 'machine_index.dart';
import 'phone_status.dart';

/// What a search result opens.
enum PhoneSearchKind { agent, machine }

/// One row the search offers, whichever of the two lists it came from.
///
/// The phone's two tabs answer two different questions — every agent on the
/// account, every machine on the account — and until now there was nowhere to
/// ask both at once. Somebody who remembers only "that review thing" should not
/// have to know first whether it is the name of an agent or of the machine it
/// runs on. This is the flattening that lets one query reach both, built the way
/// [AgentEntry] flattens machine-keyed state for the Agents tab.
///
/// [fields] is what the query is matched against, title fields first. The order
/// is the ranking: a hit on the name outranks a hit on the machine under it, the
/// same rule the desktop's `swarmFieldMatchScore` applies with its `title` flag.
class PhoneSearchResult {
  const PhoneSearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.summary,
    required this.machineId,
    this.titleFields = 1,
    this.entry,
    this.machine,
  });

  final PhoneSearchKind kind;

  /// Unique across both kinds — an agent and a machine can share a name, and
  /// two machines can each hold an agent with the same id.
  final String id;

  /// The name, as the row draws it and as the query matches it first.
  final String title;

  /// The line under it: an agent's engine and machine, a machine's status.
  final String subtitle;

  /// Every searchable string, lowercased, title first. Not everything in here is
  /// drawn — an agent's engine id is matched but never shown as itself — which is
  /// why [SearchResultText] re-checks that a matched field is actually present in
  /// the text it is emphasising.
  final List<String> fields;

  /// How many of [fields], from the front, rank as a name rather than as
  /// metadata: two for an agent that has a title, which is how people describe
  /// it, and is ranked that way on the desktop too (its `titleFields`).
  final int titleFields;

  final PhoneSummary summary;

  /// The machine this row belongs to, for either kind. An agent needs it to
  /// open; a machine IS it.
  final String machineId;

  /// Set for [PhoneSearchKind.agent] — what a tap opens.
  final AgentEntry? entry;

  /// Set for [PhoneSearchKind.machine].
  final MachineState? machine;
}

/// Everything one query can reach, unfiltered: agents most recent first (see
/// [recentAgents]), then machines in the order their tab draws them.
///
/// Agents come from [agentIndex], so only machines that are LINKED and answering
/// contribute — a row offered here has to be openable, and an offline machine's
/// last-seen agent list is not. Machines come from [visibleMachines], which keeps
/// every one INCLUDING the locked and the offline: a machine wanting its password
/// is exactly what somebody searching for it came to fix.
///
/// The asymmetry is deliberate and is the same one the tabs already make.
List<PhoneSearchResult> phoneSearchIndex(AppNotifier notifier) {
  final results = <PhoneSearchResult>[];
  for (final entry in recentAgents(agentIndex(notifier))) {
    results.add(_agentResult(entry));
  }
  for (final machine in visibleMachines(notifier)) {
    final summary = phoneMachineSummary(machine);
    results.add(
      PhoneSearchResult(
        kind: PhoneSearchKind.machine,
        id: 'machine:${machine.machine.machineId}',
        title: machine.machine.displayName,
        subtitle: summary.label,
        fields: [
          machine.machine.displayName.toLowerCase(),
          summary.label.toLowerCase(),
        ].where((field) => field.isNotEmpty).toList(),
        summary: summary,
        machineId: machine.machine.machineId,
        machine: machine,
      ),
    );
  }
  return results;
}

PhoneSearchResult _agentResult(AgentEntry entry) {
  final agent = entry.agent;
  final engine = agent.engineDisplayName ?? agent.engine ?? '';
  final title = agent.title ?? '';
  final branch = entry.project?.branchLabel ?? '';
  return PhoneSearchResult(
    kind: PhoneSearchKind.agent,
    id: 'agent:${entry.machineId}:${agent.id}',
    title: agent.name,
    // What tells `work · 3188` from `work · 48e9`: the work itself, then its
    // branch. The folder and the machine are said once, by the group header
    // over the row, rather than repeated down every line of it; the engine is
    // the mark's to show and is only spelled out when nothing else is known.
    subtitle: [
      title,
      branch,
    ].where((part) => part.isNotEmpty).join(' · ').ifEmpty(engine),
    fields: [
      agent.name.toLowerCase(),
      title.toLowerCase(),
      entry.machineName.toLowerCase(),
      engine.toLowerCase(),
      // The raw engine id as well as its display name: somebody types "codex",
      // and the display name may well be "Codex CLI".
      (agent.engine ?? '').toLowerCase(),
      (entry.project?.folder ?? '').toLowerCase(),
      // The project's own name is not drawn on a result row, but it is how
      // people describe the agent they are hunting for, so it stays searchable.
      // [SearchResultText] checks that a matched field is present in the text
      // it is about to emphasise, so matching here never bolds something
      // unrelated.
      (entry.project?.name ?? '').toLowerCase(),
      branch.toLowerCase(),
    ].where((field) => field.isNotEmpty).toList(),
    titleFields: title.isEmpty ? 1 : 2,
    summary: entry.summary,
    machineId: entry.machineId,
    entry: entry,
  );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

/// The query, split into the words that each have to match something.
///
/// Every word must hit — possibly a DIFFERENT field each — so "review mac" finds
/// the review agent on the MacBook without either word having to match the whole
/// row. The desktop splits the same way, and the freedom to match different
/// fields is what makes word order not matter.
List<String> phoneSearchTerms(String query) => query
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((term) => term.isNotEmpty)
    .toList();

/// How well [term] matches [field]: LOWER is better, null does not match.
///
/// Ported from the desktop's `swarmFieldMatchScore` so both apps rank alike.
/// The bands, cheapest first: an exact field, a prefix, a substring anywhere,
/// and last a scattered-letter subsequence whose cost grows with how far apart
/// the letters landed. A non-title field takes a flat 64 penalty, which is what
/// keeps a name match ahead of every piece of metadata under it.
int? phoneFieldMatchScore(String field, String term, {required bool title}) {
  final offset = field.indexOf(term);
  final spread = offset >= 0 ? 0 : subsequenceSpread(field, term);
  if (spread == null) return null;
  return (title ? 0 : 64) +
      (field == term
          ? 0
          : offset == 0
          ? 8
          : offset > 0
          ? 16
          : 128 + spread);
}

/// The field [term] reaches best on [row] — its score and its index in
/// [PhoneSearchResult.fields] — or null when it reaches none.
///
/// Shared by the ranking and by the emphasis, so the field a row is ranked on is
/// the field that is bolded.
///
/// Bounded: a pathologically long field is skipped rather than scanned, so one
/// agent named with a pasted log cannot make a keystroke cost more than a frame.
({int score, int index})? phoneBestFieldMatch(
  PhoneSearchResult row,
  String term,
) {
  ({int score, int index})? best;
  for (final (index, field) in row.fields.indexed) {
    if (field.length > 4096) continue;
    final score = phoneFieldMatchScore(
      field,
      term,
      title: index < row.titleFields,
    );
    if (score != null && (best == null || score < best.score)) {
      best = (score: score, index: index);
    }
    // Every field past the title fields is metadata, whose best possible score
    // is 64. An exact, prefix or substring title match already beats that, so
    // once the title fields are behind us there is nothing left to find.
    if (best != null && index >= row.titleFields - 1 && best.score <= 64) {
      break;
    }
  }
  return best;
}

/// The rows [query] reaches, best first.
///
/// An empty query keeps index order untouched: [phoneSearchIndex] already put
/// the agents in the order worth offering before a word is typed.
///
/// ⚠️ Ties break on the row's position in the index, never on anything that
/// moves by itself. An agent that starts working sorts upward in [agentIndex],
/// and that is the one reshuffle worth having; a second, unstable tiebreak on
/// top of it would let two idle rows swap places on an unrelated rebuild.
List<PhoneSearchResult> rankPhoneSearch(
  List<PhoneSearchResult> all,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return all;
  final terms = phoneSearchTerms(needle);
  if (terms.isEmpty) return all;

  final ranked = <({PhoneSearchResult row, int score, int index})>[];
  for (final (index, row) in all.indexed) {
    // An exact hit on the name — or the title — wins outright, ahead of every
    // scored row. Typing one in full is the least ambiguous thing somebody can do.
    if (row.fields.take(row.titleFields).contains(needle)) {
      ranked.add((row: row, score: -1, index: index));
      continue;
    }
    var total = 0;
    for (final term in terms) {
      final best = phoneBestFieldMatch(row, term);
      // One word matching nothing drops the row: the words narrow, they do not
      // accumulate. Without this, "review mac" would return everything either
      // word touches.
      if (best == null) {
        total = -1;
        break;
      }
      total += best.score;
    }
    if (total >= 0) ranked.add((row: row, score: total, index: index));
  }

  ranked.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    return byScore != 0 ? byScore : a.index.compareTo(b.index);
  });
  return [for (final row in ranked) row.row];
}

/// The matching rows of one kind, keeping rank order.
List<PhoneSearchResult> phoneSearchOfKind(
  List<PhoneSearchResult> rows,
  PhoneSearchKind kind,
) => [
  for (final row in rows)
    if (row.kind == kind) row,
];

/// The agent rows' entries, in rank order — what a pager opened from a result
/// swipes along.
///
/// ⚠️ **One entry out, one agent row in.** [PhoneSearchResult.entry] is nullable
/// because a machine row has none, so unwrapping it at the call site invites a
/// null-collapse that quietly drops a row. The pager walks this list BY INDEX
/// against the rows drawn on screen: a list one shorter than the list somebody
/// tapped sends the next swipe to a different agent than the one beside it.
///
/// Building it here keeps that invariant next to the code that establishes it —
/// [phoneSearchIndex] sets `entry` on every agent row it makes — rather than
/// leaving each caller to rediscover it.
List<AgentEntry> phoneSearchAgentEntries(List<PhoneSearchResult> rows) => [
  for (final row in rows)
    if (row.kind == PhoneSearchKind.agent && row.entry != null) row.entry!,
];
