import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:xterm/xterm.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';

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
class TerminalKeyBar extends StatelessWidget {
  const TerminalKeyBar({
    super.key,
    required this.terminal,
    required this.enabled,
    required this.controlArmed,
    required this.onControlToggle,
    required this.onDismissKeyboard,
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

  void _send(void Function() action) {
    if (!enabled) return;
    HapticFeedback.selectionClick();
    action();
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final top = <Widget>[
      _key(label: 'esc', onTap: () => terminal.keyInput(TerminalKey.escape)),
      _key(label: 'tab', onTap: () => terminal.keyInput(TerminalKey.tab)),
      for (final char in const ['~', '|', '/', '-'])
        _key(label: char, onTap: () => terminal.textInput(char)),
      _key(
        icon: LucideIcons.arrowLeft300,
        semanticLabel: 'Left',
        onTap: () => terminal.keyInput(TerminalKey.arrowLeft),
      ),
      _key(
        icon: LucideIcons.arrowUp300,
        semanticLabel: 'Up',
        onTap: () => terminal.keyInput(TerminalKey.arrowUp),
      ),
      _key(
        icon: LucideIcons.arrowDown300,
        semanticLabel: 'Down',
        onTap: () => terminal.keyInput(TerminalKey.arrowDown),
      ),
      _key(
        icon: LucideIcons.arrowRight300,
        semanticLabel: 'Right',
        onTap: () => terminal.keyInput(TerminalKey.arrowRight),
      ),
      // Not a key the pty ever hears about: it puts the keyboard away, which on
      // a phone is the only way to read a full screen of output.
      _key(
        icon: LucideIcons.chevronDown300,
        semanticLabel: 'Hide keyboard',
        alwaysEnabled: true,
        onTap: onDismissKeyboard,
      ),
    ];
    final bottom = <Widget>[
      _key(
        label: 'ctrl',
        held: controlArmed,
        onTap: () => onControlToggle(!controlArmed),
      ),
      for (final digit in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
        _key(label: digit, onTap: () => terminal.textInput(digit)),
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
          // at a large scale eleven keys across a phone stop fitting the row.
          child: MediaQuery.withNoTextScaling(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_row(top), const SizedBox(height: 6), _row(bottom)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(List<Widget> keys) => Row(
    children: [
      for (var index = 0; index < keys.length; index++) ...[
        if (index > 0) const SizedBox(width: 4),
        Expanded(child: keys[index]),
      ],
    ],
  );

  Widget _key({
    String? label,
    IconData? icon,
    String? semanticLabel,
    bool held = false,
    bool alwaysEnabled = false,
    required VoidCallback onTap,
  }) {
    assert((label == null) != (icon == null), 'a key carries one of the two');
    final live = enabled || alwaysEnabled;
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
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: held ? AppSurface.accentWash : AppGlass.surfaceFill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: held ? AppPalette.accentOnSurface : AppGlass.lift,
            ),
          ),
          child: icon != null
              ? Icon(icon, size: 16, color: foreground)
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
