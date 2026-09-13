import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/settings/sections/shortcuts_section.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shortcuts/app_keymap.dart';
import 'package:harness/shortcuts/keymap.dart';
import 'package:harness/shortcuts/shortcuts_list.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/swarm_switcher.dart';
import 'package:xterm/xterm.dart';

import 'keymap_host_test.dart' show MemoryKeymap, key;
import 'swarm_screen_test.dart' show terminal;
import 'swarm_state_test.dart' show createApp;

const nativeChannel = MethodChannel('harness/swarm_tabs');

Future<void> mount(
  WidgetTester tester,
  AppNotifier app,
  AppKeymap keymap, {
  bool native = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final projects = SwarmProjectStore();
  addTearDown(projects.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      builder: (_, child) => KeymapProvider(keymap: keymap, child: child!),
      home: SwarmScreen(
        notifier: app,
        nativeTabs: native,
        projectStore: projects,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> native(WidgetTester tester, String method, [Object? arguments]) {
  final done = Completer<void>();
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    nativeChannel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (_) => done.complete(),
  );
  return done.future;
}

void main() {
  testWidgets(
    'remaps, unbinding and sequences control the actual focused agent without leaking input',
    (tester) async {
      final map = MemoryKeymap();
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final firstInput = <TerminalBinaryFrame>[],
          secondInput = <TerminalBinaryFrame>[];
      final first = app.adoptSessionForTest(terminal('a0', firstInput));
      final second = app.adoptSessionForTest(terminal('a1', secondInput));
      await mount(tester, app, map);
      await key(tester, LogicalKeyboardKey.digit1, cmd: true);
      expect(app.focusedPaneId, first.id);
      await key(tester, LogicalKeyboardKey.keyL, cmd: true);
      expect(app.focusedPaneId, second.id);
      map.apply('''{"bindings":[
      {"keys":"cmd+h","command":null,"when":"terminal"},
      {"keys":"ctrl+g","command":"pane.focus_left","when":"terminal"},
      {"keys":"cmd+k","command":null},
      {"keys":"cmd+k n","command":"pane.focus_right"}
    ]}''');
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyH, cmd: true);
      expect(app.focusedPaneId, second.id, reason: 'No hardcoded H fallback');
      await key(tester, LogicalKeyboardKey.keyG, ctrl: true);
      expect(app.focusedPaneId, first.id);
      expect(firstInput, isEmpty);
      expect(secondInput, isEmpty);
      await key(tester, LogicalKeyboardKey.keyK, cmd: true);
      expect(find.text('⌘K …  Esc to cancel'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(find.text('⌘K …  Esc to cancel'), findsNothing);
      expect(
        firstInput,
        isEmpty,
        reason: 'A failed sequence is never agent input',
      );
      await key(tester, LogicalKeyboardKey.keyK, cmd: true);
      await key(tester, LogicalKeyboardKey.keyN);
      expect(app.focusedPaneId, second.id);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      expect(secondInput.single.bytes, [27, 91, 68]);
      expect(firstInput, isEmpty);
      map.apply(
        '{"bindings":[{"keys":"ctrl+g","command":null,"when":"terminal"}]}',
      );
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyG, ctrl: true);
      expect(secondInput.last.bytes, [
        7,
      ], reason: 'Unbinding restores the original agent input route');
      expect(app.panes, [first, second]);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      map.dispose();
    },
  );

  for (final inline in [false, true]) {
    testWidgets(
      'configured picker actions and hints stay in ${inline ? 'New swarm' : 'titlebar'} search',
      (tester) async {
        final map = MemoryKeymap()
          ..apply('''{"bindings":[
        {"keys":"down","command":null,"when":"picker"},
        {"keys":"ctrl+j","command":"picker.previous","when":"picker"},
        {"keys":"enter","command":null,"when":"picker"},
        {"keys":"alt+enter","command":"picker.accept","when":"picker"},
        {"keys":"cmd+i","command":null,"when":"picker"},
        {"keys":"ctrl+i","command":"picker.preview","when":"picker"}
      ]}''');
        final app = createApp();
        app.machineStates['m']!.nodeOnline = true;
        final frames = <TerminalBinaryFrame>[];
        final pane = app.adoptSessionForTest(terminal('a0', frames));
        final original = app.activeSwarmId;
        app.newSwarm();
        await mount(tester, app, map);
        final input = find.byKey(
          ValueKey(
            inline ? 'swarm-welcome-search-input' : 'swarm-search-input',
          ),
        );
        if (inline) {
          await tester.tap(input);
        } else {
          await key(tester, LogicalKeyboardKey.keyP, cmd: true);
        }
        await tester.enterText(input, 'Agent');
        await tester.pump();
        final search = tester
            .widget<SwarmSearchResults>(find.byType(SwarmSearchResults))
            .search;
        final initial = search.cursor;
        await key(tester, LogicalKeyboardKey.arrowDown);
        expect(search.cursor, initial);
        await key(tester, LogicalKeyboardKey.keyJ, ctrl: true);
        expect(search.cursor, (initial - 1) % search.rows.length);
        await tester.enterText(input, 'Agent 0');
        await tester.pump();
        expect(find.byTooltip('Preview recent output (⌃I)'), findsOneWidget);
        await key(tester, LogicalKeyboardKey.keyI, cmd: true);
        expect(search.previewEnabled, isFalse);
        await key(tester, LogicalKeyboardKey.keyI, ctrl: true);
        expect(search.previewEnabled, isTrue);
        await key(tester, LogicalKeyboardKey.enter);
        expect(find.byType(SwarmSearchResults), findsOneWidget);
        expect(frames, isEmpty);
        await key(tester, LogicalKeyboardKey.enter, alt: true);
        expect(app.activeSwarmId, original);
        expect(app.focusedPane, same(pane));
        expect(find.byType(SwarmSearchResults), findsNothing);
        await key(tester, LogicalKeyboardKey.arrowLeft);
        expect(frames.single.bytes, [27, 91, 68]);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        map.dispose();
      },
    );
  }

  testWidgets(
    'terminal IME composition keeps its keys before workspace dispatch',
    (tester) async {
      final map = MemoryKeymap();
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final frames = <TerminalBinaryFrame>[];
      app.adoptSessionForTest(terminal('a0', frames));
      await mount(tester, app, map);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '木',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pump();
      expect(
        tester.state<TerminalViewState>(find.byType(TerminalView)).isComposing,
        isTrue,
      );
      await key(tester, LogicalKeyboardKey.keyT, cmd: true);
      expect(app.swarms, hasLength(1));
      expect(frames, isEmpty);
      tester.testTextInput.updateEditingValue(TextEditingValue.empty);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyT, cmd: true);
      expect(app.swarms, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      map.dispose();
    },
  );

  testWidgets(
    'native field commands and snapshots use the same configured workspace actions',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        nativeChannel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          nativeChannel,
          null,
        ),
      );
      final map = MemoryKeymap();
      final app = createApp();
      final pane = app.adoptSessionForTest(terminal('a0', []));
      await mount(tester, app, map, native: true);
      expect(calls.where((c) => c.method == 'keymapState'), hasLength(1));
      map.apply(
        '{"bindings":[{"keys":"cmd+p","command":null},{"keys":"cmd+o","command":"navigation.quick_open"}]}',
      );
      await tester.pump();
      final snapshot =
          calls.lastWhere((c) => c.method == 'keymapState').arguments as Map;
      final picker = (snapshot['contexts'] as Map)['picker'] as List;
      expect(
        picker.any((row) => (row['keys'] as List).contains('cmd+p')),
        isFalse,
      );
      expect(
        picker.any(
          (row) =>
              row['command'] == 'navigation.quick_open' &&
              (row['keys'] as List).contains('cmd+o'),
        ),
        isTrue,
      );
      await native(tester, 'keymapCommand', {
        'command': 'navigation.quick_open',
      });
      await tester.pump();
      await native(tester, 'searchChanged', {'query': 'Agent 0'});
      await tester.pump();
      await native(tester, 'keymapCommand', {'command': 'picker.preview'});
      await tester.pump();
      expect(
        find.byKey(const ValueKey('swarm-search-preview')),
        findsOneWidget,
      );
      await native(tester, 'keymapCommand', {'command': 'picker.accept'});
      await tester.pump();
      expect(find.byType(SwarmSearchResults), findsNothing);
      expect(app.focusedPane, same(pane));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      map.dispose();
    },
  );

  testWidgets(
    'shortcut help reflects current overrides, context and unbound commands',
    (tester) async {
      final map = MemoryKeymap();
      late BuildContext helpContext;
      await tester.pumpWidget(
        MaterialApp(
          home: KeymapProvider(
            keymap: map,
            child: Builder(
              builder: (context) {
                helpContext = context;
                return const Scaffold(body: ShortcutsSection());
              },
            ),
          ),
        ),
      );
      var rows = effectiveShortcutRows(helpContext, KeymapContext.workspace);
      final searchLabel = rows
          .firstWhere((row) => row.chords.any((keys) => keys.join() == '⌘P'))
          .label;
      map.apply('''{"bindings":[
      {"keys":"cmd+p","command":null},
      {"keys":"cmd+o","command":"navigation.quick_open"},
      {"keys":"cmd+s","command":null,"when":"terminal"}
    ]}''');
      await tester.pump();
      rows = effectiveShortcutRows(helpContext, KeymapContext.workspace);
      expect(rows.firstWhere((r) => r.label == searchLabel).chords, [
        ['⌘', 'O'],
      ]);
      expect(
        rows.any((r) => r.chords.any((keys) => keys.join() == '⌘P')),
        isFalse,
      );
      final terminalRows = effectiveShortcutRows(
        helpContext,
        KeymapContext.terminal,
      );
      expect(terminalRows.where((r) => r.chords.isEmpty), isNotEmpty);
      expect(find.byType(ShortcutsDeck), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      map.dispose();
    },
  );
}
