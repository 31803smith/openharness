import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/swarm_icon.dart';
import 'package:harness/widgets/swarm_navigator.dart';

import 'keymap_host_test.dart' show MemoryKeymap, key;
import 'keymap_runtime_test.dart' show mount;
import 'swarm_screen_test.dart' show terminal;
import 'swarm_state_test.dart' show createApp;

void main() {
  for (final native in [false, true]) {
    testWidgets(
      'shared ${native ? 'native-button' : 'Flutter-button'} picker owns arrows, select-all, delete and command mode',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('harness/swarm_tabs'),
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('harness/swarm_tabs'),
            null,
          ),
        );
        final map = MemoryKeymap();
        final app = createApp();
        app.machineStates['m']!.nodeOnline = true;
        final input = <TerminalBinaryFrame>[];
        final session = terminal('a0', input)
          ..terminal.write('Reviewing the implementation\r\nAll checks passed');
        app.adoptSessionForTest(session);
        await mount(tester, app, map, native: native);
        final field = find.byKey(const ValueKey('swarm-search-input'));
        expect(field, findsNothing);
        await key(tester, LogicalKeyboardKey.keyP, cmd: true);
        await tester.pump();
        expect(field, findsOneWidget);
        expect(find.byType(SwarmNavigator), findsOneWidget);
        final controller = tester.widget<TextField>(field).controller!;
        final focus = tester.widget<TextField>(field).focusNode!;
        expect(focus.hasFocus, isTrue);
        final selected = find.byWidgetPredicate(
          (w) => w is ListTile && w.selected,
        );
        final first = tester.widget<ListTile>(selected).key;
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(tester.widget<ListTile>(selected).key, isNot(first));
        await key(tester, LogicalKeyboardKey.arrowUp);
        expect(tester.widget<ListTile>(selected).key, first);
        await tester.enterText(field, 'Agent 0');
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-navigation-locations')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsNothing,
        );
        await key(tester, LogicalKeyboardKey.keyA, cmd: true);
        expect(controller.selection.textInside(controller.text), 'Agent 0');
        await key(tester, LogicalKeyboardKey.backspace);
        expect(controller.text, isEmpty);
        await tester.enterText(field, 'Agent 1');
        await key(tester, LogicalKeyboardKey.keyP, cmd: true);
        expect(controller.selection.textInside(controller.text), 'Agent 1');
        await key(tester, LogicalKeyboardKey.keyP, cmd: true, shift: true);
        expect(controller.text, '> ');
        expect(find.text('Search commands…'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsNothing,
        );
        expect(app.activeSwarm.pinnedSlots, isEmpty);
        await key(tester, LogicalKeyboardKey.keyA, cmd: true);
        await key(tester, LogicalKeyboardKey.backspace);
        expect(controller.text, isEmpty);
        expect(find.byType(SwarmIcon), findsWidgets);
        expect(focus.hasFocus, isTrue);
        expect(input, isEmpty);
        await key(tester, LogicalKeyboardKey.escape);
        expect(field, findsNothing);
        await tester.tap(find.byKey(const ValueKey('swarm-add-agent-button')));
        await tester.pump();
        await tester.enterText(field, 'Agent 0');
        await tester.pump();
        final results = tester.getRect(
          find.byKey(const ValueKey('swarm-search-result-list')),
        );
        final preview = tester.getRect(
          find.byKey(const ValueKey('swarm-search-preview')),
        );
        expect(preview.left, greaterThanOrEqualTo(results.right));
        expect(preview.top, results.top);
        expect(find.textContaining('All checks passed'), findsOneWidget);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        expect(input, isEmpty);
        await key(tester, LogicalKeyboardKey.escape);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        map.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
