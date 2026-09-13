import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/state/pane_preset.dart';
import 'package:harness/widgets/terminal_panel.dart';
import 'package:xterm/xterm.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

Finder get jumpField => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.hintText == 'Search agents, swarms, machines, projects…',
);
Finder get selectedRow =>
    find.byWidgetPredicate((w) => w is ListTile && w.selected);

void main() {
  testWidgets('jump reveals an offscreen pane and delivers the first key there', (
    tester,
  ) async {
    final app = createApp();
    app.machineStates['m']!.nodeOnline = true;
    final inputs = List.generate(12, (_) => <TerminalBinaryFrame>[]);
    final sessions = List.generate(12, (i) => terminal('a$i', inputs[i]));
    for (final session in sessions) {
      app.adoptSessionForTest(session);
    }
    app.setPreset(12, PanePreset.cols2);
    app.focusPane(app.panes.first.id);
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyP);
    await tester.enterText(jumpField, 'Agent 11');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final pane = find.byWidgetPredicate(
      (w) => w is TerminalPanel && identical(w.session, sessions.last),
    );
    final rect = tester.getRect(pane);
    expect(rect.top, greaterThanOrEqualTo(40));
    expect(rect.bottom, lessThanOrEqualTo(800));
    final view = tester.widget<TerminalView>(
      find.descendant(of: pane, matching: find.byType(TerminalView)),
    );
    expect(
      view.focusNode!.hasFocus,
      isTrue,
      reason:
          'model ${app.focusedPaneId} / primary ${FocusManager.instance.primaryFocus}',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 10));
    expect(inputs.last.single.bytes, [27, 91, 68]);
    expect(inputs.take(11).every((input) => input.isEmpty), isTrue);
    final gridScroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView).first)
        .controller!;
    for (final crossSwarm in [false, true]) {
      if (crossSwarm) {
        app.newSwarm();
      } else {
        gridScroll.jumpTo(0);
      }
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyP);
      await tester.enterText(jumpField, 'Agent 11');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tester.getRect(pane).bottom, lessThanOrEqualTo(800));
      expect(tester.getRect(pane).top, greaterThanOrEqualTo(40));
      expect(
        tester
            .widget<TerminalView>(
              find.descendant(of: pane, matching: find.byType(TerminalView)),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
    }
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('jump focuses a same-Swarm pane, repeats focus and follows zoom', (
    tester,
  ) async {
    final app = createApp();
    app.machineStates['m']!.nodeOnline = true;
    final inputs = List.generate(3, (_) => <TerminalBinaryFrame>[]);
    final sessions = List.generate(3, (i) => terminal('a$i', inputs[i]));
    for (final session in sessions) {
      app.adoptSessionForTest(session);
    }
    await mount(tester, app);
    for (final i in [0, 0, 1]) {
      if (i == 1) app.toggleZoomPane();
      await chord(tester, LogicalKeyboardKey.keyP);
      await tester.enterText(jumpField, 'Agent $i');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final view = tester.widget<TerminalView>(
        find.byWidgetPredicate(
          (w) =>
              w is TerminalView && identical(w.terminal, sessions[i].terminal),
        ),
      );
      expect(
        view.focusNode!.hasFocus,
        isTrue,
        reason:
            'model ${app.focusedPaneId} / primary ${FocusManager.instance.primaryFocus}',
      );
      if (i == 1) expect(app.zoomedPaneId, app.panes[i].id);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(inputs[0], hasLength(2));
    expect(inputs[1].single.bytes, [27, 91, 68]);
    expect(inputs[2], isEmpty);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'search opens in one frame, owns typing, cancels, and replaces the separate Add picker',
    (tester) async {
      final app = createApp();
      app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app);
      final membership = [...app.panes];
      final input = find.byKey(const ValueKey('swarm-search-input'));
      final controller = tester.widget<TextField>(input).controller;
      final route = ModalRoute.of(tester.element(input));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(jumpField, findsOneWidget);
      final field = tester.widget<TextField>(jumpField);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(field.controller, same(controller));
      expect(ModalRoute.of(tester.element(input)), same(route));
      final results = tester.getRect(
        find.byKey(const ValueKey('swarm-search-results')),
      );
      final bar = tester.getRect(input);
      expect(results.top, inInclusiveRange(bar.bottom, bar.bottom + 12));
      expect(results.right, closeTo(bar.right, 0.1));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      await chord(tester, LogicalKeyboardKey.keyP);
      expect(
        find.byKey(const ValueKey('swarm-search-results')),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsNothing);
      await tester.enterText(jumpField, 'missing');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(jumpField, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(jumpField, findsNothing);
      expect(app.panes, membership);
      await chord(tester, LogicalKeyboardKey.keyF, shift: true);
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('swarm-search-input')));
      await tester.pump();
      expect(jumpField, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'Return jumps across swarms and a second jump returns to prior focus',
    (tester) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final firstInput = <TerminalBinaryFrame>[];
      final secondInput = <TerminalBinaryFrame>[];
      final firstPane = app.adoptSessionForTest(terminal('a0', firstInput));
      final first = app.activeSwarm;
      await mount(tester, app);
      app.newSwarm();
      final secondPane = app.adoptSessionForTest(terminal('a1', secondInput));
      app.dismissError();
      await tester.pump();
      final second = app.activeSwarm;
      await chord(tester, LogicalKeyboardKey.keyP);
      expect(
        find.descendant(of: selectedRow, matching: find.text('Agent 0')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.activeSwarmId, first.id);
      expect(app.focusedPaneId, firstPane.id);
      expect(first.panes, [firstPane]);
      expect(second.panes, [secondPane]);
      expect(firstInput, isEmpty);
      expect(secondInput, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
      expect(firstInput.single.bytes, [27, 91, 68]);
      expect(secondInput, isEmpty);
      await chord(tester, LogicalKeyboardKey.keyP);
      expect(
        find.descendant(of: selectedRow, matching: find.text('Agent 1')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.activeSwarmId, second.id);
      expect(app.focusedPaneId, secondPane.id);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 10));
      expect(firstInput, hasLength(1));
      expect(secondInput.single.bytes, [27, 91, 67]);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'keyboard selection scrolls, survives discovery, and explicitly opens a view',
    (tester) async {
      final app = createApp();
      app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyP);
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(selectedRow, findsOneWidget);
        final row = tester.getRect(selectedRow);
        final list = tester.getRect(find.byType(ListView));
        expect(row.top, greaterThanOrEqualTo(list.top));
        expect(row.bottom, lessThanOrEqualTo(list.bottom));
      }
      await tester.pump();
      final selectedId =
          (tester.widget<ListTile>(selectedRow).key! as ValueKey<String>).value;
      final rowRect = tester.getRect(selectedRow);
      final listRect = tester.getRect(find.byType(ListView));
      expect(rowRect.top, greaterThanOrEqualTo(listRect.top));
      expect(rowRect.bottom, lessThanOrEqualTo(listRect.bottom));
      final machine = app.machineStates['m']!;
      machine.agents = [
        const Agent(
          id: 'new',
          name: 'A newly discovered agent',
          terminalAvailable: true,
        ),
        ...machine.agents,
      ];
      app.dismissError();
      await tester.pump();
      await tester.pump();
      expect(tester.widget<ListTile>(selectedRow).key, ValueKey(selectedId));
      expect(find.textContaining('Open agent in'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.panes, hasLength(2));
      expect(
        agentDestinationId(
          app.focusedPane!.machineId,
          app.focusedPane!.agentId!,
        ),
        selectedId,
      );
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
