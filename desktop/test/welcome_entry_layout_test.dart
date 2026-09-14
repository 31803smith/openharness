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
import 'swarm_screen_test.dart' show terminal;

import 'package:harness/core/models.dart';

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
    (880.0, 560.0, 1.0),
    (600.0, 900.0, 1.7),
  ]) {
    testWidgets(
      'centered start and recent harnesses remain usable at $width with text scale $scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, height);
        addTearDown(tester.view.reset);
        final app = createApp();
        app.machineStates['m']!.nodeOnline = true;
        for (var i = 0; i < 6; i++) {
          final name = [
            'Harness desktop',
            'NYC chess set',
            'Marketing',
            'Landing page',
            'Training H1',
            'New onboarding',
          ][i];
          app.machineStates['m']!.agents[i] = Agent(
            id: 'a$i',
            name: name,
            engine: i.isEven ? 'codex' : 'claude',
            terminalAvailable: true,
          );
          app.adoptSessionForTest(terminal('a$i', []));
        }
        app.newSwarm();
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
        final field = find.byKey(const ValueKey('swarm-welcome-search-input'));
        final create = find.byKey(const ValueKey('swarm-start-primary'));
        expect(find.text('Find a harness'), findsOneWidget);
        expect(find.text('Create a new harness'), findsOneWidget);
        expect(find.text('Recent harnesses'), findsNothing);
        expect(find.text('Harness'), findsOneWidget);
        expect(find.text('or'), findsOneWidget);
        expect(find.byType(Checkbox), findsNothing);
        expect(
          find.byKey(const ValueKey('swarm-add-agent-button')),
          findsNothing,
        );
        final findRect = tester.getRect(field);
        final createRect = tester.getRect(create);
        expect(createRect.top, greaterThan(findRect.bottom));
        expect(findRect.center.dx, closeTo(width / 2, 1));
        expect(findRect.width, closeTo((width - 96).clamp(0, 920), 1));
        if (scale == 1) {
          expect(create.hitTestable(), findsOneWidget);
          expect(createRect.bottom, lessThanOrEqualTo(height));
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
        expect(tester.getRect(results).height, greaterThan(140));
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
