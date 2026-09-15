import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

const _viewHeight = 300.0;

/// Mounts a view the way Harness does (`resizeBuffer: false`, so the local grid
/// is whatever the remote screen is) and returns the terminal and what it sent.
Future<(Terminal, List<String>)> _mount(
  WidgetTester tester,
  ScrollController controller,
) async {
  final output = <String>[];
  final terminal = Terminal(maxLines: 1000, reflowEnabled: false)
    ..onOutput = output.add;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 600,
          height: _viewHeight,
          child: TerminalView(
            terminal,
            resizeBuffer: false,
            scrollController: controller,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (terminal, output);
}

/// A full-screen TUI whose grid is taller than the pane showing it — the remote
/// pane has not taken the size this view reported, or another client keeps it
/// larger. The alternate screen then has a few pixels of local scroll extent.
Future<void> _tuiTallerThanPane(WidgetTester tester, Terminal terminal) async {
  final lineHeight = tester
      .state<TerminalViewState>(find.byType(TerminalView))
      .renderTerminal
      .lineHeight;
  terminal.resize(60, (_viewHeight / lineHeight).floor() + 2);
  // Alternate screen, with SGR mouse reports on — tmux with `mouse on`.
  terminal.write('\x1b[?1049h\x1b[?1000h\x1b[?1006h');
  await tester.pump();
  await tester.pump();
}

Future<void> _trackpadUp(WidgetTester tester) async {
  final center = tester.getCenter(find.byType(TerminalView));
  final pad = TestPointer(1, PointerDeviceKind.trackpad);
  await tester.sendEventToBinding(pad.panZoomStart(center));
  await tester.sendEventToBinding(
    pad.panZoomUpdate(center, pan: const Offset(0, 120)),
  );
  await tester.sendEventToBinding(pad.panZoomEnd());
  await tester.pump(const Duration(milliseconds: 400));
}

const _wheelUpReport = '\x1b[<64;';

void main() {
  testWidgets(
    'trackpad scrolling reaches a full-screen program whose grid is taller than the pane',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final (terminal, output) = await _mount(tester, controller);
      await _tuiTallerThanPane(tester, terminal);
      expect(controller.position.maxScrollExtent, greaterThan(0));

      await _trackpadUp(tester);

      expect(output.join(), contains(_wheelUpReport));
    },
  );

  testWidgets(
    'a mouse-wheel tick reaches a full-screen program whose grid is taller than the pane',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final (terminal, output) = await _mount(tester, controller);
      await _tuiTallerThanPane(tester, terminal);
      expect(controller.position.maxScrollExtent, greaterThan(0));

      final mouse = TestPointer(2, PointerDeviceKind.mouse);
      final center = tester.getCenter(find.byType(TerminalView));
      await tester.sendEventToBinding(mouse.hover(center));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
      await tester.pump(const Duration(milliseconds: 400));

      expect(output.join(), contains(_wheelUpReport));
    },
  );

  // Only the alternate screen hands scrolling to the program: in the normal
  // screen the gesture reads local history, as it always has.
  testWidgets('in the normal screen the same gesture still scrolls history', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final (terminal, output) = await _mount(tester, controller);
    terminal.write(List.generate(200, (i) => 'line $i').join('\r\n'));
    await tester.pump();
    await tester.pump();
    final bottom = controller.position.maxScrollExtent;
    expect(bottom, greaterThan(0));
    expect(controller.position.pixels, bottom);

    await _trackpadUp(tester);

    expect(controller.position.pixels, lessThan(bottom));
    expect(output.join(), isNot(contains(_wheelUpReport)));
  });

  // Scrollable swaps in a new ScrollPosition whenever its dependencies change —
  // a reparent is enough, and the pane grid reparents terminals as its layout
  // moves. The scroll view moved the wrong listener onto the new position, so
  // after two or three scrolls every later one reached nothing.
  testWidgets(
    'scrolling still reaches the program after the view is reparented',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(maxLines: 1000, reflowEnabled: false)
        ..onOutput = output.add;
      final viewKey = GlobalKey();
      Future<void> pump({required bool padded}) {
        final view = TerminalView(terminal, key: viewKey, resizeBuffer: false);
        return tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 600,
                height: _viewHeight,
                child: padded
                    ? Padding(padding: EdgeInsets.zero, child: view)
                    : Center(child: view),
              ),
            ),
          ),
        );
      }

      // The alternate screen's own scroll view is the outermost Scrollable.
      ScrollPosition altScrollPosition() => tester
          .stateList<ScrollableState>(find.byType(Scrollable))
          .first
          .position;

      Future<void> wheelUp() async {
        final mouse = TestPointer(4, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(
          mouse.hover(tester.getCenter(find.byType(TerminalView))),
        );
        await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
        await tester.pump(const Duration(milliseconds: 400));
      }

      await pump(padded: true);
      terminal.write('\x1b[?1049h\x1b[?1000h\x1b[?1006h');
      await tester.pump();
      await tester.pump();
      await wheelUp();
      expect(output.join(), contains(_wheelUpReport));
      output.clear();
      final before = altScrollPosition();

      await pump(padded: false);
      await tester.pump();
      expect(altScrollPosition(), isNot(same(before)));

      await wheelUp();
      expect(output.join(), contains(_wheelUpReport));
    },
  );
}
