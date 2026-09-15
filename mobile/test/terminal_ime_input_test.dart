import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// The phone has no composer box under its pane — see `phone/terminal_page.dart`
/// — so the terminal's own input connection is the only place a software
/// keyboard has to compose in. Whatever this config says, a Vietnamese Telex or
/// CJK keyboard either gets a pre-edit buffer or types raw letters into the pty.
void main() {
  Terminal newTerminal() =>
      Terminal(maxLines: 200, reflowEnabled: false)..resize(80, 12);

  Future<void> pumpTerminal(WidgetTester tester, Terminal terminal) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 320,
            child: TerminalView(terminal, autofocus: true),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
  }

  Future<Map<String, dynamic>> attachedConfig(WidgetTester tester) async {
    await pumpTerminal(tester, newTerminal());
    return tester.testTextInput.setClientArgs!;
  }

  testWidgets(
    'iOS keeps the autocorrection machinery its Telex conversion rides on',
    (tester) async {
      final config = await attachedConfig(tester);

      // `autocorrect: false` reaches UIKit as `UITextAutocorrectionTypeNo`,
      // which is also what stops the Vietnamese keyboard turning `hoo` into
      // `hô`. iOS exposes no separate switch for the two.
      expect(config['autocorrect'], isTrue);
      expect(config['enableSuggestions'], isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Android composes with suggestions on and rewrites nothing with '
    'autocorrection off',
    (tester) async {
      final config = await attachedConfig(tester);

      // `enableSuggestions: false` reaches Android as
      // TYPE_TEXT_FLAG_NO_SUGGESTIONS, which takes the composing region — and
      // with it Telex — away entirely.
      expect(config['enableSuggestions'], isTrue);
      expect(config['autocorrect'], isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a desktop keyboard composes through marked text and keeps the strict '
    'config',
    (tester) async {
      final config = await attachedConfig(tester);

      expect(config['autocorrect'], isFalse);
      expect(config['enableSuggestions'], isFalse);
    },
    variant: TargetPlatformVariant.desktop(),
  );

  testWidgets(
    'quotes and dashes stay straight on every platform',
    (tester) async {
      final config = await attachedConfig(tester);

      // `"` and `--flag` are syntax at a prompt. Both of these default to
      // enabled, and iOS acts on them the moment autocorrect goes on.
      expect(config['smartDashesType'], SmartDashesType.disabled.index.toString());
      expect(config['smartQuotesType'], SmartQuotesType.disabled.index.toString());
    },
    variant: TargetPlatformVariant.all(),
  );

  testWidgets(
    'Telex sends the composed word, not the letters it was typed from',
    (tester) async {
      final terminal = newTerminal();
      final outbound = <String>[];
      terminal.onOutput = outbound.add;
      await pumpTerminal(tester, terminal);

      // `h`, `o`, `o`, `m` as the keyboard rewrites its own pre-edit text.
      for (final pending in const ['h', 'ho', 'hô', 'hôm']) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: pending,
            selection: TextSelection.collapsed(offset: pending.length),
            composing: TextRange(start: 0, end: pending.length),
          ),
        );
        await tester.pump();
        expect(outbound, isEmpty, reason: 'pre-edit `$pending` left the pty');
      }

      // Space ends the composition and commits it.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'hôm ',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();

      expect(outbound, ['hôm ']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
