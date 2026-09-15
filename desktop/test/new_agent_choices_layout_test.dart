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
      ('laptop', 'dees-MacBook-Pro.local'),
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
  Future<Map<String, dynamic>> readProjectPreview(
    String machineId,
    String path,
  ) async => {
    'path': path,
    'branch': 'main',
    'changedFiles': 2,
    'readme': '# Harness\nOne window for your coding agents.\n\n## Development\nRun agents on your machines and keep every project within reach.',
    'commit': {
      'subject': 'Simplify the project picker',
      'author': 'Alex',
      'date': '2026-09-15T10:00:00Z',
    },
    'contributors': ['Alex', 'Dee', 'Sam'],
  };

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
    (const Size(1280, 1000), 1.0),
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
      for (final path in [
        '/Users/example/code/workshop',
        '/Users/example/code/website',
        '/Users/example/code/harness',
      ]) {
        await app.projectHistory.select('local', path);
      }
      await app.projectHistory.select('local', null);
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
      for (final id in ['local', 'office', 'home', 'studio', 'laptop']) {
        expect(find.byKey(ValueKey('new-agent-machine-$id')), findsOneWidget);
      }
      for (final id in ['codex', 'claude', 'opencode']) {
        expect(find.byKey(ValueKey('new-agent-quick-$id')), findsOneWidget);
      }
      void expectUniformTiles({bool withKilo = false}) {
        final tile = tester.getSize(
          find.byKey(const ValueKey('new-agent-quick-codex')),
        );
        for (final key in [
          for (final id in ['claude', 'opencode', if (withKilo) 'kilo'])
            'new-agent-quick-$id',
          for (final id in ['local', 'office', 'home', 'studio', 'laptop'])
            'new-agent-machine-$id',
          'new-agent-engine-field',
        ]) {
          expect(tester.getSize(find.byKey(ValueKey(key))), tile, reason: key);
        }
      }

      expectUniformTiles();
      expect(find.text('This machine'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Create'), findsOneWidget);
      final advanced = find.byKey(const Key('new-agent-advanced'));
      await tester.ensureVisible(advanced);
      await tester.tap(advanced);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Bypass approvals'));
      await capture('advanced');
      await tester.ensureVisible(advanced);
      await tester.tap(advanced);
      await tester.pumpAndSettle();
      final bar = find.byKey(const Key('new-agent-project-bar'));
      await tester.ensureVisible(bar);
      await tester.tap(bar);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await capture('projects');
      await tester.enterText(
        find.byKey(const Key('new-agent-project-search')),
        'owner/repo',
      );
      await tester.pumpAndSettle();
      await capture('repository');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('new-agent-machine-studio')),
      );
      await tester.tap(find.byKey(const ValueKey('new-agent-machine-studio')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-agent-machine-home')),
        findsOneWidget,
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
        find.byKey(const ValueKey('new-agent-quick-opencode')),
        findsOneWidget,
      );
      expect(find.text('Kilo'), findsOneWidget);
      expectUniformTiles(withKilo: true);
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
