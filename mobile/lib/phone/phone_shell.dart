// `Timer` — used only by the kept-but-dead landing rules below, which is also why
// `phone_navigation.dart` and `phone_status.dart` are still imported here.
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:harness_mobile/state/app_state.dart';

import '../p2p/phone_terminal_p2p.dart';
import 'agent_home.dart';
import 'agent_index.dart';
import 'machines_tab.dart';
import 'phone_navigation.dart';
import 'phone_shell_scope.dart';
import 'phone_status.dart';
import 'phone_tab_bar.dart';
import 'settings_page.dart';

/// Whether the shell draws its tab bar.
///
/// Off because the terminal is where the phone opens and stays: [AgentHome] is
/// the Agents tab's root, it picks the agent itself, and a bar for steering
/// between tabs by hand is a row of chrome under every screen paying for a case
/// that no longer arises.
///
/// ⚠️ It hides the BAR, not the tabs. All three still exist, still hold their
/// own page stacks, and [_PhoneShellState._select] still pops one back to its
/// root — nothing below this flag knows it is off. What goes with it is the only
/// way to REACH a tab by hand, so with it off the app can only be where it was
/// put: fine while that place is one agent's terminal, and the reason this is a
/// flag rather than a deletion.
const bool _showTabBar = false;

/// The signed-in phone app: three tabs, each with its own page stack.
///
/// Its own [Navigator] per tab, nested under the app's, on purpose. Two reasons, and both are
/// things a single shared navigator gets wrong:
///
///  - `RootShell` swaps this whole shell out on sign-out, and the pages have to go with it rather
///    than stay stacked over the login screen, as they would on the root navigator.
///  - A tab remembers where it was. Walking into a machine's agents, switching to Settings and
///    coming back returns to that machine, not to the root of the tab — which is what every phone
///    OS does and what a single stack cannot express.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> with WidgetsBindingObserver {
  PhoneTab _tab = PhoneTab.agents;

  final _navigators = {
    for (final tab in PhoneTab.values) tab: GlobalKey<NavigatorState>(),
  };

  /// One per tab — see the note at the `HeroControllerScope` below for why they cannot be shared.
  final _heroControllers = {
    for (final tab in PhoneTab.values) tab: HeroController(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkedMachineId.dispose();
    for (final controller in _heroControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ── Where the app lands ───────────────────────────────────────────────────────────────────────
  //
  // Almost nothing, now — and that is the change. The shell used to reopen the last agent itself,
  // fall back to Machines when nothing answered, and time the wait out after 45 seconds, because
  // the thing it was steering towards was a page it had to PUSH over an agents list. There is no
  // list and no push: [AgentHome] is the Agents tab's root, and it reads the last-agent record,
  // waits for the machines to answer and picks the agent, all as part of drawing itself.
  //
  // One move is left, because it crosses tabs and no page can make it alone: a password accepted on
  // the Machines tab takes the person back to Agents, where the machine they just opened is about
  // to bring its agents with it.

  /// The machine whose password was just accepted, for [AgentHome] to open once it answers.
  ///
  /// ⚠️ **A notifier and not a field on this State, because a field cannot reach [AgentHome] at
  /// all.** Each tab's root is built inside `onGenerateRoute`, which a nested [Navigator] runs ONCE
  /// when it creates that route — so the root keeps forever whatever arguments it was first given,
  /// and `setState` here rebuilds this widget without ever rebuilding it. A value passed down as a
  /// constructor field would have been read on the first launch frame, when no machine had been
  /// linked, and never again.
  ///
  /// Handed over once, at construction, and written to afterwards: [AgentHome] listens, so a value
  /// set at any point reaches it. Never reset here — [AgentHome] spends the request itself, on the
  /// agent arriving or on a swipe away from it.
  final _linkedMachineId = ValueNotifier<String?>(null);

  /// A password was accepted: the agent is what the person came for, so the phone points itself at
  /// that machine and shows the tab an agent lives on.
  ///
  /// No waiting and no timeout here, which is what this used to be full of. The machine is still
  /// connecting at this point and [AgentHome] is already watching for exactly that — it holds
  /// whatever is on screen while the machine dials, then opens the first agent it reports.
  void _followLinkedMachine(String machineId) {
    _linkedMachineId.value = machineId;
    setState(() {
      _tab = PhoneTab.agents;
      _tabCanPop =
          _navigators[PhoneTab.agents]?.currentState?.canPop() ?? false;
    });
  }

  // ── The landing rules this replaced, kept and not called ──────────────────────────────────────
  //
  // ⚠️ **Dead on purpose: nothing below this line runs.** It is the shell's old way of deciding
  // where the app opens, from when the Agents tab's root was a LIST and a terminal had to be pushed
  // over it — so the shell waited for a machine to answer, pushed the pager itself, gave up after
  // [_pendingTimeout], and fell back to Machines when no machine answered at all. [AgentHome] now
  // does all of that as part of drawing itself, without a push and without a timeout, so none of
  // this is wired up any more.
  //
  // Kept because the list screens are kept: `_showTabBar` above and `AgentsTab` are both still here
  // for the same reason, and bringing them back would need these rules back with them.
  // [_followLinkedMachine] above is the live one; the copy here is renamed so the two can sit side
  // by side.
  //
  // `ignore_for_file` is deliberately NOT used: the ignores are per-member, so an unused member
  // added to this class later still gets flagged.

  /// An agent waiting for its machine to answer before it can be opened.
  // ignore: unused_field
  ({String machineId, String? agentId, bool afterLink})? _pending;
  // ignore: unused_field
  Timer? _pendingDeadline;

  /// How long a machine gets to answer. Past this the phone stays where it is — on a list the person
  /// can act on — rather than jumping into a terminal a minute after they stopped expecting it.
  // ignore: unused_field
  static const _pendingTimeout = Duration(seconds: 45);

  /// The last-agent record has not been read yet, so the landing tab cannot be chosen: a reopen
  /// would override it.
  // ignore: unused_field
  bool _readingLastAgent = true;

  /// The landing has been decided — by the shell or by the person — and nothing moves on its own
  /// again except [_followLinkedMachineLegacy], which the person asked for by entering a password.
  // ignore: unused_field
  bool _landed = false;

  // ignore: unused_element
  Future<void> _reopenLastAgent() async {
    final last = await widget.notifier.lastOpenedAgent.read();
    if (!mounted) return;
    _readingLastAgent = false;
    if (last != null && !_landed) {
      _wait(machineId: last.machineId, agentId: last.agentId, afterLink: false);
    } else {
      _onAppChanged();
    }
  }

  // ignore: unused_element
  void _followLinkedMachineLegacy(String machineId) {
    _landed = true;
    // Straight to Agents, before the machine has finished connecting: the row it lands on says
    // "Connecting…", which is what is actually happening, and the agent opens over it once it can.
    setState(() {
      _tab = PhoneTab.agents;
      _tabCanPop =
          _navigators[PhoneTab.agents]?.currentState?.canPop() ?? false;
    });
    _wait(machineId: machineId, agentId: null, afterLink: true);
  }

  // ignore: unused_element
  void _wait({
    required String machineId,
    required String? agentId,
    required bool afterLink,
  }) {
    _pending = (machineId: machineId, agentId: agentId, afterLink: afterLink);
    _pendingDeadline?.cancel();
    _pendingDeadline = Timer(_pendingTimeout, _dropPending);
    _onAppChanged();
  }

  // ignore: unused_element
  void _dropPending() {
    _pending = null;
    _pendingDeadline?.cancel();
    _pendingDeadline = null;
    if (mounted) _onAppChanged();
  }

  // ignore: unused_element
  void _onAppChanged() {
    if (!mounted) return;
    final pending = _pending;
    if (pending == null) {
      _decideLanding();
      return;
    }
    final notifier = widget.notifier;
    final machine = notifier.stateOf(pending.machineId);
    if (machine == null) {
      // Not on the account — or the account's machines have not arrived yet.
      if (notifier.machines.isNotEmpty && !notifier.machinesLoading) {
        _dropPending();
      }
      return;
    }
    switch (phoneMachineStatusOf(machine)) {
      case PhoneMachineStatus.needsPassword:
        return _dropPending();
      case PhoneMachineStatus.offline:
        // ⚠️ Not given up on straight after a link. Accepting a password closes the machine's old
        // socket before dialling a new one, and that close marks the node offline for the moment
        // before the new socket answers. On a relaunch offline is the REST answer, and it holds.
        if (!pending.afterLink) _dropPending();
        return;
      case PhoneMachineStatus.connecting:
        return;
      case PhoneMachineStatus.ready:
        break;
    }
    switch (machine.agentLoadStatus) {
      case AgentLoadStatus.loaded:
        break;
      case AgentLoadStatus.error:
        return _dropPending();
      case AgentLoadStatus.idle ||
          AgentLoadStatus.loading ||
          AgentLoadStatus.needsLink:
        return;
    }
    // Something already open on the Agents tab was opened by the person; it is not covered over.
    if (_navigators[PhoneTab.agents]?.currentState?.canPop() ?? false) {
      _landed = true;
      return _dropPending();
    }
    // The same order the list draws, so the pager swipes to the neighbours the person would see —
    // and "first agent" means the first row of that machine, not the first one it reported.
    final entries = visibleAgents(agentIndex(notifier));
    final target = entries
        .where(
          (entry) =>
              entry.machineId == pending.machineId &&
              entry.agent.terminalAvailable &&
              (pending.agentId == null || entry.agent.id == pending.agentId),
        )
        .firstOrNull;
    if (target == null) {
      // A machine with no agents yet, or a remembered agent since deleted: the list is the answer.
      return _dropPending();
    }
    _landed = true;
    _pending = null;
    _pendingDeadline?.cancel();
    _pendingDeadline = null;
    // After the frame: this runs inside the notifier's notify, which can land mid-build, and a push
    // there trips the navigator's lock.
    _afterFrame(() {
      final navigator = _navigators[PhoneTab.agents]?.currentState;
      if (navigator == null) return;
      setState(() => _tab = PhoneTab.agents);
      openAgentPager(navigator.context, notifier, entries, target);
      _syncCanPop();
    });
  }

  /// Machines, once no machine on the account has answered and none is still trying.
  ///
  /// Waits on a machine that is connecting: whether it needs a password is only learned by dialling
  /// it, so a phone that IS linked reads exactly like one that is not for the first second or two.
  /// An empty account decides nothing either — until the list arrives, empty is indistinguishable
  /// from not loaded.
  // ignore: unused_element
  void _decideLanding() {
    if (_landed || _readingLastAgent) return;
    final notifier = widget.notifier;
    if (notifier.machines.isEmpty) return;
    for (final machine in notifier.machines) {
      final state = notifier.stateOf(machine.machineId);
      if (state == null) return;
      switch (phoneMachineStatusOf(state)) {
        case PhoneMachineStatus.ready:
          _landed = true;
          return;
        case PhoneMachineStatus.connecting:
          return;
        case PhoneMachineStatus.needsPassword || PhoneMachineStatus.offline:
          continue;
      }
    }
    _landed = true;
    _afterFrame(() {
      setState(() {
        _tab = PhoneTab.machines;
        _tabCanPop =
            _navigators[PhoneTab.machines]?.currentState?.canPop() ?? false;
      });
    });
  }

  // ignore: unused_element
  void _afterFrame(VoidCallback action) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) action();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // ── End of the kept-but-dead landing rules ────────────────────────────────────────────────────

  /// Back in the foreground: a p2p retry waiting out its delay fires now, and so does every machine
  /// socket the phone lost while it was away. Going to the background needs nothing — the OS
  /// suspends the socket, and the redial tears the old wire down and negotiates a fresh one.
  ///
  /// ⚠️ The two used to be one line, and the missing half showed. P2P was kicked here from the
  /// start; the WebSocket underneath it was not, so a phone coming back sat through a backoff that
  /// had already climbed to its 30s ceiling — the machine list saying "Connecting…" at somebody
  /// who was looking straight at it, with a network that would have answered at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    phoneTerminalP2p.kickRetry();
    widget.notifier.handleAppResumed();
  }

  NavigatorState? get _currentNavigator => _navigators[_tab]?.currentState;

  void _select(PhoneTab tab) {
    if (tab == _tab) {
      // A second tap on the tab you are already on pops that tab back to its root — the phone
      // convention, and the only way back out of a deep stack without walking every page.
      _currentNavigator?.popUntil((route) => route.isFirst);
      _syncCanPop();
      return;
    }
    // The new tab has a depth of its own, so the back gesture's answer changes with it.
    setState(() {
      _tab = tab;
      _tabCanPop = _navigators[tab]?.currentState?.canPop() ?? false;
    });
  }

  Widget _rootFor(PhoneTab tab) => switch (tab) {
    PhoneTab.agents => AgentHome(
      notifier: widget.notifier,
      openMachineId: _linkedMachineId,
    ),
    PhoneTab.machines => MachinesTab(notifier: widget.notifier),
    PhoneTab.settings => SettingsPage(notifier: widget.notifier),
  };

  /// Whether the tab on screen has a page to go back to — what [PopScope] is given.
  ///
  /// Kept as state rather than read inline in `build`, because a push or pop inside a nested
  /// [Navigator] does not rebuild this widget: the flag has to be pushed here by the notification
  /// below, or `canPop` would answer with whatever was true when the shell last happened to build.
  bool _tabCanPop = false;

  /// Android's back button, handled per tab.
  ///
  /// ⚠️ Deliberately NOT `NavigatorPopHandler`, which is what a single-stack phone shell would
  /// use. It tracks one `canPop` flag fed by `NavigationNotification`s bubbling out of its
  /// subtree — and an [IndexedStack] keeps all three navigators MOUNTED and notifying, so the flag
  /// ends up reflecting whichever tab spoke last rather than the one on screen. A back press on a
  /// root Agents tab would then be swallowed because Settings happened to be two pages deep.
  ///
  /// So the notification is used only as a SIGNAL that some stack moved, and the answer is then
  /// read from the current tab's navigator — the one stack the person is actually looking at.
  bool _onNavigation(NavigationNotification notification) {
    _syncCanPop();
    // Let it keep bubbling: the root navigator above this shell tracks its own state from it.
    return false;
  }

  void _syncCanPop() {
    final next = _currentNavigator?.canPop() ?? false;
    if (next == _tabCanPop) return;
    // The notification arrives mid-build of the subtree that sent it, so defer rather than calling
    // setState inside another widget's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _currentNavigator?.canPop() ?? false;
      if (current == _tabCanPop) return;
      setState(() => _tabCanPop = current);
    });
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    _currentNavigator?.maybePop().then((_) {
      if (mounted) _syncCanPop();
    });
  }

  @override
  Widget build(BuildContext context) => PhoneShellScope(
    onMachineLinked: _followLinkedMachine,
    child: ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) => PopScope<Object?>(
        // False while this tab has somewhere to go back to, so the gesture reaches [_handleBack]
        // instead of leaving the app. True at a tab's root: the press then belongs to the system.
        canPop: !_tabCanPop,
        onPopInvokedWithResult: _handleBack,
        child: NotificationListener<NavigationNotification>(
          onNotification: _onNavigation,
          child: Scaffold(
            body: IndexedStack(
              index: PhoneTab.values.indexOf(_tab),
              sizing: StackFit.expand,
              children: [
                for (final tab in PhoneTab.values)
                  // ⚠️ Each tab's navigator needs its OWN HeroController, and without this the
                  // engine-mark flights simply never happen — silently, with no error.
                  //
                  // `MaterialApp` installs one controller for the ROOT navigator only; a nested
                  // `Navigator` inherits nothing, so its routes have no observer to drive a flight.
                  // One shared controller is not the fix either — `navigator.dart` on
                  // `HeroControllerScope`: "The hero controller ... can only subscribe to one
                  // navigator", and these three are all mounted at once inside the IndexedStack.
                  HeroControllerScope(
                    controller: _heroControllers[tab]!,
                    child: Navigator(
                      key: _navigators[tab],
                      // ⚠️ The controller goes in the SCOPE ONLY, never also in `observers`.
                      // `NavigatorState._updateEffectiveObservers` appends the scope's controller to
                      // `widget.observers` itself, so listing it here registers it twice and trips
                      // "A HeroController can not be shared by multiple Navigators" — which reads
                      // like a sharing bug and is really a double-subscription by one navigator.
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => _rootFor(tab),
                      ),
                    ),
                  ),
              ],
            ),
            // ⚠️ Hidden, not removed. The terminal is the screen the phone
            // opens on, and the three-tab bar under it is on its way out — but
            // the tabs themselves still carry the whole app: every page here is
            // rooted in one of them, [_select] is what pops a tab back and
            // keeps its stack, and the landing rules above still choose between
            // them. Deleting the bar would take all of that with it.
            //
            // So the shell is unchanged and only the bar is not drawn. Flip
            // [_showTabBar] to bring it straight back, and everything below is
            // still wired to it.
            bottomNavigationBar: !_showTabBar
                ? null
                : PhoneTabBar(
                    current: _tab,
                    onSelect: _select,
                    waitingCount: waitingAgents(agentIndex(widget.notifier))
                        .length,
                  ),
          ),
        ),
      ),
    ),
  );
}
