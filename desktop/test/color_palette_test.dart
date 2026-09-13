import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/settings/appearance/palette_section.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shared/theme/appearance_prefs_store.dart';
import 'package:harness/shared/theme/color_palette.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/terminal/terminal_theme.dart';
import 'package:xterm/xterm.dart';

import 'swarm_screen_test.dart' show terminal;
import 'swarm_state_test.dart' show createApp;

class _Storage implements LocalKeyValueStore {
  final values = <String, String>{};
  Completer<void>? writeGate;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> delete(String key) async => values.remove(key);
  @override
  Future<void> write(String key, String value) async {
    await writeGate?.future;
    values[key] = value;
  }
}

void main() {
  tearDown(() => grid.AppTheme.palette.value = HarnessPalette.graphite);

  test('rapid palette changes keep the last choice through relaunch', () async {
    final storage = _Storage()..writeGate = Completer<void>();
    final store = AppearancePrefsStore(storage: storage);
    addTearDown(store.dispose);
    final saved = store.setPalette(HarnessPalette.forest);
    store.setPalette(HarnessPalette.ember);
    expect(store.value.palette, HarnessPalette.ember);
    storage.writeGate!.complete();
    await saved;
    final restored = AppearancePrefsStore(storage: storage);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.value.palette, HarnessPalette.ember);
    await restored.reset();
    expect(storage.values.containsKey('app_color_palette'), isFalse);
    expect(restored.value.palette, HarnessPalette.graphite);
    storage.values['app_color_palette'] = 'missing-preset';
    await restored.load();
    expect(restored.value.palette, HarnessPalette.graphite);
  });

  test('palette text is readable and terminal themes are cached', () {
    double contrast(Color foreground, Color background) =>
        (foreground.computeLuminance() + .05) /
        (background.computeLuminance() + .05);
    for (final palette in HarnessPalette.values) {
      expect(
        contrast(palette.foreground, palette.background),
        greaterThanOrEqualTo(7),
        reason: palette.name,
      );
      for (final background in [
        palette.search,
        palette.card,
        palette.workspace,
      ]) {
        final secondary = Color.alphaBlend(Colors.white70, background);
        expect(
          contrast(secondary, background),
          greaterThanOrEqualTo(4.5),
          reason: palette.name,
        );
      }
      expect(terminalThemeFor(palette), same(terminalThemeFor(palette)));
      expect(terminalThemeFor(palette).background, palette.background);
      expect(terminalThemeFor(palette).selection.a, lessThan(.5));
    }
  });

  testWidgets(
    'palette choices fit narrow settings and support keyboard selection',
    (tester) async {
      final store = AppearancePrefsStore(storage: _Storage());
      addTearDown(store.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: SingleChildScrollView(child: PaletteSection(store: store)),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(store.value.palette, HarnessPalette.dusk);
      await tester.ensureVisible(find.byKey(const ValueKey('palette-forest')));
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Forest palette. Quiet evergreen'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('palette-forest')));
      await tester.pump();
      expect(store.value.palette, HarnessPalette.forest);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets(
    'palette changes preserve the live terminal and update native colors',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const channel = MethodChannel('harness/swarm_tabs');
      final updates = <Map>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'update') updates.add(call.arguments as Map);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final app = createApp();
      final input = <TerminalBinaryFrame>[];
      final session = terminal('a0', input)..terminal.write('Keep this output');
      app.adoptSessionForTest(session);
      final projects = SwarmProjectStore();
      await tester.pumpWidget(
        grid.BrightnessScope(
          child: MaterialApp(
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            home: SwarmScreen(
              notifier: app,
              nativeTabs: true,
              projectStore: projects,
            ),
          ),
        ),
      );
      await tester.pump();
      final terminalState = tester.state(find.byType(TerminalView));
      final before = tester.widget<TerminalView>(find.byType(TerminalView));
      final hadFocus = before.focusNode!.hasFocus;
      final pane = app.focusedPane;
      grid.AppTheme.palette.value = HarnessPalette.midnight;
      await tester.pump();
      final after = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(tester.state(find.byType(TerminalView)), same(terminalState));
      expect(after.terminal, same(before.terminal));
      expect(app.focusedPane, same(pane));
      expect(after.focusNode!.hasFocus, hadFocus);
      expect(after.theme.background, HarnessPalette.midnight.background);
      expect(updates.last['palette'], HarnessPalette.midnight.nativeColors);
      expect(input, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      projects.dispose();
    },
  );
}
