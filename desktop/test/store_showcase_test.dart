// A store product page shows what a harness does: an example's prompt beside a picture of what it
// made, and "Try this prompt" opens New Harness with that prompt as the first message.
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/dsh_catalog.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/core/project_folder.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/state/pane_arrangement.dart';
import 'package:harness/store/store_showcase.dart';
import 'package:harness/widgets/new_agent_dialog.dart';

import 'swarm_state_test.dart' show createApp;

const _lamp = StoreExample(
  prompt: 'A desk lamp with a weighted base and an arm that folds flat.',
  image: 'https://example.com/lamp.jpg',
  caption: 'Desk lamp · 9 parts',
);
const _gear = StoreExample(
  prompt: 'A planetary gearbox, 5:1, printable without supports.',
  caption: 'Gearbox · STEP',
);

const _blender = DshEntry(
  id: 'autonomous/blender',
  name: 'Blender',
  engine: 'claude',
  installed: true,
  category: '3D',
  tier: 2,
  examples: [_lamp, _gear],
);

class _Folders extends FileSelectorPlatform {
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async => '/work/lamp';
}

class _Notifier extends AppNotifier {
  _Notifier()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );

  final prompts = <String?>[];

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}

  @override
  Future<void> probeDsh(String machineId, {bool force = false}) async {}

  @override
  Future<Map<String, dynamic>> listCodexProfiles(
    String machineId, {
    Set<String> observedPaths = const {},
  }) async => {'profiles': <dynamic>[]};

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    bool bypassPermission = false,
    String? permissionMode,
    String? codexHome,
    String? dsh,
    String? prompt,
    String? name,
    String? agent,
    ProjectFolderRequest? projectFolder,
    String? swarmId,
    PaneSplitRequest? split,
    AgentCreationAttempt? attempt,
  }) async {
    prompts.add(prompt);
    return 'Test launch refused.';
  }
}

String _promptText(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('store-showcase-prompt')))
    .textSpan!
    .toPlainText();

/// What has been typed so far: the rest of the prompt is laid out but transparent.
String _typedText(WidgetTester tester) =>
    (tester
                .widget<Text>(
                  find.byKey(const ValueKey('store-showcase-prompt')),
                )
                .textSpan!
            as TextSpan)
        .children!
        .first
        .toPlainText();

Future<void> _pumpShowcase(
  WidgetTester tester, {
  ValueChanged<String>? onTry,
  bool? autoAdvance,
  List<StoreExample> examples = const [_lamp, _gear],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StoreShowcase(
            entry: _blender,
            examples: examples,
            onTry: onTry,
            autoAdvance: autoAdvance,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('StoreExample', () {
    test('keeps a prompt, an https picture and a short caption', () {
      final example = StoreExample.fromJson({
        'prompt': '  A lamp  ',
        'image': 'https://example.com/lamp.jpg',
        'caption': 'x' * 200,
      })!;
      expect(example.prompt, 'A lamp');
      expect(example.image, 'https://example.com/lamp.jpg');
      expect(example.caption, hasLength(120));
    });

    test(
      'drops a picture that is not https, and an example with no prompt',
      () {
        expect(
          StoreExample.fromJson({
            'prompt': 'A lamp',
            'image': 'http://example.com/lamp.jpg',
          })!.image,
          isNull,
        );
        expect(
          StoreExample.fromJson({
            'prompt': 'A lamp',
            'image': 'file:///etc/passwd',
          })!.image,
          isNull,
        );
        expect(StoreExample.fromJson({'prompt': '  '}), isNull);
        expect(
          StoreExample.fromJson({'image': 'https://example.com/a.jpg'}),
          isNull,
        );
        expect(StoreExample.fromJson('A lamp'), isNull);
      },
    );

    test('a catalog row carries at most eight examples and skips bad ones', () {
      final entry = DshEntry.fromJson({
        'id': 'autonomous/blender',
        'name': 'Blender',
        'engine': 'claude',
        'examples': [
          {'prompt': 'One'},
          'nonsense',
          for (var i = 0; i < 10; i++) {'prompt': 'More $i'},
        ],
      })!;
      expect(entry.examples, hasLength(8));
      expect(entry.examples.first.prompt, 'One');
      expect(entry.examples[1].prompt, 'More 0');
    });
  });

  testWidgets('shows the first example whole, and a strip picks another', (
    tester,
  ) async {
    await _pumpShowcase(tester);
    expect(_promptText(tester), '“${_lamp.prompt}”');
    expect(find.text('Desk lamp · 9 parts'), findsOneWidget);
    expect(find.text('YOU ASK'), findsOneWidget);
    expect(find.text('IT MAKES'), findsOneWidget);
    expect(find.text('Blender harness'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('store-example:1')));
    await tester.pumpAndSettle();
    expect(_promptText(tester), '“${_gear.prompt}”');
    expect(find.text('Gearbox · STEP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one example needs no strip', (tester) async {
    await _pumpShowcase(tester, examples: const [_lamp]);
    expect(find.byKey(const ValueKey('store-example:0')), findsNothing);
  });

  testWidgets('Try this prompt hands over the prompt on screen', (
    tester,
  ) async {
    final tried = <String>[];
    await _pumpShowcase(tester, onTry: tried.add);
    await tester.tap(find.byKey(const ValueKey('store-try-prompt')));
    await tester.tap(find.byKey(const ValueKey('store-example:1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('store-try-prompt')));
    expect(tried, [_lamp.prompt, _gear.prompt]);
  });

  testWidgets('Try this prompt is off with nowhere to open it', (tester) async {
    await _pumpShowcase(tester);
    final button = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Try this prompt'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Copy puts the prompt on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpShowcase(tester);
    await tester.tap(find.byKey(const ValueKey('store-copy-prompt')));
    await tester.pump();
    expect(copied, _lamp.prompt);
  });

  testWidgets(
    'playing, it types the prompt, then moves on to the next example',
    (tester) async {
      await _pumpShowcase(tester, autoAdvance: true);
      await tester.pump(const Duration(milliseconds: 300));
      final typing = _typedText(tester);
      expect(
        typing.length,
        lessThan('“${_lamp.prompt}”'.length),
        reason: 'still typing',
      );
      expect(typing, startsWith('“A desk'));

      await tester.pump(const Duration(seconds: 3)); // typed and revealed
      await tester.pump(const Duration(seconds: 1));
      expect(_promptText(tester), '“${_lamp.prompt}”');
      await tester.pump(const Duration(seconds: 7)); // seen for a while
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      expect(_promptText(tester), '“${_gear.prompt}”');

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Reduce Motion shows it whole and stays put', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              child: StoreShowcase(
                entry: _blender,
                examples: const [_lamp, _gear],
                autoAdvance: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_promptText(tester), '“${_lamp.prompt}”');
    await tester.pump(const Duration(seconds: 30));
    expect(_promptText(tester), '“${_lamp.prompt}”');
  });

  testWidgets('narrow, the prompt sits above the picture', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(520, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StoreShowcase(entry: _blender, examples: [_lamp, _gear]),
          ),
        ),
      ),
    );
    await tester.pump();
    final prompt = tester.getRect(
      find.byKey(const ValueKey('store-showcase-prompt')),
    );
    final picture = tester.getRect(find.text('IT MAKES'));
    expect(picture.top, greaterThan(prompt.bottom));
    expect(tester.takeException(), isNull);
  });

  group('New Harness with a first message', () {
    setUp(() => FileSelectorPlatform.instance = _Folders());

    Future<_Notifier> open(WidgetTester tester) async {
      final notifier = _Notifier();
      addTearDown(notifier.dispose);
      const machine = Machine(
        machineId: 'machine-1',
        authMode: MachineAuthMode.remote,
        name: 'harness-remote-box',
      );
      final state = MachineState(machine)..localOnly = true;
      state.engines.replace(const [
        EngineAvailability(engine: 'claude', installed: true),
      ]);
      state.dsh.replace(const [_blender]);
      notifier.machineStates['machine-1'] = state;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showNewAgentDialog(
                  context,
                  notifier,
                  'machine-1',
                  source: 'store',
                  initialEngine: 'autonomous/blender',
                  initialPrompt: '  ${_lamp.prompt}\n',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final newProject = find.byKey(
        const ValueKey('new-agent-folder-newProject'),
      );
      await tester.ensureVisible(newProject);
      await tester.tap(newProject);
      await tester.pumpAndSettle();
      return notifier;
    }

    Future<void> create(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('create-agent-submit')),
      );
      await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
      await tester.pump();
    }

    testWidgets('says what it starts with and sends it', (tester) async {
      final app = await open(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('new-agent-first-message')),
          matching: find.text(_lamp.prompt),
        ),
        findsOneWidget,
      );
      await create(tester);
      expect(app.prompts, [_lamp.prompt]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('starts without it once removed', (tester) async {
      final app = await open(tester);
      await tester.ensureVisible(
        find.byKey(const ValueKey('new-agent-first-message-remove')),
      );
      await tester.tap(
        find.byKey(const ValueKey('new-agent-first-message-remove')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('new-agent-first-message')),
        findsNothing,
      );
      await create(tester);
      expect(app.prompts, [null]);
    });
  });

  testWidgets(
    'the product page leads with the examples and tries one in New Harness',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.reset);
      final app = createApp();
      final state = app.machineStates['m']!
        ..localOnly = true
        ..nodeOnline = true
        ..connectionStatus = ConnectionStatus.connected;
      state.dsh.replace(const [_blender]);
      await app.addAgentToSwarm('m', 'a0');
      app.newSwarm(name: 'Other work');
      app.openStore();
      final storeTab = app.activeSwarm;

      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: SwarmScreen(notifier: app, nativeTabs: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('store-search')),
        'blender',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('store-card:autonomous/blender')).first,
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('store-showcase-stage')),
        findsOneWidget,
      );
      expect(
        find.text('Start with an idea'),
        findsNothing,
        reason: 'the examples replace the bare prompt list',
      );
      await tester.tap(find.byKey(const ValueKey('store-example:1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('store-try-prompt')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('create-agent-submit')),
        findsOneWidget,
        reason: 'New Harness is open',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('new-agent-first-message')),
          matching: find.text(_gear.prompt),
        ),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        app.activeSwarm,
        same(storeTab),
        reason: 'dismissed, back on the store',
      );
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
