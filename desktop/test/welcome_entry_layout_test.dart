import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;

import 'support/real_fonts.dart';
import 'swarm_state_test.dart' show createApp;

void main() {
  setUpAll(() async {
    await loadRealFonts();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final (width, height, scale) in [
    (1280.0, 800.0, 1.0),
    (760.0, 900.0, 1.0),
    (600.0, 900.0, 1.7),
  ]) {
    testWidgets(
      'two welcome actions remain usable at $width with text scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, height);
        addTearDown(tester.view.reset);
        final app = createApp();
        app.machineStates['m']!.nodeOnline = true;
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: grid.buildAppTheme(brightness: Brightness.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: SwarmScreen(notifier: app, nativeTabs: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final findCard = find.byKey(const ValueKey('welcome-find-agent'));
        final createCard = find.byKey(const ValueKey('welcome-create-agent'));
        final field = find.byKey(const ValueKey('swarm-welcome-search-input'));
        expect(find.text('Find an agent'), findsOneWidget);
        expect(find.text('Create a new agent'), findsOneWidget);
        expect(find.text('Machines'), findsNothing);
        expect(find.text('Projects'), findsNothing);
        expect(
          find.byKey(const ValueKey('swarm-add-agent-button')),
          findsNothing,
        );
        final findRect = tester.getRect(findCard);
        final createRect = tester.getRect(createCard);
        if (width == 1280) {
          expect(createRect.left, greaterThan(findRect.right));
          expect(createRect.top, findRect.top);
          expect(createRect.height, closeTo(findRect.height, 1));
        } else {
          expect(createRect.top, greaterThan(findRect.bottom));
        }
        expect(tester.takeException(), isNull);
        final output = Platform.environment['HARNESS_WELCOME_CAPTURE_DIR'];
        if (output != null) {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/welcome-${width.toInt()}-${scale.toStringAsFixed(1)}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.enterText(field, 'Test host');
        await tester.pump();
        final results = find.byKey(
          const ValueKey('swarm-welcome-search-results'),
        );
        expect(results, findsOneWidget);
        expect(tester.getRect(results).width, tester.getRect(field).width);
        expect(
          find.byKey(const ValueKey('swarm-search-preview')),
          findsNothing,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('swarm-start-primary')),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      },
    );
  }
}
