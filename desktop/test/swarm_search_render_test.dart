import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shared/theme/color_palette.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/swarm_search_input.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

void main() {
  testWidgets('Add arrow movement rebuilds only the changed result rows', (
    tester,
  ) async {
    final app = createApp();
    final input = <TerminalBinaryFrame>[];
    app.adoptSessionForTest(terminal('a69', input));
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyN);
    final field = find.byKey(const ValueKey('swarm-search-input'));
    await tester.enterText(field, 'Agent');
    await tester.pump(const Duration(milliseconds: 200));
    final search = tester
        .widget<SwarmSearchInput>(
          find.ancestor(of: field, matching: find.byType(SwarmSearchInput)),
        )
        .search!;
    final previous = search.selected!.id;
    var fields = 0;
    var rows = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is TextField) fields++;
      if (element.widget is ListTile) rows++;
    };
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(search.selected!.id, isNot(previous));
    expect(
      fields,
      0,
      reason: 'Moving the highlight does not change the editor',
    );
    expect(rows, 2, reason: 'Only the old and new highlights changed');
    final selected = tester.widget<ListTile>(
      find.byKey(ValueKey(search.selected!.id)),
    );
    expect(selected.selected, isTrue);
    expect(find.byKey(const ValueKey('swarm-row-action')), findsOneWidget);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(input, isEmpty);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'cached Add rows keep selection through palette and text changes',
    (tester) async {
      final app = createApp();
      final originalPalette = grid.AppTheme.palette.value;
      addTearDown(() => grid.AppTheme.palette.value = originalPalette);
      app.adoptSessionForTest(terminal('a69', []));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        grid.BrightnessScope(
          child: MaterialApp(
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            home: SwarmScreen(notifier: app, nativeTabs: false),
          ),
        ),
      );
      await chord(tester, LogicalKeyboardKey.keyN);
      final field = find.byKey(const ValueKey('swarm-search-input'));
      await tester.enterText(field, 'Agent');
      await tester.pump();
      final row = find.byKey(ValueKey(agentDestinationId('m', 'a0')));
      final checkbox = find.byKey(
        ValueKey('select:${agentDestinationId('m', 'a0')}'),
      );
      await tester.tap(checkbox);
      await tester.pump();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      final height = tester.getSize(row).height;
      grid.AppTheme.palette.value = HarnessPalette.ember;
      await tester.pump();
      expect(
        tester.widget<Checkbox>(checkbox).activeColor,
        HarnessPalette.ember.accent,
      );
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pump();
      expect(tester.getSize(row).height, greaterThan(height));
      expect(tester.widget<TextField>(field).controller!.text, 'Agent');
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets('Add header and cached rows respond when capacity changes', (
    tester,
  ) async {
    final app = createApp();
    final input = <TerminalBinaryFrame>[];
    app.adoptSessionForTest(terminal('a69', input));
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyN);
    final field = find.byKey(const ValueKey('swarm-search-input'));
    final create = find.byKey(const ValueKey('swarm-search-new-agent'));
    await tester.enterText(field, 'Agent');
    await tester.pump();
    final editor = tester.widget<TextField>(field).controller;
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    for (var i = 0; i < AppNotifier.maxPanes - 1; i++) {
      app.adoptSessionForTest(terminal('a$i', input));
    }
    app.dismissError(); // Publish the sessions assembled through the test seam.
    await tester.pump();
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    final row = find.byKey(ValueKey(agentDestinationId('m', 'a0')));
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    expect(
      find.descendant(of: row, matching: find.text('In this swarm')),
      findsOneWidget,
    );
    await app.closePane(app.panes.last.id);
    await tester.pump();
    expect(tester.widget<FilledButton>(create).onPressed, isNotNull);
    expect(tester.widget<TextField>(field).controller, same(editor));
    expect(editor!.text, 'Agent');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(input, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('a completed background add cannot take the picker keyboard', (
    tester,
  ) async {
    final app = createApp();
    final input = <TerminalBinaryFrame>[];
    app.adoptSessionForTest(terminal('a0', input));
    app.newSwarm();
    app.adoptSessionForTest(terminal('a69', input));
    final target = app.activeSwarm;
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyN);
    final field = find.byKey(const ValueKey('swarm-search-input'));
    await tester.enterText(field, 'Agent');
    await tester.pump();
    await app.addAgentToSwarm('m', 'a0', swarmId: target.id);
    await tester.pump();
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    final search = tester
        .widget<SwarmSearchInput>(
          find.ancestor(of: field, matching: find.byType(SwarmSearchInput)),
        )
        .search!;
    final previous = search.selected!.id;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(search.selected!.id, isNot(previous));
    expect(input, isEmpty);
    expect(target.panes, hasLength(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
