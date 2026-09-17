import 'dart:async';

import 'package:flutter/material.dart';
// `PlatformException` — a refused camera permission arrives as one, and it is
// the one picker failure with something the person can do about it.
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/app_icon_button.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/terminal/image_transcode.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';
import 'package:harness_mobile/widgets/rename_agent_dialog.dart';
import 'package:harness_mobile/widgets/terminal_panel.dart';

import 'agents_page.dart' show openNewAgent;
import 'delete_agent.dart';
import 'phone_header.dart';
import 'phone_search_page.dart' show openPhoneSearch;
import 'phone_sheet.dart';
import 'phone_status.dart';
import 'status_pill.dart';
import 'terminal_input_dock.dart';
import 'voice_input_controller.dart';

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
    required this.voice,
    this.isActive = true,
  });

  final AppNotifier notifier;
  final String machineId;
  final String agentId;

  /// Voice input, shared by every page of the pager this page is in — see
  /// [VoiceInputController] for why it is not this page's own.
  final VoiceInputController voice;

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

/// Whether the software keyboard is up, as one fact rather than as a flag each
/// page keeps for itself.
///
/// ⚠️ Per-page state cannot answer the question the pager asks. Swiping to the
/// next agent while typing must HOLD the keyboard — the outgoing page releases
/// focus, and unless the incoming one takes it in the same frame the platform
/// closes the keyboard — and a page built while the keyboard was down, then
/// swiped to after it rose, never watched it rise. Whether the keyboard is up is
/// a property of the SCREEN, not of any one page, so it is kept once here.
///
/// Written by every mounted page's `didChangeMetrics` — they all see the same
/// inset, so they all write the same value.
bool _keyboardIsUp = false;

/// Forgets what the keyboard did during the last run of terminal pages.
///
/// Called when a pager opens. A pager popped with the keyboard up is disposed
/// before the inset falls, so no page is left to see it fall — and the next
/// pager would otherwise open believing the keyboard is up, and summon it.
void resetKeyboardSession() {
  _keyboardIsUp = false;
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

  /// Whether the Keyboard button in voice input has asked for the keyboard,
  /// and it has not risen yet.
  ///
  /// What makes [TerminalPanel] claim focus at all: arriving on a page raises
  /// nothing, and a tap on the terminal opens voice input, so this is the one
  /// way the keyboard is SUMMONED. Spent the moment the keyboard is up — from
  /// then on [_keyboardIsUp] holds it — so Back or `⌄` can put it away without
  /// a claim fetching it straight back.
  ///
  /// It stays set when no inset ever arrives, which is what a hardware keyboard
  /// looks like: the terminal keeps its focus, and the key bar stays for `esc`.
  bool _keyboardRequested = false;

  /// Whether the software keyboard is up, and with it [TerminalKeyBar].
  ///
  /// Read from [View] for the reason [didChangeMetrics] gives: MediaQuery's
  /// bottom inset is pinned at zero inside this page.
  bool _keyboardUp = false;

  /// Whether the keyboard is mid-animation, and so the pane's height is still
  /// changing frame by frame. Handed to [TerminalPanel.settling], which freezes
  /// the renderer and the auto-resize until this clears.
  bool _keyboardSettling = false;

  /// The last bottom inset seen, in physical pixels, and the timer that decides
  /// the animation has stopped.
  ///
  /// The platform gives no "keyboard animation finished" callback on either OS —
  /// only a stream of [didChangeMetrics] ticks — so the end is detected by the
  /// inset going quiet. The window is a little longer than one frame at 60Hz so
  /// a slow frame mid-animation does not read as the end of it.
  double? _lastInset;
  Timer? _settleTimer;
  static const _settleWindow = Duration(milliseconds: 80);

  /// Stops the settle watch, leaving the renderer live.
  ///
  /// ⚠️ Called from [dispose], so it must not touch [setState].
  void _cancelSettle() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _lastInset = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Releases the freeze when this page is parked mid-animation.
  ///
  /// A settle that never ends would otherwise be waiting on [didChangeMetrics]
  /// ticks that only the page ON SCREEN gets, and the pane would come back from
  /// the pager with its renderer still gated.
  @override
  void didUpdateWidget(TerminalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      // A keyboard asked for and still on its way belongs to the page that
      // asked; a parked page must not claim it when it comes.
      _keyboardRequested = false;
      _cancelSettle();
      if (_keyboardSettling) setState(() => _keyboardSettling = false);
    }
  }

  @override
  void dispose() {
    _cancelSettle();
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
    final inset = View.of(context).viewInsets.bottom;
    final up = inset > 0;
    // Every mounted page writes it, and they all see the same inset — so a page
    // that was parked while the keyboard came and went still reads the truth.
    _keyboardIsUp = up;
    // The FIRST frame of the keyboard rising spends the request — it need not
    // finish. Spending it this early is the point: it is off long before any
    // Back press can arrive.
    final requested = _keyboardRequested && !up;
    // One input at a time. Whatever raised the keyboard, voice input yields.
    if (up && widget.voice.isOpen) widget.voice.close();

    // Every tick that MOVES the inset is the animation still running; the run
    // ends when one window passes without another move. Gated on a real change
    // so the ticks this page gets for everything else — a rotation, a status
    // bar resizing — never freeze a pane whose height is not moving.
    //
    // The very first tick is deliberately not a move: `_lastInset` starts null
    // and only seeds the baseline, so arriving on this page cannot begin a
    // settle of its own.
    final previous = _lastInset;
    _lastInset = inset;
    if (previous != null && inset != previous) {
      _settleTimer?.cancel();
      _settleTimer = Timer(_settleWindow, () {
        _settleTimer = null;
        if (!mounted || !_keyboardSettling) return;
        setState(() => _keyboardSettling = false);
      });
    }

    final settling = _settleTimer != null;
    if (up == _keyboardUp &&
        requested == _keyboardRequested &&
        settling == _keyboardSettling) {
      return;
    }
    setState(() {
      _keyboardUp = up;
      _keyboardRequested = requested;
      _keyboardSettling = settling;
    });
  }

  /// Whether [TerminalPanel] should hold the input connection: while the
  /// keyboard is up, and while one is on its way — see [_keyboardRequested].
  ///
  /// ⚠️ Holding reads [_keyboardIsUp], the one screen-wide fact, rather than
  /// anything this page remembers — see that flag for why swiping needs it.
  bool get _shouldFocus =>
      widget.isActive && (_keyboardIsUp || _keyboardRequested);

  /// A tap on the terminal while no keyboard is up or coming: voice input,
  /// waiting on its mic button. Null while the keyboard is, so the tap is
  /// xterm's and the keyboard stays.
  VoidCallback? get _onInputTap => _shouldFocus ? null : widget.voice.open;

  /// The Keyboard button in voice input. What was heard is typed into the
  /// prompt rather than dropped, so the keyboard picks up where the voice left
  /// off — to correct a word, or to finish the sentence. A take still being
  /// recorded is transcribed first: pressing Keyboard mid-sentence is asking to
  /// fix that sentence, not to lose it.
  Future<void> _useKeyboard(TerminalSession session) async {
    final heard = await widget.voice.takeTranscript();
    if (!mounted) return;
    widget.voice.close();
    if (heard.isNotEmpty && session.acceptsInput) {
      session.terminal.textInput(heard);
    }
    setState(() => _keyboardRequested = true);
  }

  /// Puts away whichever input is up without leaving the page — the `⌄` key on
  /// [TerminalKeyBar]. Dropping focus is what closes the input connection.
  void _dismissInput() {
    widget.voice.close();
    FocusManager.instance.primaryFocus?.unfocus();
    if (_keyboardRequested) setState(() => _keyboardRequested = false);
  }

  /// Whether an input on screen is THIS page's — the keyboard, or voice input
  /// in its place — the question the machine row at the foot of the page asks,
  /// which [_keyboardUp] alone answers wrongly.
  ///
  /// Voice input counts for the same reason the keyboard does: the panel takes
  /// the keyboard's place, and a status line under it is a row the terminal
  /// loses while someone is talking to the agent.
  ///
  /// ⚠️ [_keyboardUp] means "an inset exists", not "this page raised it". A
  /// pushed page with a text field — search, rename — raises one of its own,
  /// and this page is still mounted underneath, still gets `didChangeMetrics`,
  /// and so still records the keyboard as up. It then stops receiving ticks
  /// once it is no longer the route being laid out, so the fall back to zero
  /// after that page closes never reaches it: the flag stays true forever and
  /// the row it hides never comes back.
  ///
  /// [ModalRoute.isCurrent] is what separates the two. False while anything is
  /// stacked above, so an inset belonging to that page is not read as this
  /// one's — and true again the moment it pops, whatever the stale flag says.
  ///
  /// Not used for [_shouldFocus] or for the key bar: those are about the
  /// keyboard ITSELF, which is screen-wide, and a covered page must keep
  /// tracking it to know what to do when it is uncovered.
  bool get _ownsInput =>
      (_keyboardUp || widget.voice.isOpen) &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  /// Guards against a second picker while one is already up.
  ///
  /// The key bar stays on screen under the sheet the OS puts over it, so its
  /// button remains tappable — and `pickImage` answers a second call on iOS by
  /// throwing rather than by queueing.
  bool _picking = false;

  /// Picks a picture and sends it to the agent, re-encoded on the way.
  ///
  /// ⚠️ **The transcode is not an optimisation, it is what makes the picture
  /// arrive at all** — see `transcodeToPng`. Everything past this point names
  /// PNG: the binary kind, the file the CLI writes, and the three OS clipboard
  /// writers it hands the bytes to. A phone produces JPEG and HEIC.
  Future<void> _sendImage(TerminalSession session, ImageSource source) async {
    if (_picking || !session.acceptsInput) return;
    _picking = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    void report(String message) {
      if (mounted) messenger?.showSnackBar(SnackBar(content: Text(message)));
    }

    try {
      final XFile? picked;
      try {
        picked = await ImagePicker().pickImage(source: source);
      } on PlatformException catch (error) {
        // A refused camera permission lands here rather than as a null, and it
        // is the one failure somebody can do something about.
        report(
          error.code == 'camera_access_denied'
              ? 'Allow camera access in Settings to send a photo.'
              : 'Could not open the picker.',
        );
        return;
      }
      // Null is a CANCEL, not a failure: the person backed out of the sheet, and
      // a snackbar saying so would be noise over a deliberate act.
      if (picked == null) return;

      final result = await transcodeToPng(await picked.readAsBytes());
      switch (result) {
        case ImageTranscodeUnreadable():
          report("That file isn't an image this phone can read.");
        case ImageTranscodeTooLarge():
          report('That image is too large to send, even scaled down.');
        case ImageTranscodeOk(:final pngBytes):
          // Re-checked AFTER the picker, which the person may have had open for
          // a while: the stream can have been taken over or dropped since, and
          // `pasteImage` on a dead stream goes nowhere silently.
          if (!session.acceptsInput) {
            report('The terminal is no longer accepting input.');
            return;
          }
          if (!await session.pasteImage(pngBytes)) {
            report('The image could not be sent.');
          }
      }
    } finally {
      _picking = false;
    }
  }

  /// The composer starts OPEN here, and the phone owns that answer rather than the pane.
  ///
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // The panel opening or closing hides or shows the machine row — see
      // [_ownsInput]. Its open STATE only: what it hears repaints the panel.
      listenable: Listenable.merge([widget.notifier, widget.voice.openState]),
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
          // ⚠️ No fab. New agent is the `+` in the header — see the note there.
          // A Scaffold fab floats over the body, and the body here is the
          // terminal: it covered the newest line of output, which on a page
          // that streams is the line being read.
          // ⚠️ Plain `SafeArea`. A `bottom: !keyboardUp` toggle was here,
          // computed from `MediaQuery.viewInsetsOf(context).bottom > 0` — and
          // that value is pinned at ZERO inside this page (see
          // [didChangeMetrics]). The toggle therefore never toggled.
          body: SafeArea(
            child: Column(
              children: [
                PhoneHeader(
                  title: _clipTitle(agent?.name ?? 'Agent'),
                  leading: EngineMark(
                    engine: agent?.engine,
                    displayName: agent?.engineDisplayName,
                    size: 22,
                  ),
                  // ⚠️ No subtitle. The machine and its state moved to
                  // [_MachineBar] at the foot of the page — see there for why.
                  // A header carrying both a name and a status line spent two
                  // rows on identity and left the filename, the one thing that
                  // says WHICH agent this is, sharing its row with four
                  // controls and ellipsing halfway through.
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
                    // New agent, search and the actions menu: the three the
                    // page offers, in the order they are reached for — create,
                    // find, then everything else.
                    //
                    // ⚠️ They are spaced by [_HeaderAction], not drawn bare.
                    // [AppIconButton] is a fixed 24px box whatever glyph size
                    // it is given, so a 22px search glyph fills its box edge to
                    // edge while a 20px ellipsis sits inside one — three
                    // buttons butted together then read as unevenly spaced
                    // when the gaps are in fact identical. One glyph size and
                    // one padding across the three is what evens the rhythm.
                    //
                    // ⚠️ `+` here rather than floating over the terminal. A fab
                    // covers the last line of output — the line being read —
                    // and this page has no list to scroll it clear of.
                    //
                    // Gated on the machine ANSWERING, the same gate the Agents
                    // tab puts on its fab: creating needs the machine to list
                    // its folders and name its engines, so one that is offline
                    // or still wants its password cannot host a new agent.
                    if (machine != null &&
                        phoneMachineStatusOf(machine) ==
                            PhoneMachineStatus.ready)
                      _HeaderAction(
                        icon: LucideIcons.plus300,
                        size: 21,
                        tooltip: 'New agent',
                        // Awaited for the same reason search is: the form may
                        // be backed out of rather than completed, and this page
                        // gets no rebuild when it lands back on top.
                        onPressed: () async {
                          await openNewAgent(
                            context,
                            widget.notifier,
                            widget.machineId,
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                    // Search is here because this page is where the phone now
                    // opens, so what the list screens offered has to be
                    // reachable without going back to them first:
                    // [openPhoneSearch] is the same search that spans agents
                    // and machines.
                    //
                    // ⚠️ Shown while the keyboard is up, and so is `+`. Both
                    // were once hidden on `!_ownsInput`, to spare a one-row
                    // header while typing — but the row is not what was short.
                    // The title ellipses at the same width either way, so
                    // hiding them bought the title nothing and only left a gap,
                    // while the header's controls jumped position on every
                    // keyboard raise. A header that holds still is worth more
                    // than two columns of unused space.
                    //
                    // ⚠️ Not [PhoneSearchButton], which pushes and forgets. A
                    // page that pops back onto the top gets no rebuild of its
                    // own, so anything read from [_ownsInput] — the machine
                    // bar below still does — would keep answering with what was
                    // true while the search was covering it. Awaiting the push
                    // is what turns "the search closed" into a frame.
                    _HeaderAction(
                      icon: LucideIcons.search300,
                      size: 21,
                      tooltip: 'Search',
                      onPressed: () async {
                        await openPhoneSearch(context, widget.notifier);
                        if (mounted) setState(() {});
                      },
                    ),
                    // Null while the agent is not loaded: there is nothing to act on yet, and a
                    // menu of actions that all fail is worse than no menu.
                    if (agent != null)
                      _HeaderAction(
                        icon: LucideIcons.ellipsis300,
                        size: 21,
                        tooltip: 'Agent actions',
                        // Last in the row, so its padding stops at the header's
                        // own right inset rather than adding to it.
                        last: true,
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
                            : TerminalPanel(
                                key: ValueKey(pane.id),
                                notifier: widget.notifier,
                                session: session,
                                // Only the page on screen takes the keyboard — see
                                // [TerminalPage.isActive]. `visible` is the same answer for the
                                // panel's other half: a page parked beside this one releases
                                // focus, stops rendering and stops resizing its remote shell.
                                //
                                // Whether it also HOLDS one that is already
                                // up is a separate question, and the pager asks
                                // it on every swipe — see [_shouldFocus].
                                focused: _shouldFocus,
                                visible: widget.isActive,
                                // Hold the renderer still while the keyboard
                                // slides. Separate from `visible` because this
                                // must NOT release focus — the animation being
                                // waited on is the one that focus started.
                                settling: _keyboardSettling,
                                // ⚠️ The tap is taken in the panel, not by a
                                // `Listener` over it. xterm's own `_onTapDown`
                                // calls `requestKeyboard()`, so anything that
                                // merely ALSO reacted to the tap would get the
                                // keyboard rising under voice input — and a
                                // re-armed claim on top of it was measured
                                // asking Android twice per tap, which answers a
                                // show mid-animation by cancelling and
                                // restarting it.
                                onInputTap: _onInputTap,
                                showHeader: false,
                                // No composer, and so no grip above it: the
                                // page hands the pane its full height and the
                                // software keyboard drives the terminal
                                // directly. Voice input's Send is what kept
                                // the composer's batched turn.
                              ),
                      ),
                      // The bottom of this page IS just above the keyboard:
                      // `PhoneShell`'s Scaffold has already resized for it —
                      // the same resize that empties this page's MediaQuery
                      // insets (see [didChangeMetrics]).
                      if (session != null)
                        TerminalInputDock(
                          session: session,
                          voice: widget.voice,
                          keyboardUp: _keyboardUp || _keyboardRequested,
                          onDismiss: _dismissInput,
                          onUseKeyboard: () => unawaited(_useKeyboard(session)),
                          // Only where the far side can actually take one: an
                          // older CLI never advertises the binary kind, so the
                          // upload would go nowhere silently. Null leaves the
                          // buttons undrawn rather than drawn dead.
                          onPickImage:
                              machine?.terminalImagePasteAvailable == true
                              ? () => unawaited(
                                  _sendImage(session, ImageSource.gallery),
                                )
                              : null,
                          onTakePhoto:
                              machine?.terminalImagePasteAvailable == true
                              ? () => unawaited(
                                  _sendImage(session, ImageSource.camera),
                                )
                              : null,
                        ),
                      // Which computer this is running on, and whether it is
                      // still answering — the pair that used to sit under the
                      // filename in the header.
                      //
                      // ⚠️ Below the key bar, not above it. The bar is what the
                      // thumb works, and a line that moves every time it
                      // appears would shift the keys under it. Here it is the
                      // last row on the page and nothing it does moves
                      // anything above it.
                      //
                      // ⚠️ Hidden while this page owns the keyboard, the same
                      // gate the header controls take. The key bar is already
                      // tall, and a status line wedged under it is a row of
                      // chrome the terminal loses for nothing — state is not
                      // what is being read mid-typing.
                      if (!_ownsInput)
                        _MachineBar(
                          name: machine?.machine.displayName ?? '',
                          // ⚠️ The machine ALONE once the reclaim button is up.
                          // The two say the same fact in different words —
                          // "Taken over" here against "Take control" there,
                          // "Disconnected" against "Reconnect" — and a page
                          // stating its problem twice reads as two problems.
                          // The button wins because it is the way out of the
                          // state, not just a report of it. Same rule the
                          // header's subtitle followed before this row took
                          // the pair over.
                          status: reclaim == null ? status : null,
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
  ///
  /// ⚠️ **Removes THIS page's route, which is not the same as popping.** `pop` takes whatever is on
  /// top, and this page is often not on top when its pane goes: the terminal's own `+` opens the
  /// new-agent form over it, and the agent that form creates is opened as the single pane — closing
  /// this one. Popping from here then took down the NEW agent's terminal, the page underneath
  /// surfaced, found its pane gone too and popped again, and the person landed on the list instead
  /// of in the agent they had just made.
  ///
  /// ⚠️ **Does nothing at all on the home screen, and that is correct rather than a gap.** The
  /// terminal is the root of its stack there ([AgentHome]), so `canPop` is false and the guard below
  /// returns — but the reason this is called is that the agent went away, and [AgentHome] watches
  /// the same agent list: the agent leaves it, the home screen's target stops matching, and it
  /// rebuilds onto another agent or onto its empty state. Leaving the route was never what fixed
  /// this case; it only uncovered the list that did.
  void _leave() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final route = ModalRoute.of(context);
      if (route == null || !navigator.canPop()) return;
      if (route.isCurrent) {
        navigator.pop();
      } else if (route.isActive) {
        // Underneath something: leave the stack quietly, so back from the page on top goes to
        // whatever was below this one.
        navigator.removeRoute(route);
      }
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
        // Last, and alone in red: the two above are recoverable and this one is
        // not, so it does not sit where a thumb lands on the way to them.
        //
        // ⚠️ Nothing here pops this page. Deleting detaches the pane, and the
        // `_hadPane` branch above leaves on its own when that happens — the same
        // path a delete from the list, or from the desktop, already takes. A pop
        // here would be a second one, and the parked pages in this pager share
        // the route.
        PhoneSheetAction(
          icon: LucideIcons.trash2300,
          label: 'Delete agent…',
          destructive: true,
          onTap: () => unawaited(
            confirmDeleteAgent(
              context,
              widget.notifier,
              widget.machineId,
              widget.agentId,
              agentName,
            ),
          ),
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

/// The longest agent name the header will print before it cuts.
///
/// An agent's name is usually a filename, and the header row has to hold three
/// controls beside it. Left to the width alone, a long name pushed right up
/// against `+` with no gap; cutting by COUNT keeps a fixed, predictable stretch
/// of chrome whatever the name and whatever the screen.
const int _titleMaxChars = 20;

/// The name as the header prints it: cut to [_titleMaxChars] with an ellipsis
/// when it is longer.
///
/// ⚠️ Counts runes, not code units. `String.length` counts UTF-16 units, so an
/// emoji or a decomposed Vietnamese vowel costs two and a name cuts early —
/// short of the 20 the design asks for, and at a different point per name.
///
/// ⚠️ The width ellipsis in [PhoneHeader] stays as well. This one bounds the
/// string; that one still catches a 20-character name on a narrow screen, and
/// neither makes the other redundant.
String _clipTitle(String name) {
  final runes = name.runes.toList();
  if (runes.length <= _titleMaxChars) return name;
  // Trailing space before the ellipsis reads as a typo, so it goes.
  return '${String.fromCharCodes(runes.take(_titleMaxChars)).trimRight()}…';
}

/// One of the header's trailing controls, padded so the three sit evenly.
///
/// ⚠️ The padding is what makes the row look right, and the reason is that
/// [AppIconButton] is a fixed 24px box for every glyph size. A 22px glyph fills
/// that box to its edges while a 20px one floats inside it, so equal gaps
/// BETWEEN the boxes read as unequal gaps between the marks. Giving every
/// action the same glyph size and the same padding puts the marks on an even
/// pitch.
///
/// ⚠️ It does NOT widen the tap target. [AppIconButton] takes its tap on a
/// 24px `GestureDetector` with no `HitTestBehavior.opaque`, so the padding is
/// dead space either side and the three stay 24px each — under the 44 iOS asks
/// for. Fixing that belongs in the shared button, where every screen's header
/// would get it, not in a wrapper one page defines.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 21,
    this.last = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  /// The rightmost action, whose trailing padding is dropped: [PhoneHeader]
  /// already insets the row's right edge, and keeping it here would push the
  /// last mark further from the edge than the others are from each other.
  final bool last;

  /// Half the gap between two marks — each neighbour contributes one, so the
  /// boxes end up 14 apart.
  ///
  /// 14 because that is [PhoneHeader]'s own right inset: the gap between two
  /// actions and the gap from the last one to the screen edge are then the
  /// same measure, and the three read as evenly placed rather than as a group
  /// shoved against the corner.
  static const double _gap = 7;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(_gap, 0, last ? 0 : _gap, 0),
    child: AppIconButton(
      icon: icon,
      size: size,
      tooltip: tooltip,
      color: AppPalette.textSecondary,
      onPressed: onPressed,
    ),
  );
}

/// The foot of the page: which computer the agent runs on, and whether that
/// computer is still answering.
///
/// It reads as one fact — *this agent, on that machine, live* — so the machine
/// and the state share a row rather than stacking. The dot belongs to the
/// state, not to the name, which is why [StatusPill] draws the pair and this
/// widget only puts the machine in front of it.
///
/// ⚠️ The name is what yields when the row is narrow. A truncated state word
/// is the bug this layout was moved out of the header to avoid — "Taken over"
/// ellipsed to "Ta…" there — so [StatusPill] keeps its intrinsic width and the
/// [Flexible] is on the name alone. A machine called "Macbook Pro của Phát"
/// loses its tail; "Disconnected" never does.
class _MachineBar extends StatelessWidget {
  const _MachineBar({required this.name, required this.status});

  final String name;

  /// Null while the header's reclaim button is saying the state instead — see
  /// the call site. The row then carries the machine alone, at the same height
  /// it has with both, so nothing under the terminal moves when a session is
  /// taken over.
  final PhoneSummary? status;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final status = this.status;
    // Nothing to say — the machine has not loaded and the header is carrying
    // the state. Draw no row rather than an empty one holding its padding
    // open under the terminal.
    if (name.isEmpty && status == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Row(
        children: [
          if (name.isNotEmpty)
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppPalette.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (name.isNotEmpty && status != null)
            // A separator the eye passes over rather than reads: the two halves
            // are one sentence, and a heavier mark between them made the row
            // look like two controls.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Text(
                '·',
                style: TextStyle(color: AppPalette.textFaint, fontSize: 12),
              ),
            ),
          if (status != null) StatusPill(fontSize: 12, summary: status),
        ],
      ),
    );
  }
}
