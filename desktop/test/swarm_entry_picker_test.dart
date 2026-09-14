import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:xterm/xterm.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp, MemoryStore;

final _input = find.byKey(const ValueKey('swarm-search-input'));
final _results = find.byKey(const ValueKey('swarm-search-results'));

void main() {
  for (final native in [false, true]) {
    testWidgets(
      'the starting picker cannot leave a blank page (native=$native)',
      (tester) async {
        const channel = MethodChannel('harness/swarm_tabs');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => true,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final app = createApp();
        await mount(tester, app, nativeTabs: native);
        void ready() {
          expect(_results, findsOneWidget);
          expect(
            tester.widget<TextField>(_input).focusNode!.hasPrimaryFocus,
            isTrue,
          );
          expect(find.byKey(const ValueKey('welcome-title')), findsNothing);
          expect(find.text('> Commands'), findsNothing);
          expect(
            find.byKey(const ValueKey('swarm-search-new-agent')),
            findsOneWidget,
          );
        }

        ready();
        final original = app.activeSwarmId;
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        ready();
        expect(find.text('esc'), findsNothing);
        app.renameSwarm(original, 'Empty workspace');
        await tester.pump();
        ready();
        expect(app.activeSwarmId, original);
        await chord(tester, LogicalKeyboardKey.keyO);
        ready();
        expect(app.swarms, hasLength(1));
        await chord(tester, LogicalKeyboardKey.keyT);
        await tester.pump();
        ready();
        expect(app.swarms, hasLength(1));
        expect(app.activeSwarmId, original);
        expect(app.panes, isEmpty);
        await tester.tapAt(const Offset(20, 200));
        await tester.pump();
        ready();
        app.dismissError();
        await tester.pump();
        ready();
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        expect(tester.takeException(), isNull);
      },
    );

    for (final dismissal in ['outside', 'escape']) {
      testWidgets('cancel a new draft on $dismissal (native=$native)', (
        tester,
      ) async {
        final app = createApp();
        final frames = <TerminalBinaryFrame>[];
        final pane = app.adoptSessionForTest(terminal('a0', frames));
        final original = app.activeSwarmId;
        await mount(tester, app, nativeTabs: native);
        await chord(tester, LogicalKeyboardKey.keyT);
        await tester.pump();
        final draft = app.activeSwarmId;
        expect(draft, isNot(original));
        expect(app.isDraftSwarm(draft), isTrue);
        expect(_results, findsOneWidget);
        // Repeated New Harness reuses the untouched draft.
        await chord(tester, LogicalKeyboardKey.keyT);
        expect(app.swarms, hasLength(2));
        if (dismissal == 'outside') {
          await tester.tapAt(const Offset(20, 200));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await tester.pump();
        expect(_results, findsNothing);
        expect(app.activeSwarmId, original);
        expect(app.swarms, hasLength(1));
        expect(app.closedHistory, isEmpty);
        expect(app.focusedPane, same(pane));
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(frames.single.bytes, [27, 91, 66]);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('discovery preserves picker composition and Escape ownership', (
    tester,
  ) async {
    final app = createApp();
    await mount(tester, app);
    await tester.enterText(_input, 'Agent 12');
    await tester.pump();
    final text = tester.widget<TextField>(_input).controller!;
    final composing = text.value.copyWith(
      selection: const TextSelection.collapsed(offset: 7),
      composing: const TextRange(start: 6, end: 8),
    );
    text.value = composing;
    app.renameSwarm(app.activeSwarmId, 'Updated in the background');
    await tester.pump();
    expect(text.value, composing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_results, findsOneWidget);
    text.clearComposing();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(_results, findsOneWidget);
    await chord(tester, LogicalKeyboardKey.keyP, shift: true);
    expect(tester.widget<TextField>(_input).controller!.text, '> ');
    expect(
      tester.widget<TextField>(_input).decoration!.hintText,
      'Search commands…',
    );
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'a first selection opens here and hands the terminal its next key',
    (tester) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final frames = <TerminalBinaryFrame>[];
      final pane = app.adoptSessionForTest(terminal('a0', frames));
      final original = app.activeSwarm;
      app.newSwarm(draft: true);
      final destination = app.activeSwarmId;
      await mount(tester, app);
      await tester.enterText(_input, 'Agent 0');
      await tester.pump();
      expect(frames, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.activeSwarmId, destination);
      expect(original.panes.single, same(pane));
      expect(app.panes.single, same(pane));
      expect(app.isDraftSwarm(destination), isFalse);
      expect(_results, findsNothing);
      expect(
        tester
            .widget<TerminalView>(find.byType(TerminalView))
            .focusNode!
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
      expect(frames.single.bytes, [27, 91, 68]);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  test(
    'drafts are omitted from persistence and cancellation history',
    () async {
      final store = MemoryStore();
      final app = createApp(store: store);
      addTearDown(app.dispose);
      await app.addAgentToSwarm('m', 'a0');
      final original = app.activeSwarmId;
      app.newSwarm(draft: true);
      final draft = app.activeSwarmId;
      await app.flushPaneLayout();
      final restored = createApp(store: store);
      addTearDown(restored.dispose);
      await restored.restorePaneLayoutForTest();
      expect(restored.swarms, hasLength(1));
      expect(restored.activeSwarmId, original);
      expect(app.cancelSwarmDraft(draft), isTrue);
      expect(app.activeSwarmId, original);
      expect(app.closedHistory, isEmpty);

      app.newSwarm(draft: true);
      final committed = app.activeSwarmId;
      await app.addAgentToSwarm('m', 'a1');
      expect(app.cancelSwarmDraft(committed), isFalse);
      await app.closeSwarm(committed);
      expect(app.closedSwarms.single.id, committed);
    },
  );

  test('leaving a draft discards it, but a renamed workspace is kept', () {
    final app = createApp();
    addTearDown(app.dispose);
    final original = app.activeSwarmId;
    app.newSwarm(draft: true);
    app.selectSwarm(original);
    expect(app.swarms, hasLength(1));
    expect(app.closedHistory, isEmpty);
    app.newSwarm(draft: true);
    final saved = app.activeSwarmId;
    app.renameSwarm(saved, 'Planned work');
    expect(app.cancelSwarmDraft(saved), isFalse);
    app.selectSwarm(original);
    expect(app.swarms, hasLength(2));
  });
}
