import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shared/theme/color_palette.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/terminal/terminal_theme.dart';
import 'package:harness/terminal/terminal_theme_store.dart';

void main() {
  test('the terminal default follows the app\'s dark background', () {
    expect(darkTerminalTheme.background, const Color(0xff181818));
    expect(darkTerminalTheme.foreground, const Color(0xffffffff));
  });

  test('the colours sent to a daemon are the pane\'s own, as #rrggbb', () {
    addTearDown(() {
      grid.AppTheme.palette.value = HarnessPalette.graphite;
      terminalThemeStore.value = TerminalThemeChoice.matchApp;
    });
    expect(AppNotifier.terminalThemeColours(), {
      'background': '#181818',
      'foreground': '#f5f5f5',
    });
    terminalThemeStore.value = TerminalThemeChoice.tango;
    expect(AppNotifier.terminalThemeColours()['background'], '#300a24');
  });
}
