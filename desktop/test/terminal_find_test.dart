import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:harness/terminal/terminal_search.dart';
import 'package:harness/widgets/terminal_find_bar.dart';
import 'package:xterm/xterm.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

Finder get findField => find.byWidgetPredicate(
  (widget) =>
      widget is TextField && widget.decoration?.hintText == 'Find in terminal…',
);

Future<void> finishFind(WidgetTester tester) async {
  for (var frame = 0; frame < 200; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (!tester
        .widget<TerminalFindBar>(find.byType(TerminalFindBar))
        .search
        .searching) {
      return;
    }
  }
  fail('Find did not settle');
}

TerminalViewState terminalView(WidgetTester tester, TerminalSession session) =>
    tester.state<TerminalViewState>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TerminalView && widget.terminal == session.terminal,
      ),
    );

Future<void> output(
  TerminalSession session,
  int sequence,
  String text, {
  bool keyframe = false,
}) => session.handleBinary(
  TerminalBinaryFrame(
    kind: keyframe ? TerminalBinaryKind.keyframe : TerminalBinaryKind.output,
    streamId: session.streamId!,
    seq: sequence,
    compressed: false,
    bytes: utf8.encode(text),
    cols: keyframe ? 80 : null,
    rows: keyframe ? 24 : null,
  ),
);

void main() {
  testWidgets(
    'a narrow find bar supports large text and a large result count',
    (tester) async {
      final terminal = Terminal()..resize(80, 4);
      terminal.write('needle\r\n' * 9998);
      final search = TerminalSearch(terminal);
      await tester.runAsync(() async {
        search.setQuery('needle');
        await search.settled;
      });
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                height: 38,
                child: TerminalFindBar(
                  search: search,
                  readOnly: true,
                  onQuery: (query, sensitive) =>
                      search.setQuery(query, caseSensitive: sensitive),
                  onStep: search.step,
                  onClose: () {},
                  onFocus: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(findField).height, lessThanOrEqualTo(38));
      expect(tester.getSize(findField).width, greaterThan(24));
      expect(
        find.bySemanticsLabel(
          'Match ${search.selected + 1} of ${search.count}',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Match case'));
      await tester.pump();
      expect(tester.widget<TextField>(findField).focusNode!.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      search.dispose();
      semantics.dispose();
    },
  );

  testWidgets(
    'find opens in one frame without resizing, preserves selection and returns to prior scroll',
    (tester) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final input = <TerminalBinaryFrame>[];
      final session = terminal('a0', input);
      session.terminal.write(
        List.generate(
          180,
          (i) => 'Line $i${i % 50 == 0 ? ' needle' : ''}\r\n',
        ).join(),
      );
      app.adoptSessionForTest(session);
      await mount(tester, app);
      final view = terminalView(tester, session);
      final renderer = view.renderTerminal;
      final size = renderer.size;
      final dimensions = (
        session.terminal.viewWidth,
        session.terminal.viewHeight,
      );
      final scroll = view.widget.scrollController!;
      scroll.jumpTo(renderer.lineHeight * 20.5);
      final previousScroll = scroll.offset;
      final controller = view.widget.controller!;
      controller.setSelection(
        session.terminal.buffer.createAnchor(0, 5),
        session.terminal.buffer.createAnchor(4, 5),
      );
      final previousSelection = controller.selection;
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump();
      expect(findField, findsOneWidget);
      expect(tester.widget<TextField>(findField).focusNode!.hasFocus, isTrue);
      expect(view.renderTerminal, same(renderer));
      expect(renderer.size, size);
      expect((
        session.terminal.viewWidth,
        session.terminal.viewHeight,
      ), dimensions);
      await tester.enterText(findField, 'needle');
      await finishFind(tester);
      final search = tester
          .widget<TerminalFindBar>(find.byType(TerminalFindBar))
          .search;
      expect(search.count, 4);
      expect(search.selected, 1);
      expect(controller.highlights, hasLength(1));
      expect(
        session.terminal.buffer.getText(controller.highlights.single.range),
        'needle',
      );
      expect(controller.selection, previousSelection);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(search.selected, 2);
      await chord(tester, LogicalKeyboardKey.keyG);
      expect(search.selected, 3);
      await chord(tester, LogicalKeyboardKey.keyG, shift: true);
      expect(search.selected, 2);
      expect(input, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(findField, findsNothing);
      expect(controller.highlights, isEmpty);
      expect(controller.selection, previousSelection);
      expect(scroll.offset, closeTo(previousScroll, 0.01));
      expect(renderer.size, size);
      await chord(tester, LogicalKeyboardKey.keyG);
      await finishFind(tester);
      expect(
        tester
            .widget<TerminalFindBar>(find.byType(TerminalFindBar))
            .search
            .selected,
        3,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(scroll.offset, closeTo(previousScroll, 0.01));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 10));
      expect(input.single.bytes, [27, 91, 68]);
      for (final key in [LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyG]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(input.skip(1).map((frame) => frame.bytes.single), [6, 7]);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'hidden find does no indexing and returns to the same query with current output',
    (tester) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final a = terminal('a0', []);
      final b = terminal('a1', []);
      await output(a, 0, 'first marker\r\n', keyframe: true);
      app.adoptSessionForTest(a);
      final first = app.activeSwarm;
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyF);
      await tester.enterText(findField, 'marker');
      await finishFind(tester);
      final search = tester
          .widget<TerminalFindBar>(find.byType(TerminalFindBar))
          .search;
      expect(search.count, 1);
      app.newSwarm();
      app.adoptSessionForTest(b);
      await tester.pump();
      await tester.pump();
      expect(search.count, 0);
      expect(findField, findsNothing);
      await output(a, 1, 'second marker\r\n');
      expect(tester.binding.hasScheduledFrame, isFalse);
      app.selectSwarm(first.id, attachPending: false);
      await tester.pump();
      await finishFind(tester);
      expect(search.count, 2);
      expect(tester.widget<TextField>(findField).controller!.text, 'marker');
      expect(tester.widget<TextField>(findField).focusNode!.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'a real keyframe replaces the emulator without sending find text to the agent',
    (tester) async {
      final app = createApp();
      app.machineStates['m']!.nodeOnline = true;
      final input = <TerminalBinaryFrame>[];
      final session = terminal('a0', input);
      await output(session, 0, 'old marker\r\n', keyframe: true);
      app.adoptSessionForTest(session);
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyF);
      await tester.enterText(findField, 'marker');
      await finishFind(tester);
      final old = session.terminal;
      final text = tester.widget<TextField>(findField).controller!;
      text.selection = const TextSelection.collapsed(offset: 3);
      await output(
        session,
        10,
        'new marker\r\nsecond marker\r\n',
        keyframe: true,
      );
      await tester.pump();
      await finishFind(tester);
      expect(session.terminal, isNot(same(old)));
      expect(tester.widget<TextField>(findField).controller, same(text));
      expect(text.selection, const TextSelection.collapsed(offset: 3));
      expect(tester.widget<TextField>(findField).focusNode!.hasFocus, isTrue);
      expect(
        tester
            .widget<TerminalFindBar>(find.byType(TerminalFindBar))
            .search
            .count,
        2,
      );
      await tester.enterText(findField, 'new');
      await finishFind(tester);
      expect(
        tester
            .widget<TerminalFindBar>(find.byType(TerminalFindBar))
            .search
            .count,
        1,
      );
      expect(input, isEmpty);
      old.buffer.lines.forEach((line) => expect(line.anchors, isEmpty));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets('taken-over terminals can be searched without retry or input', (
    tester,
  ) async {
    final app = createApp();
    app.machineStates['m']!.nodeOnline = true;
    final input = <TerminalBinaryFrame>[];
    final session = terminal('a0', input);
    session.terminal.write('Retained Error\r\n');
    app.adoptSessionForTest(session);
    session.status = TerminalSessionStatus.takenOver;
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyF);
    expect(find.text('TERMINAL FROZEN'), findsNothing);
    expect(find.byTooltip('This terminal is read only'), findsOneWidget);
    await tester.enterText(findField, 'error');
    await finishFind(tester);
    final search = tester
        .widget<TerminalFindBar>(find.byType(TerminalFindBar))
        .search;
    expect(search.count, 1);
    await tester.tap(find.byTooltip('Match case'));
    await finishFind(tester);
    expect(search.count, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(session.status, TerminalSessionStatus.takenOver);
    expect(find.text('TERMINAL FROZEN'), findsNothing);
    expect(find.text('Take control'), findsOneWidget);
    expect(input, isEmpty);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
