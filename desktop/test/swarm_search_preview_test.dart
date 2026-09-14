import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/swarm_search.dart';
import 'package:harness/terminal/search_output_preview.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:xterm/xterm.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

void main() {
  test(
    'preview bounds scrollback, rows and columns without altering Unicode',
    () {
      final terminal = Terminal(maxLines: 10000)..resize(300, 120);
      terminal.write('A short prompt in a tall pane');
      expect(
        SearchOutputPreview.capture(terminal).text,
        'A short prompt in a tall pane',
      );
      terminal.write('\r\n');
      for (var i = 0; i < 500; i++) {
        terminal.write('Old line $i\r\n');
      }
      terminal.write('${'木' * 150}\r\nRecent result 😀\r\n> ');
      final before = terminal.buffer.getText();
      final position = (terminal.buffer.cursorX, terminal.buffer.cursorY);
      final snapshot = SearchOutputPreview.capture(terminal).text;
      expect(snapshot.split('\n').length, SearchOutputPreview.shownLines);
      expect(snapshot, contains('木' * 96));
      expect(snapshot, isNot(contains('木' * 97)));
      expect(snapshot, contains('Recent result 😀'));
      expect(snapshot, isNot(contains('Old line 0\n')));
      expect(snapshot, isNot(contains('\uFFFD')));
      expect(terminal.buffer.getText(), before);
      expect((terminal.buffer.cursorX, terminal.buffer.cursorY), position);
      terminal.write('\r\n' * (SearchOutputPreview.scannedLines + 1));
      expect(SearchOutputPreview.capture(terminal).text, isEmpty);
      expect(SearchOutputPreview.capture(null).text, isEmpty);
    },
  );

  test(
    'preview is lazy and cached for the selection, with explicit refresh',
    () {
      final app = createApp();
      addTearDown(app.dispose);
      final output = terminal('a0', []);
      output.terminal.write('Original context');
      final pane = app.adoptSessionForTest(output);
      final search = SwarmSearchController(app, []);
      addTearDown(search.dispose);
      search.setQuery('Agent 0');
      expect(search.preview, isNull);
      search.togglePreview();
      final first = search.preview;
      expect(first!.text, contains('Original context'));
      output.terminal.write('\r\nNew output');
      for (final query in ['Agent', 'Agent 0', 'Test host Agent 0']) {
        search.setQuery(query);
        expect(search.preview, same(first));
      }
      search.togglePreview();
      expect(search.preview, isNull);
      search.togglePreview();
      expect(search.preview!.text, contains('New output'));
      expect(pane.session, same(output));
      search.setQuery('Agent 1');
      expect(search.preview!.text, isEmpty);
      expect(app.allPanes, [pane]);
      search.setQuery('>');
      expect(search.previewVisible, isFalse);
      expect(search.preview, isNull);
    },
  );

  for (final inline in [false, true]) {
    testWidgets(
      'optional preview keeps ${inline ? 'New swarm' : 'titlebar'} input and go-to action',
      (tester) async {
        final app = createApp();
        app.machineStates['m']!.nodeOnline = true;
        final frames = <TerminalBinaryFrame>[];
        final output = terminal('a0', frames);
        output.terminal.write('Checking the build\r\nOne useful clue\r\n');
        final original = app.adoptSessionForTest(output);
        if (inline) app.newSwarm();
        final target = app.activeSwarm;
        await mount(tester, app);
        final input = find.byKey(
          ValueKey(
            inline ? 'swarm-welcome-search-input' : 'swarm-search-input',
          ),
        );
        if (!inline) {
          await tester.tap(find.byKey(const ValueKey('swarm-search-button')));
          await tester.pump();
        }
        await tester.tap(input);
        await tester.enterText(input, 'Agent 0');
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsOneWidget,
        );
        await chord(tester, LogicalKeyboardKey.keyI);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsNothing,
        );
        final field = tester.widget<TextField>(input);
        final controller = field.controller!;
        final focus = field.focusNode!;
        await chord(tester, LogicalKeyboardKey.keyI);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsOneWidget,
        );
        expect(find.textContaining('One useful clue'), findsOneWidget);
        expect(controller.text, 'Agent 0');
        expect(focus.hasFocus, isTrue);
        expect(app.activeSwarm, same(target));
        expect(frames, isEmpty);

        // Mouse toggling also keeps editing in the field that opened search.
        await tester.tap(
          find.byKey(const ValueKey('swarm-search-preview-toggle')),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsNothing,
        );
        expect(focus.hasFocus, isTrue);
        controller.value = const TextEditingValue(
          text: 'Agent 0',
          composing: TextRange(start: 0, end: 7),
        );
        await chord(tester, LogicalKeyboardKey.keyI);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsNothing,
        );
        controller.value = const TextEditingValue(
          text: 'Agent 0',
          selection: TextSelection.collapsed(offset: 7),
        );
        await chord(tester, LogicalKeyboardKey.keyI);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(app.focusedPaneId, original.id);
        expect(app.panes.single.session, same(output));
        expect(frames, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump(const Duration(milliseconds: 10));
        expect(frames.single.bytes, [27, 91, 68]);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
