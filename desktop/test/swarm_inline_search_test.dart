import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:xterm/xterm.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

final _input = find.byKey(const ValueKey('swarm-welcome-search-input'));
final _results = find.byKey(const ValueKey('swarm-welcome-search-results'));

void main() {
  for (final native in [false, true]) {
    testWidgets(
      'New swarm arrives ready to type without opening results (native=$native)',
      (tester) async {
        const channel = MethodChannel('harness/swarm_tabs');
        final messages = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            messages.add(call);
            return true;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = createApp();
        app.machineStates['m']!.nodeOnline = true;
        final frames = <TerminalBinaryFrame>[];
        final projects = SwarmProjectStore();
        await tester.pumpWidget(
          MaterialApp(
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            home: SwarmScreen(
              notifier: app,
              nativeTabs: native,
              projectStore: projects,
            ),
          ),
        );
        await tester.pump();
        void ready() {
          expect(
            _results,
            findsNothing,
            reason: 'Arriving must leave the welcome choices visible',
          );
          expect(
            tester.widget<TextField>(_input).focusNode!.hasPrimaryFocus,
            isTrue,
          );
        }

        ready();
        messages.clear();
        tester.testTextInput.enterText('Agent 12');
        await tester.pump();
        expect(_results, findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Agent 12'), findsOneWidget);
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
        expect(_results, findsOneWidget, reason: 'Composition owns Escape');
        text.clearComposing();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        ready();
        expect(text.text, 'Agent 12');
        tester.testTextInput.enterText('Agent 3');
        await tester.pump();
        expect(_results, findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Agent 3'), findsOneWidget);
        expect(
          messages.where(
            (c) => c.method == 'searchState' || c.method == 'focusSearch',
          ),
          isEmpty,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        app.adoptSessionForTest(terminal('a0', frames));
        app.selectSwarm(app.activeSwarmId);
        await tester.pump();
        await tester.pump();
        app.newSwarm();
        await tester.pump();
        await tester.pump();
        ready();
        final newId = app.activeSwarmId;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(_results, findsOneWidget);
        expect(
          app.activeSwarmId,
          newId,
          reason: 'Opening suggestions cannot activate an unseen result',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        ready();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(_results, findsOneWidget);
        expect(app.activeSwarmId, newId);
        await app.closeSwarm(app.activeSwarmId);
        await tester.pump();
        await app.closeSwarm(app.activeSwarmId);
        await tester.pump();
        await tester.pump();
        ready();
        expect(app.swarms, hasLength(1));
        expect(frames, isEmpty);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        projects.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'New swarm keeps editing and results at the field that was clicked',
    (tester) async {
      final app = createApp();
      await mount(tester, app);
      final top = find.byKey(const ValueKey('swarm-search-input'));
      final before = tester.getRect(_input);
      await tester.tap(_input);
      await tester.enterText(_input, 'Agent 12');
      await tester.pump();
      expect(tester.widget<TextField>(_input).focusNode!.hasFocus, isTrue);
      expect(top, findsNothing);
      expect(find.byKey(const ValueKey('swarm-search-results')), findsNothing);
      expect(find.widgetWithText(ListTile, 'Agent 12'), findsOneWidget);
      final results = tester.getRect(_results);
      expect(tester.getRect(_input), before);
      expect(results.top, closeTo(before.bottom, 0.1));
      expect(results.left, closeTo(before.left, 0.1));
      expect(results.width, closeTo(before.width, 0.1));
      expect(results.bottom, lessThanOrEqualTo(784));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(_results, findsNothing);
      expect(tester.widget<TextField>(_input).controller!.text, 'Agent 12');
      await tester.tap(_input);
      await tester.pump();
      expect(_results, findsOneWidget);
      await chord(tester, LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(_results, findsNothing);
      expect(
        find.byKey(const ValueKey('swarm-search-results')),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(top).focusNode!.hasFocus, isTrue);
      expect(tester.widget<TextField>(top).controller!.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'inline selection opens the existing agent and hands it the next key',
    (tester) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final frames = <TerminalBinaryFrame>[];
      final pane = app.adoptSessionForTest(terminal('a0', frames));
      final original = app.activeSwarmId;
      app.newSwarm();
      await mount(tester, app);
      await tester.tap(_input);
      await tester.enterText(_input, 'Agent 0');
      await tester.pump();
      expect(frames, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.activeSwarmId, original);
      expect(app.panes.single, same(pane));
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

  testWidgets(
    'the welcome field never redirects typing through the native title bar',
    (tester) async {
      const channel = MethodChannel('harness/swarm_tabs');
      final messages = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        messages.add(call);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = createApp();
      final projects = SwarmProjectStore();
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: SwarmScreen(
            notifier: app,
            nativeTabs: true,
            projectStore: projects,
          ),
        ),
      );
      await tester.pump();
      messages.clear();
      await tester.tap(_input);
      await tester.enterText(_input, 'Agent 3');
      await tester.pump();
      expect(_results, findsOneWidget);
      expect(
        messages.where(
          (call) =>
              call.method == 'focusSearch' || call.method == 'searchState',
        ),
        isEmpty,
      );
      final controller = tester.widget<TextField>(_input).controller!;
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 0, end: 3),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.panes, isEmpty);
      expect(_results, findsOneWidget);
      controller.clearComposing();
      await tester.tapAt(const Offset(30, 100));
      await tester.pump();
      expect(_results, findsNothing);
      await tester.pumpWidget(const SizedBox());
      projects.dispose();
      app.dispose();
    },
  );
}
