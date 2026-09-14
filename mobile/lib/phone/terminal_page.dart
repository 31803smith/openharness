import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness/shared/theme/app_theme.dart';
import 'package:harness/shared/widgets/app_icon_button.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/engine_identity.dart';
import 'package:harness/widgets/rename_agent_dialog.dart';
import 'package:harness/widgets/terminal_panel.dart';

import 'phone_header.dart';
import 'phone_sheet.dart';
import 'phone_status.dart';
import 'status_pill.dart';

/// One agent's terminal, filling the phone. The header says whose it is and whether it is live;
/// everything below it is the same [TerminalPanel] a desktop tile draws, minus that tile's own
/// header.
///
/// A pushed page, so the tab bar is covered: the bottom of this screen belongs to the composer, and
/// a nav bar under it would put two rows of chrome in the thumb's way.
class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.agentId,
    this.isActive = true,
  });

  final AppNotifier notifier;
  final String machineId;
  final String agentId;

  /// Whether this is the page being LOOKED AT, rather than one parked beside it in the pager.
  ///
  /// ⚠️ **Load-bearing for correctness, not just for tidiness.** [TerminalPanel] claims the keyboard
  /// whenever it is built focused — `requestKeyboard()` reopens the input connection on purpose — so
  /// two mounted pages both passing `focused: true` race for the software keyboard, and the winner
  /// can be the page off-screen. What gets typed then reaches an agent nobody is looking at.
  ///
  /// It also drives the panel's `visible`, which is what releases focus and stops the renderer and
  /// the auto-resize for a page that has slid away — three terminals all resizing themselves to the
  /// layout would send SIGWINCH to three remote shells at once.
  final bool isActive;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  /// Whether this page's pane ever existed.
  ///
  /// ⚠️ Load-bearing, and the reason this page is stateful at all. The page is pushed BEFORE the
  /// attach — that is what lets it say "Attaching…" — so a null pane means two opposite things
  /// depending on when it is seen: not yet (wait) or no longer (leave).
  ///
  /// Without the distinction, the second case renders as a spinner that never resolves. It is
  /// reachable in normal use now that two tabs can each open a terminal: `openAgent` keeps exactly
  /// one pane, so opening an agent from the Machines tab closes the pane belonging to a
  /// TerminalPage still sitting in the Agents tab's stack.
  bool _hadPane = false;

  /// Whether this page has already used its one chance to summon the keyboard.
  ///
  /// It starts `false`, so the terminal is focused on arrival and the keyboard
  /// rises by itself. It flips the moment the keyboard IS up, and NEVER goes
  /// back: from then on `TerminalPanel` is passed `focused: false` and stops
  /// claiming, for the life of the page. Bringing the keyboard back is the
  /// terminal's own job — xterm's tap handler calls `requestKeyboard()` without
  /// consulting this flag, so nothing here needs to re-arm.
  ///
  /// ⚠️ Without this, Back could not put the keyboard away at all:
  /// `TerminalPanel._claimFocus` calls `TerminalView.requestKeyboard()`, which
  /// RE-TAKES focus when it finds none, so the keyboard returned a frame after
  /// the system dismissed it. Measured on a Pixel 8 Pro — `onRequestShow`
  /// ELEVEN times against a single `onRequestHide`.
  ///
  /// ⚠️ It flips on the keyboard APPEARING, not on it going away, and that is
  /// the difference between Back working on the first press and on the second.
  /// `_claimFocus` runs from a post-frame callback and BEATS `didChangeMetrics`
  /// to the news that the keyboard is gone:
  ///
  ///     onDispatched            keyboard hidden
  ///     CLAIM focused=true      claim ran first — re-took focus
  ///     onRequestShow           keyboard on its way back
  ///     KB raw=0.0              our metrics callback, one beat too late
  ///
  /// Arming on the way up removes the race: by the time any Back arrives,
  /// claiming has been off for as long as the keyboard has been visible.
  bool _claimSpent = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Watches the keyboard through [View], because MediaQuery lies to this page.
  ///
  /// ⚠️ `MediaQuery.viewInsetsOf(context).bottom` is ALWAYS ZERO here, keyboard
  /// up or down. `PhoneShell` puts this page's Navigator inside a `Scaffold`
  /// body, and a Scaffold that has already resized for the keyboard STRIPS the
  /// bottom inset from the MediaQuery it hands its body — the body must not
  /// subtract it twice. Every descendant therefore reads zero.
  ///
  /// [View.of] is the raw platform value, in PHYSICAL pixels, and no widget can
  /// intercept it.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    // The FIRST frame of the keyboard rising is enough — it need not finish.
    // Spending the claim this early is the point: it is off long before any
    // Back press can arrive.
    if (View.of(context).viewInsets.bottom > 0 && !_claimSpent) {
      setState(() => _claimSpent = true);
    }
  }

  /// The composer starts OPEN here, and the phone owns that answer rather than the pane.
  ///
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        AppTheme.watch(context);
        final pane = widget.notifier.panes
            .where(
              (p) =>
                  p.machineId == widget.machineId &&
                  p.agentId == widget.agentId,
            )
            .firstOrNull;
        if (pane != null) {
          _hadPane = true;
        } else if (_hadPane && widget.isActive) {
          // The pane this page was showing is gone — another tab opened a different agent, or the
          // agent was deleted. Leave rather than spin: there is nothing here to come back.
          //
          // ⚠️ Only the ACTIVE page may leave, and only it ever should. A page parked beside the one
          // being read shares the route, so popping from there would take the whole pager down —
          // including the terminal actually on screen. A parked page whose pane went away simply
          // waits: swiping to it is what makes it attach again.
          _leave();
        }
        final session = pane?.session;
        final machine = widget.notifier.stateOf(widget.machineId);
        final agent = machine?.agents
            .where((a) => a.id == widget.agentId)
            .firstOrNull;
        final status = phoneSessionSummary(session);
        final reclaim = phoneReclaimAction(session);
        return Scaffold(
          backgroundColor: AppPalette.windowBg,
          // ⚠️ Plain `SafeArea`. A `bottom: !keyboardUp` toggle was here,
          // computed from `MediaQuery.viewInsetsOf(context).bottom > 0` — and
          // that value is pinned at ZERO inside this page (see
          // [didChangeMetrics]). The toggle therefore never toggled.
          body: SafeArea(
            child: Column(
              children: [
                PhoneHeader(
                  title: agent?.name ?? 'Agent',
                  leading: EngineMark(
                    engine: agent?.engine,
                    displayName: agent?.engineDisplayName,
                    size: 22,
                  ),
                  subtitle: StatusPill(
                    fontSize: 12,
                    summary: (
                      // The machine alone once the button beside it is saying
                      // the state: two words for one fact, in a row this
                      // narrow, is what truncated "Taken over" to "Ta…".
                      label: reclaim == null
                          ? '${machine?.machine.displayName ?? ''} · ${status.label}'
                          : machine?.machine.displayName ?? '',
                      tone: status.tone,
                    ),
                  ),
                  trailing: [
                    // Read-only is a state to get OUT of, so its way out is a
                    // labelled button in the header rather than a line in the
                    // actions sheet: the sheet is where you go having decided
                    // to do something, and this is the thing telling you that
                    // typing will go nowhere until you do.
                    if (reclaim != null)
                      _ReclaimButton(
                        action: reclaim,
                        onPressed: () => widget.notifier.selectAgent(
                          widget.machineId,
                          widget.agentId,
                        ),
                      ),
                    // Null while the agent is not loaded: there is nothing to act on yet, and a
                    // menu of actions that all fail is worse than no menu.
                    if (agent != null)
                      AppIconButton(
                        icon: LucideIcons.ellipsis300,
                        size: 20,
                        tooltip: 'Agent actions',
                        color: AppPalette.textSecondary,
                        onPressed: () => _showActions(
                          machineName: machine?.machine.displayName ?? '',
                          agentName: agent.name,
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: Column(
                    children: [
                      Divider(height: 1, color: AppGlass.hair),
                      Expanded(
                        child: pane == null || session == null
                            ? const _Attaching()
                            // ⚠️ Nothing re-arms [_claimSpent] on tap, and that
                            // is deliberate. A `Listener` doing so was written
                            // and removed: xterm's own `_onTapDown` already
                            // calls `requestKeyboard()`, so the tap opened the
                            // keyboard and THEN the re-armed claim asked for it
                            // a second time — Android answers a show arriving
                            // mid-animation by cancelling and restarting it.
                            // Measured: two `onRequestShow` and two
                            // `onCancelled at PHASE_CLIENT_APPLY_ANIMATION` per
                            // tap. The claim exists only to raise the keyboard
                            // on arrival; after that the terminal handles it.
                            : TerminalPanel(
                                key: ValueKey(pane.id),
                                notifier: widget.notifier,
                                session: session,
                                // Only the page on screen takes the keyboard — see
                                // [TerminalPage.isActive]. `visible` is the same answer for the
                                // panel's other half: a page parked beside this one releases
                                // focus, stops rendering and stops resizing its remote shell.
                                //
                                // AND only until the keyboard is actually up —
                                // see [_claimSpent]. Both gates, not either:
                                // `isActive` keeps a parked page from stealing
                                // the keyboard, `_claimSpent` keeps this one
                                // from taking it back after Back.
                                focused: widget.isActive && !_claimSpent,
                                visible: widget.isActive,
                                showHeader: false,
                                // No composer, and so no grip above it: the
                                // page hands the pane its full height and the
                                // software keyboard drives the terminal
                                // directly — `TerminalPanel` autofocuses the
                                // view precisely when no box is covering it.
                                // What goes with the box is the batched send,
                                // and the Esc/Tab/Ctrl an on-screen keyboard
                                // never had anyway.
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Pops after the frame: this runs from inside a build, where popping a route synchronously is
  /// not allowed.
  void _leave() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    });
  }

  void _showActions({required String machineName, required String agentName}) {
    showPhoneSheet(
      context,
      title: '$agentName · $machineName',
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.pencil300,
          label: 'Rename agent…',
          onTap: () => showAgentRenameDialog(
            context,
            widget.notifier,
            widget.machineId,
            widget.agentId,
            agentName,
          ),
        ),
        PhoneSheetAction(
          icon: LucideIcons.refreshCw300,
          label: 'Restart agent',
          onTap: () => unawaited(_restart()),
        ),
      ],
    );
  }

  /// Restarting is a round trip that can fail, and the phone has no status rail to fail into — so
  /// the answer lands as a snackbar, which is the one surface a pushed page here always has.
  Future<void> _restart() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await widget.notifier.restartAgent(
      widget.machineId,
      widget.agentId,
    );
    final error = result.error;
    if (error == null || messenger == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }
}

/// The header's way back into a session this device is not driving.
///
/// Re-selecting the agent is what reclaims it — the same call the desktop tile's
/// status chip makes, so one gesture means one thing on both.
class _ReclaimButton extends StatelessWidget {
  const _ReclaimButton({required this.action, required this.onPressed});

  final PhoneSummary action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final color = phoneToneColor(action.tone);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        action.tone == PhoneTone.attention
            ? LucideIcons.lock300
            : LucideIcons.refreshCw300,
        size: 15,
      ),
      label: Text(
        action.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
  }
}

class _Attaching extends StatelessWidget {
  const _Attaching();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppPalette.accent,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Attaching to the agent…',
          style: TextStyle(color: AppPalette.textSecondary, fontSize: 14),
        ),
      ],
    ),
  );
}
