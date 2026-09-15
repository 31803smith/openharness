import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

import 'support/real_fonts.dart';

class _ChoicesApp extends AppNotifier {
  _ChoicesApp() : super(config: AppConfig.dev, authSession: AuthSession()) {
    for (final (id, name) in [
      ('local', 'iMac - Office'),
      ('office', 'M2'),
      ('home', 'T480 - Omarchy'),
      ('studio', 'Studio'),
    ]) {
      final machine = Machine(
        machineId: id,
        name: name,
        authMode: MachineAuthMode.remote,
      );
      machineStates[id] = MachineState(machine)
        ..localOnly = id == 'local'
        ..nodeOnline = id != 'home'
        ..engines.replace(const [
          EngineAvailability(
            engine: 'codex',
            installed: true,
            supportsCodexHome: true,
          ),
          EngineAvailability(
            engine: 'kilo',
            installed: false,
            installable: true,
          ),
        ]);
    }
  }

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}

  @override
  Future<Map<String, dynamic>> listCodexProfiles(
    String machineId, {
    Set<String> observedPaths = const {},
  }) async => {
    'profiles': [
      {'path': '/home/example/.codex', 'label': 'Personal'},
    ],
  };
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
  });

  for (final (size, scale) in [
    (const Size(900, 720), 1.0),
    (const Size(880, 560), 1.0),
    (const Size(600, 700), 2.0),
  ]) {
    testWidgets('machine and agent choices fit $size at text scale $scale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final app = _ChoicesApp();
      await app.agentPreference.select('codex');
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: grid.buildAppTheme(brightness: Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showNewAgentDialog(context, app, 'local', source: 'test'),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      Future<void> capture(String state) async {
        final output = Platform.environment['HARNESS_CHOICES_CAPTURE_DIR'];
        if (output == null) return;
        await tester.runAsync(() async {
          for (final asset in ['codex.png', 'cursor.png', 'kilo.png']) {
            await precacheImage(
              AssetImage('assets/engine-icons/$asset'),
              boundaryKey.currentContext!,
            );
          }
        });
        await tester.pumpAndSettle();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/${size.width.toInt()}-$scale-$state.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('initial');
      await tester.tap(
        find.byKey(const ValueKey('new-agent-folder-newProject')),
      );
      await tester.pumpAndSettle();
      await capture('new-project');
      await tester.tap(find.byKey(const ValueKey('new-agent-folder-remote')));
      await tester.pumpAndSettle();
      await capture('repository');
      await tester.tap(find.byKey(const ValueKey('new-agent-folder-local')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('new-agent-machine-field')), findsNothing);
      await tester.tap(find.byKey(const Key('new-agent-machine-toggle')));
      await tester.pumpAndSettle();
      await capture('machines');
      for (final label in [
        'iMac - Office',
        if (scale == 1) ...['M2', 'T480 - Omarchy'],
        'Codex',
        'Claude Code',
        'Cursor',
      ]) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label).last)
              .didExceedMaxLines,
          isFalse,
          reason: label,
        );
      }
      if (scale == 1) {
        final machineTop = tester
            .getTopLeft(find.byKey(const ValueKey('new-agent-machine-local')))
            .dy;
        for (final id in ['office', 'home']) {
          expect(
            tester.getTopLeft(find.byKey(ValueKey('new-agent-machine-$id'))).dy,
            machineTop,
          );
        }
        final agentTop = tester
            .getTopLeft(find.byKey(const ValueKey('new-agent-quick-codex')))
            .dy;
        expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('new-agent-quick-cursor')))
              .dy,
          agentTop,
        );
      }
      final visibleMachines = ['local', 'office', 'home']
          .map((id) => find.byKey(ValueKey('new-agent-machine-$id')))
          .where((finder) => finder.evaluate().isNotEmpty);
      final top = tester.getTopLeft(visibleMachines.first).dy;
      for (final choice in visibleMachines) {
        expect(tester.getTopLeft(choice).dy, top);
      }
      expect(
        tester.getTopLeft(find.byKey(const Key('new-agent-machine-more'))).dy,
        top,
      );
      await tester.tap(find.byKey(const Key('new-agent-machine-more')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Studio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Studio'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-agent-machine-studio')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('new-agent-machine-home')),
        findsNothing,
      );
      final moreAgents = find.byKey(const Key('new-agent-engine-field'));
      await tester.ensureVisible(moreAgents);
      await tester.tap(moreAgents);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Kilo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilo'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-agent-quick-kilo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('new-agent-quick-cursor')),
        findsNothing,
      );
      expect(find.text('Kilo'), findsOneWidget);
      expect(
        find.text('Harness will install Kilo before starting.'),
        findsNothing,
      );
      await capture('selected');
      final submit = find.byKey(const ValueKey('create-agent-submit'));
      expect(tester.getRect(submit).bottom, lessThan(size.height));
      expect(tester.takeException(), isNull);
    });
  }
}
