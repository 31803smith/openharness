import 'dart:async';

import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';

import 'agent_swipe_list.dart';

/// Opens the agents one swipe either side of the one on screen, and closes the ones further out.
///
/// ⚠️ **Why a swipe needs this.** A page is not built until the finger drags it in, and an agent
/// nobody has opened yet had no stream at all until the swipe passed halfway: the page slid in as
/// "Attaching…", the stream opened, and the agent's screen arrived as a keyframe a network round
/// trip later — well after the swipe had finished. Opened in advance, the keyframe has long landed
/// and the page slides in already showing its output.
///
/// ⚠️ **Only once the agent on screen is live, and a beat after.** Two reasons. Its size is the size
/// the neighbours open at — every page of the pager shares it — and there is no size until its own
/// keyframe has come back. And the home screen closes every pane but the one it opened as it builds
/// a pager (`AgentHome._attachOnly`); by the time the agent on screen is live that has happened, so
/// it cannot close what this opens. The beat keeps the neighbours' keyframes, parsed on the UI
/// thread, off the frames where the landed page is still settling.
///
/// ⚠️ **A window of three, not everything ever swiped past.** The pager used to keep every agent it
/// visited attached until it was thrown away; with neighbours opened on top of that, a lap of the
/// list would leave a live stream per agent. Agents outside the window are closed as it moves.
class AgentNeighbourWarmer {
  AgentNeighbourWarmer({
    required this.notifier,
    required this.list,
    required this.attached,
  });

  final AppNotifier notifier;
  final AgentSwipeList list;

  /// The pager's own record of what it opened — shared, so what this opens is closed with the rest
  /// when the pager goes, and what this closes is no longer on it.
  final Set<AgentRef> attached;

  /// How long the page on screen has been live before its neighbours are opened.
  static const delay = Duration(milliseconds: 600);

  Timer? _timer;

  /// The page whose neighbours are open, so every notifier change afterwards costs one comparison.
  int? _warmedPage;

  /// Warms [page]'s neighbours if [current] — the agent on it — is live and they are not warm yet.
  ///
  /// Cheap enough to call on every notifier change, which is how the pager calls it: that is the only
  /// signal that the agent on screen has gone live.
  void check({required int page, required AgentRef current}) {
    if (!list.wraps || _warmedPage == page || _timer != null) return;
    final session = notifier
        .paneOfAgent(current.machineId, current.agentId)
        ?.session;
    if (session == null ||
        session.status != TerminalSessionStatus.controlling) {
      return;
    }
    _timer = Timer(delay, () {
      _timer = null;
      _warmedPage = page;
      _warm(page, current, cols: session.cols, rows: session.rows);
    });
  }

  /// Forgets the page it was warming for — the pager has moved.
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _warmedPage = null;
  }

  void dispose() => cancel();

  AgentRef _at(int page) {
    final entry = list.entries[page % list.entries.length];
    return (machineId: entry.machineId, agentId: entry.agent.id);
  }

  void _warm(
    int page,
    AgentRef current, {
    required int cols,
    required int rows,
  }) {
    // A set, so a two-agent pager — whose page before and page after are the same agent — opens it
    // once.
    final window = {current, _at(page - 1), _at(page + 1)};
    for (final agent in [...attached]) {
      if (window.contains(agent)) continue;
      attached.remove(agent);
      final pane = notifier.paneOfAgent(agent.machineId, agent.agentId);
      if (pane != null) unawaited(notifier.closePane(pane.id));
    }
    for (final agent in window) {
      if (agent == current) continue;
      attached.add(agent);
      unawaited(
        notifier.preattachAgent(
          agent.machineId,
          agent.agentId,
          cols: cols,
          rows: rows,
        ),
      );
    }
  }
}
