import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/swarm_switcher.dart';

import 'swarm_interactions_test.dart' show chord;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;
import 'support/real_fonts.dart';

Future<void> seedPreviews(AppNotifier app) async {
  final machine = app.machineStates['m']!;
  machine.nodeOnline = true;
  machine.connectionStatus = ConnectionStatus.connected;
  machine.agents = [
    for (final (id, name, engine) in [
      ('a0', 'Checkout retries', 'codex'),
      ('a1', 'Search experience', 'claude'),
      ('a2', 'Workspace sync', 'codex'),
    ])
      Agent(
        id: id,
        sessionId: 'session-$id',
        name: name,
        engine: engine,
        terminalAvailable: true,
        project: AgentProject(
          name: id == 'a0' ? 'storefront' : 'workbench',
          cwd: '/work/${id == 'a0' ? 'storefront' : 'workbench'}',
          branch: 'feat/${id == 'a0' ? 'safe-retries' : 'search'}',
        ),
      ),
  ];
  Future<void> event(String id, String type, Map<String, dynamic> payload) =>
      app.handleEventForTest('m', {
        'type': type,
        'payload': {'agentId': id, 'sessionId': 'session-$id', ...payload},
      });
  await event('a0', 'turn_started', {
    'userMessage':
        'Prevent duplicate charges when a checkout request is retried.',
  });
  await event('a0', 'text_delta', {
    'content': 'Payment retries now reuse the same idempotency key.\n\n**Verified**\n- A timed-out checkout can be retried safely.\n- The original receipt is preserved.\n- All 24 payment tests pass.',
  });
  await event('a0', 'turn_ended', {});
  await event('a1', 'turn_started', {
    'userMessage': 'Show the current task and latest result when selecting a workspace. Keep keyboard navigation fast.',
  });
  await event('a1', 'text_delta', {
    'content': 'The cached preview is connected. I’m checking keyboard focus and resizing at narrow window widths.',
  });
  await event('a1', 'tool_start', {'tool': 'Read'});
  await event('a2', 'turn_started', {
    'userMessage': 'Keep shared workspaces in sync across both machines.',
  });
  await event('a2', 'commander_question', {
    'requestId': 'q',
    'questions': [
      {
        'q': 'Should a workspace reopen its last layout on another machine?',
        'options': ['Restore the layout', 'Start with one pane'],
      },
    ],
  });
}

void main() {
  setUpAll(() async {
    await loadRealFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
    await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
          rootBundle.load(
            'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
          ),
        ))
        .load();
  });

  testWidgets('offline previews retain text without claiming to work or wait', (
    tester,
  ) async {
    final app = createApp();
    await seedPreviews(app);
    app.adoptSessionForTest(terminal('a69', []));
    await mount(tester, app);
    await chord(tester, LogicalKeyboardKey.keyO);
    final field = find.byKey(const ValueKey('swarm-search-input'));
    await tester.enterText(field, 'Workspace sync');
    await tester.pump();
    expect(find.text('Needs your input'), findsOneWidget);
    app.machineStates['m']!.connectionStatus = ConnectionStatus.disconnected;
    app.notifyListeners();
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Needs your input'), findsNothing);
    expect(
      find.textContaining('Keep shared workspaces in sync'),
      findsOneWidget,
    );
    expect(find.textContaining('Saved text'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  for (final inline in [false, true]) {
    testWidgets(
      'existing content previews are immediate and preserve search focus (inline=$inline)',
      (tester) async {
        final app = createApp();
        await seedPreviews(app);
        app.adoptSessionForTest(
          terminal('a69', [])..terminal.write('Raw terminal noise'),
        );
        app.newSwarm();
        await mount(tester, app);
        final field = find.byKey(
          ValueKey(inline ? 'harness-start-search' : 'swarm-search-input'),
        );
        if (inline) {
          await tester.tap(field);
        } else {
          await chord(tester, LogicalKeyboardKey.keyO);
        }
        await tester.enterText(field, 'Checkout retries');
        await tester.pump();
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Payment retries now reuse'),
          findsOneWidget,
        );
        expect(find.text('Latest response'), findsOneWidget);
        expect(find.textContaining('Raw terminal noise'), findsNothing);
        final editor = tester.widget<EditableText>(
          find.descendant(of: field, matching: find.byType(EditableText)),
        );
        expect(editor.focusNode.hasFocus, isTrue);
        final list = tester.getRect(
          find.byKey(const ValueKey('swarm-search-result-list')),
        );
        final preview = tester.getRect(
          find.byKey(const ValueKey('swarm-search-preview')),
        );
        expect(preview.left, greaterThanOrEqualTo(list.right));

        await tester.enterText(field, 'Search experience');
        await tester.pump();
        expect(find.text('Current request'), findsOneWidget);
        expect(
          find.textContaining('The cached preview is connected'),
          findsOneWidget,
        );
        expect(find.textContaining('Payment retries now reuse'), findsNothing);
        expect(editor.focusNode.hasFocus, isTrue);
        await app.handleEventForTest('m', {
          'type': 'text_delta',
          'payload': {
            'agentId': 'a1',
            'sessionId': 'session-a1',
            'content': 'The current selection updates immediately.',
          },
        });
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          find.text('The current selection updates immediately.'),
          findsOneWidget,
        );
        expect(editor.focusNode.hasFocus, isTrue);

        await tester.enterText(field, 'Test host');
        await tester.pump();
        final search = tester
            .widget<SwarmSearchResults>(find.byType(SwarmSearchResults))
            .search;
        expect(search.selected!.agentId, isNull);
        final waiting = tester.getTopLeft(find.text('Workspace sync').last);
        final working = tester.getTopLeft(find.text('Search experience').last);
        expect(waiting.dy, lessThan(working.dy));
        expect(
          find.text(
            'Should a workspace reopen its last layout on another machine?',
          ),
          findsOneWidget,
        );

        await tester.enterText(field, 'Checkout retries');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(app.panes.any((pane) => pane.agentId == 'a0'), isTrue);
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsNothing,
        );
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }

  for (final size in [
    const Size(1280, 800),
    const Size(760, 650),
    const Size(400, 600),
  ]) {
    testWidgets('preview remains readable and scrollable at $size', (
      tester,
    ) async {
      final app = createApp();
      await seedPreviews(app);
      app.adoptSessionForTest(terminal('a69', []));
      await mount(tester, app);
      tester.view.physicalSize = size;
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyO);
      await tester.enterText(
        find.byKey(const ValueKey('swarm-search-input')),
        'Checkout',
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      final preview = tester.getRect(
        find.byKey(const ValueKey('swarm-search-preview')),
      );
      final list = tester.getRect(
        find.byKey(const ValueKey('swarm-search-result-list')),
      );
      if (size.width < 864) {
        expect(preview.top, greaterThanOrEqualTo(list.bottom));
      }
      final directory = Platform.environment['HARNESS_PREVIEW_CAPTURE_DIR'];
      if (directory != null) {
        final renderView = tester.binding.renderViews.first;
        final layer = renderView.debugLayer! as OffsetLayer;
        await tester.runAsync(() async {
          final image = await layer.toImage(Offset.zero & size);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/preview-${size.width.toInt()}.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
}
