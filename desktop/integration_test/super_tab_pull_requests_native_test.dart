import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:harness/core/test_run.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/super_tabs/pull_requests.dart';

import '../test/super_tab_pull_requests_test.dart'
    show prServer, allPrStates, prUrl;

/// Native rendering of the actual pane, with protocol fixtures and no production daemon or account writes.
void main() {
  if (!kUnderTest) throw StateError('Requires FLUTTER_TEST=1');
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('linked PR status, expansion and stale answers render on macOS', (
    tester,
  ) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1100, 1100));
    await windowManager.setAlwaysOnTop(true);
    addTearDown(() => windowManager.setAlwaysOnTop(false));
    await windowManager.show();
    await windowManager.focus();
    final rows = allPrStates();
    final server = prServer(
      rows.map((r) => int.parse((r['url'] as String).split('/').last)),
    );
    final c = await tester.runAsync(() async {
      final c = server.controller();
      await c.refresh();
      return c;
    });
    var fail = false;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: grid.buildAppTheme(brightness: Brightness.dark),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: SuperTabPullRequests(
              controller: c!,
              read: (_) async => fail ? {'error': 'TIMEOUT'} : {'rows': rows},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Needs you 4'), findsOneWidget);
    expect(find.text('Ready to merge'), findsOneWidget);
    expect(find.text('View status on GitHub'), findsNothing);
    Future<void> shot(String name) async {
      final folder = Platform.environment['SUPER_TAB_PR_SHOTS'];
      if (folder == null) return;
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(folder).create(recursive: true);
      await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await tester.runAsync(() => shot('pull-requests-all-states'));
    await tester.tap(find.text('Show 1 more'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Closed 1'));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('super-pr-${prUrl(16)}')), findsOneWidget);
    await tester.runAsync(() => shot('pull-requests-expanded'));
    fail = true;
    // A new linked URL triggers a read now, without waiting a wall-clock minute.
    server.append(prUrl(18));
    await tester.runAsync(c.refresh);
    await tester.pumpAndSettle();
    expect(
      find.textContaining("GitHub didn't answer. Showing what it said"),
      findsOneWidget,
    );
    expect(find.text('Pull request 1'), findsOneWidget);
    await tester.runAsync(() => shot('pull-requests-stale'));
    final receipt = Platform.environment['SUPER_TAB_PR_REAL_RECEIPT'];
    if (receipt != null) {
      final real =
          (jsonDecode(await File(receipt).readAsString()) as Map)['rows']
              as List;
      await tester.pumpWidget(const SizedBox());
      final realServer = prServer(
        real.map((r) => int.parse((r['url'] as String).split('/').last)),
      );
      for (final message in realServer.messages) {
        message['text'] = (message['text'] as String).replaceAll(
          'github.com/o/r/',
          'github.com/autonomous-ai/openharness/',
        );
      }
      final realController = await tester.runAsync(() async {
        final c = realServer.controller();
        await c.refresh();
        return c;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: SuperTabPullRequests(
                controller: realController!,
                read: (_) async => {'rows': real},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Merged 6'), findsOneWidget);
      expect(find.text('Nothing needs you.'), findsOneWidget);
      expect(find.text('View status on GitHub'), findsNothing);
      await tester.runAsync(() => shot('pull-requests-real-six'));
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(realController.flush);
      realController.dispose();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(c.flush);
    c.dispose();
  });
}
