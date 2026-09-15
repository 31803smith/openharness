import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:xterm/xterm.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'phone_sheet.dart';

/// The keys a phone keyboard does not have, in a strip above the one it does.
///
/// A pane is driven by `esc`, `tab`, the arrows and `ctrl` far more than by
/// anything the alphabet offers — interrupting Claude Code, cycling its modes,
/// walking shell history, `^C`. None of them exist on a software keyboard, so
/// until this strip a phone could type at an agent but could not DRIVE one.
///
/// It appears with the keyboard and goes away with it: the terminal is short
/// enough on a phone that two rows of chrome are worth their height only while
/// someone is actually typing.
///
/// ⚠️ **One row that SCROLLS, with the rest behind `»`.** The keys outgrew a
/// fixed grid the moment `enter` and `⇧tab` joined them: eleven across a narrow
/// phone leaves each one under 30px, below the 44px Apple and Android both put
/// as the floor for a touch target, and these are keys people hit repeatedly
/// while looking at the terminal rather than at their thumb. So the row keeps
/// full-size keys and runs off the edge instead, ordered by how often a key is
/// actually reached for, and `»` opens the remainder — digits included — as a
/// second row rather than shrinking the first.
class TerminalKeyBar extends StatefulWidget {
  const TerminalKeyBar({
    super.key,
    required this.terminal,
    required this.enabled,
    required this.controlArmed,
    required this.onControlToggle,
    required this.onDismissKeyboard,
    this.onPickImage,
    this.onTakePhoto,
  });

  final Terminal terminal;

  /// False while the stream is not accepting input — the strip stays visible
  /// (it moves with the keyboard, and a row that vanished would take the
  /// keyboard's place with it) but dims and stops answering.
  final bool enabled;

  /// Whether the next character typed leaves as a control chord. Owned by the
  /// session, which is also what spends it — see `TerminalSession.armControl`.
  final bool controlArmed;
  final ValueChanged<bool> onControlToggle;
  final VoidCallback onDismissKeyboard;

  /// Sending a picture. Null on a pane that cannot take one — an older CLI that
  /// never advertised `terminalImagePasteAvailable` — and the buttons are then
  /// not drawn at all rather than drawn dead: a key that does nothing is worse
  /// than one that was never offered.
  final VoidCallback? onPickImage;
  final VoidCallback? onTakePhoto;

  @override
  State<TerminalKeyBar> createState() => _TerminalKeyBarState();
}

class _TerminalKeyBarState extends State<TerminalKeyBar> {
  /// Whether `»` has opened the second row.
  ///
  /// Held here rather than by the page: it is a property of this strip, it does
  /// not survive the keyboard going away, and nothing above needs to know.
  bool _expanded = false;

  void _send(void Function() action) {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    action();
  }

  Terminal get _terminal => widget.terminal;

  /// Whether this pane can take a picture at all — see [TerminalKeyBar.onPickImage].
  bool get _canSendImage =>
      widget.onPickImage != null || widget.onTakePhoto != null;

  /// The pinned image button: asks WHICH picture, then hands off.
  ///
  /// The sheet only appears where there is a choice to make. A build with just
  /// one of the two wired goes straight there instead — a sheet with a single
  /// row is a tap spent on nothing.
  void _sendImage() {
    final pick = widget.onPickImage;
    final photo = widget.onTakePhoto;
    if (pick == null) {
      photo?.call();
      return;
    }
    if (photo == null) {
      pick();
      return;
    }
    showPhoneSheet(
      context,
      title: 'Send a picture to this agent',
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.image300,
          label: 'Choose from library',
          onTap: pick,
        ),
        PhoneSheetAction(
          icon: LucideIcons.camera300,
          label: 'Take a photo',
          onTap: photo,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // Ordered by reach, not by keyboard layout: `esc` and `tab` drive an engine's
    // modes, `↵` ends a message, `⇧tab` cycles Claude Code's, and the arrows walk
    // history.
    //
    // ⚠️ Sending a picture is NOT in here, and that is the whole point of the
    // pinned button below. A scrolling row only shows four keys on a 393pt phone,
    // so anything past `⇧tab` is behind a swipe — measured, not guessed. The
    // image button was tenth in this list and therefore invisible on arrival,
    // which for the one action people come to this bar for is the same as absent.
    final primary = <Widget>[
      _key(label: 'esc', onTap: () => _terminal.keyInput(TerminalKey.escape)),
      _key(label: 'tab', onTap: () => _terminal.keyInput(TerminalKey.tab)),
      _key(
        icon: LucideIcons.cornerDownLeft300,
        semanticLabel: 'Enter',
        onTap: () => _terminal.keyInput(TerminalKey.enter),
      ),
      // Shift+Tab is CSI Z, and xterm builds it from the modifier rather than
      // from a key of its own — which is why this passes `shift` instead of
      // looking for a `TerminalKey.shiftTab` that does not exist.
      _key(
        label: '⇧tab',
        onTap: () => _terminal.keyInput(TerminalKey.tab, shift: true),
      ),
      _key(
        icon: LucideIcons.arrowUp300,
        semanticLabel: 'Up',
        onTap: () => _terminal.keyInput(TerminalKey.arrowUp),
      ),
      _key(
        icon: LucideIcons.arrowDown300,
        semanticLabel: 'Down',
        onTap: () => _terminal.keyInput(TerminalKey.arrowDown),
      ),
      _key(
        icon: LucideIcons.arrowLeft300,
        semanticLabel: 'Left',
        onTap: () => _terminal.keyInput(TerminalKey.arrowLeft),
      ),
      _key(
        icon: LucideIcons.arrowRight300,
        semanticLabel: 'Right',
        onTap: () => _terminal.keyInput(TerminalKey.arrowRight),
      ),
      _key(
        label: 'ctrl',
        held: widget.controlArmed,
        onTap: () => widget.onControlToggle(!widget.controlArmed),
      ),
    ];
    final secondary = <Widget>[
      for (final char in const ['~', '|', '/', '-', '_', ':', '.'])
        _key(label: char, onTap: () => _terminal.textInput(char)),
      for (final digit in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
        _key(label: digit, onTap: () => _terminal.textInput(digit)),
    ];

    return ExcludeFocus(
      // ⚠️ Load-bearing. Every key here is a tap target inside a focus scope the
      // TERMINAL owns: a focusable one would take the focus on tap, the input
      // connection would close, and the keyboard this strip is attached to
      // would leave with it on the first `esc`.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.panelBg,
          border: Border(top: BorderSide(color: AppGlass.hair)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          // Held out of the app-wide text scale like the composer's own type:
          // the keys are sized for a thumb, and a large accessibility scale
          // would grow the labels past the boxes holding them.
          child: MediaQuery.withNoTextScaling(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _scrollingRow(primary)),
                    const SizedBox(width: 4),
                    // Pinned for the same reason `»` is, and more so: this is
                    // what somebody opens the bar to reach. One button rather
                    // than two — the library and the camera are two answers to
                    // "which picture", which is a question a sheet asks better
                    // than a second key nobody can fit on the row.
                    if (_canSendImage) ...[
                      _key(
                        icon: LucideIcons.image300,
                        semanticLabel: 'Send image',
                        onTap: _sendImage,
                      ),
                      const SizedBox(width: 4),
                    ],
                    // Pinned OUTSIDE the scroller, so the way to the rest of the
                    // keys cannot itself be scrolled off the edge.
                    _key(
                      icon: _expanded
                          ? LucideIcons.chevronsLeft300
                          : LucideIcons.chevronsRight300,
                      semanticLabel: _expanded ? 'Fewer keys' : 'More keys',
                      held: _expanded,
                      alwaysEnabled: true,
                      onTap: () => setState(() => _expanded = !_expanded),
                    ),
                    const SizedBox(width: 4),
                    // Not a key the pty ever hears about: it puts the keyboard
                    // away, which on a phone is the only way to read a full
                    // screen of output.
                    _key(
                      icon: LucideIcons.chevronDown300,
                      semanticLabel: 'Hide keyboard',
                      alwaysEnabled: true,
                      onTap: widget.onDismissKeyboard,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 6),
                  _scrollingRow(secondary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One row of keys at their natural width, scrolling horizontally past the edge.
  ///
  /// `ClampingScrollPhysics` rather than the iOS default: a bouncing row above the
  /// keyboard reads as the whole strip coming loose, and the overscroll glow is
  /// what says "there is more this way" on a row with no scrollbar.
  Widget _scrollingRow(List<Widget> keys) => SizedBox(
    height: _keyHeight,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: keys.length,
      separatorBuilder: (_, _) => const SizedBox(width: 4),
      itemBuilder: (_, index) => keys[index],
    ),
  );

  /// Tall enough to hit without looking — the floor both platforms put on a
  /// touch target, which the old two-row grid was under at 34.
  static const double _keyHeight = 40;

  /// Wide enough for `⇧tab` at 13px, and the same width for every key so the row
  /// reads as a keyboard rather than as a sentence of buttons.
  static const double _keyWidth = 52;

  Widget _key({
    String? label,
    IconData? icon,
    String? semanticLabel,
    bool held = false,
    bool alwaysEnabled = false,
    required VoidCallback onTap,
  }) {
    assert((label == null) != (icon == null), 'a key carries one of the two');
    final live = widget.enabled || alwaysEnabled;
    final foreground = held
        ? AppPalette.accentOnSurface
        : live
        ? AppPalette.textPrimary
        : AppPalette.textFaint;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      // Named so a test can reach the icon keys, which carry no text.
      key: ValueKey('terminal-key-${semanticLabel ?? label}'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: alwaysEnabled ? onTap : () => _send(onTap),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: _keyWidth,
          height: _keyHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: held ? AppSurface.accentWash : AppGlass.surfaceFill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: held ? AppPalette.accentOnSurface : AppGlass.lift,
            ),
          ),
          child: icon != null
              ? Icon(icon, size: 17, color: foreground)
              : Text(
                  label!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1,
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}
