import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'package:harness_mobile/state/app_state.dart';
import 'agent_index.dart';
import 'agent_swipe.dart';
import 'agents_page.dart';
import 'link_page.dart';

/// Every phone page slides in the iOS way, and goes back with the edge swipe.
Route<void> phoneRoute(WidgetBuilder builder) =>
    CupertinoPageRoute<void>(builder: builder);

/// Where a tap on a machine goes. A machine this device holds no link to opens on ITS password
/// form — each machine has its own remote password — and only a linked one opens on its agents.
void openMachine(BuildContext context, AppNotifier notifier, String machineId) {
  final machine = notifier.stateOf(machineId);
  if (machine == null) return;
  Navigator.of(context).push(
    phoneRoute(
      (_) => machine.needsLink
          ? LinkPage(notifier: notifier, machineId: machineId)
          : AgentsPage(notifier: notifier, machineId: machineId),
    ),
  );
}

/// Opens one agent full screen.
///
/// ONE at a time, and that is the whole difference from the desktop grid: a phone has no room
/// for a second tile, so whatever else was open is closed rather than left attached somewhere
/// nobody can see it. The page goes up first and says it is attaching; the attach follows.
///
/// [swipeNeighbours] turns the page into a pager over that list — see [AgentSwipeList] and
/// [openAgentPager], which is how the Agents tab calls this.
void openAgent(
  BuildContext context,
  AppNotifier notifier,
  String machineId,
  String agentId, {
  AgentSwipeList? swipeNeighbours,
}) {
  Navigator.of(context).push(
    phoneRoute(
      (_) => AgentSwipeHost(
        notifier: notifier,
        machineId: machineId,
        agentId: agentId,
        neighbours: swipeNeighbours,
      ),
    ),
  );
  unawaited(_openPane(notifier, machineId, agentId, keepOthers: swipeNeighbours != null));
}

/// Opens one agent as a PAGER over [entries]: the page it lands on is the agent tapped, and a
/// horizontal swipe moves to the entry beside it.
///
/// Takes the entries as a SNAPSHOT rather than a way to recompute them. The list is sorted partly on
/// state that moves by itself — an agent that starts working sorts upward — so a page recomputing
/// "the next one" mid-session would renumber itself under the finger. What the person saw when they
/// tapped is the order they get, for as long as that screen is open.
void openAgentPager(
  BuildContext context,
  AppNotifier notifier,
  List<AgentEntry> entries,
  AgentEntry entry,
) => openAgent(
  context,
  notifier,
  entry.machineId,
  entry.agent.id,
  swipeNeighbours: AgentSwipeList(entries),
);

/// Attaches the agent's pane.
///
/// [keepOthers] is what separates the two ways in. A page opened on its own keeps the phone's old
/// rule — one pane, because a second one attached behind a screen nobody can see is a terminal
/// streaming for nothing. A PAGER deliberately keeps its neighbours attached: that is the whole
/// point of swiping, and the panes it keeps are exactly the pages it has mounted.
///
/// `selectAgent` already does the right thing either way — it reuses an existing pane and only
/// reopens a session that died, so arriving back on a page already attached costs nothing.
Future<void> _openPane(
  AppNotifier notifier,
  String machineId,
  String agentId, {
  required bool keepOthers,
}) async {
  await notifier.selectAgent(machineId, agentId);
  if (keepOthers) return;
  final keep = notifier.focusedPane?.id;
  for (final pane in [...notifier.panes]) {
    if (pane.id != keep) await notifier.closePane(pane.id);
  }
}
