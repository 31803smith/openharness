// The pane header's model picker: two sections, the way back always offered, and a tick that says
// where the agent actually is.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/grid_model_picker.dart';
import 'package:harness/ws/ws_conn.dart';

/// A connection that answers the picker's one RPC immediately. Without it the menu waits out the
/// request's own 12-second timeout, and a spinner that never stops means `pumpAndSettle` never
/// returns — the test would be measuring the timeout rather than the menu.
class _Conn extends WsConn {
  _Conn(
    this.models, {
    this.localModelEngines,
    this.gridName,
    this.fails = false,
  }) : super(
         wsBaseUrl: 'ws://fixture.invalid',
         autonomousEnv: 'test',
         machineId: 'local',
         accessTokenProvider: (_, _) async => '',
         onAuthFailure: (_) {},
         onEvent: (_) {},
         onStatus: (_) {},
       );

  final List<Map<String, Object?>> models;

  /// The daemon's list of engines a Local model can be offered to; null = an older daemon that
  /// sends no such field.
  final List<String>? localModelEngines;

  /// The grid this account has, independent of what it is serving — so "a grid serving nothing" can
  /// be told apart from "no grid".
  final String? gridName;

  /// Make the request FAIL, the way an offline machine or a daemon too old for the call does.
  final bool fails;

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (fails) throw StateError('grid_models_list_result: UNSUPPORTED');
    return {
      'gridName': gridName ?? (models.isEmpty ? null : 'someone-7f3a91c4'),
      'models': models,
      if (localModelEngines != null) 'localModelEngines': localModelEngines,
    };
  }
}

void main() {
  late AppNotifier notifier;

  void build({
    List<Map<String, Object?>> models = const [],
    List<String>? localModelEngines,
    String? gridName,
    bool fails = false,
  }) {
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      connectionForTest: (_) => _Conn(
        models,
        localModelEngines: localModelEngines,
        gridName: gridName,
        fails: fails,
      ),
    );
  }

  setUp(() => build());
  tearDown(() => notifier.dispose());

  Future<void> open(
    WidgetTester tester, {
    String? currentModel,
    GridWebSearch? webSearch,
    String engine = 'claude',
    VoidCallback? onOwnLogin,
    ValueChanged<GridModel>? onSelected,
    VoidCallback? onRunLocalModel,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GridModelPicker(
              notifier: notifier,
              machineId: 'local',
              engineLabel: engine,
              currentModel: currentModel,
              webSearch: webSearch,
              onUseOwnLogin: onOwnLogin,
              onSelected: onSelected,
              onRunLocalModel: onRunLocalModel,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Model'));
    // The menu waits on the grid read AND the usage read; settle covers both plus the open animation.
    await tester.pumpAndSettle();
  }

  testWidgets('shows both sections, and the way back is in the first one', (
    tester,
  ) async {
    await open(tester);

    // The two sections this picker has, and NOT the API section the window's own Models menu
    // carries — this control cannot put an agent on an API provider, so offering one would be a
    // choice that goes nowhere.
    expect(find.text('Subscription'), findsOneWidget);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('API'), findsNothing);

    // A picker that can only move an agent ONTO a grid is a one-way door, so the engine's own login
    // is always the first row. It is named the way the window's own Models menu names it — by
    // PROVIDER ('Anthropic'), not by engine ('Claude') — so the two controls agree about what the
    // thing is called, and it carries that menu's status text beside it.
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.textContaining('usage'), findsOneWidget);
  });

  // THREE situations, two sentences and one silence, one test each — a single test cannot cover
  // them, because re-pumping the same widget reuses the State and the picker answers from the memo
  // it already has. Only the middle one is about the ACCOUNT, and folding the first two together is
  // what told a signed-in user to "sign in again" when the real problem was a daemon that had not
  // answered: advice that was wrong, and useless even if the diagnosis had been right. The third
  // says nothing: the "Run a local model" row under Local is what a person does about it.
  testWidgets(
    'a machine that did not answer says so, and does not blame the account',
    (tester) async {
      build(fails: true);
      await open(tester);
      expect(find.text('Could not reach this machine.'), findsOneWidget);
      expect(find.textContaining('sign in'), findsNothing);
    },
  );

  testWidgets('an account with no grid says there are no local models yet', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('No local models on this account yet.'), findsOneWidget);
    // The user's vocabulary is "Local models", never "grid" — the grid is how a Local model is
    // served, not a thing the picker asks anyone to know about.
    expect(find.textContaining('grid'), findsNothing);
  });

  testWidgets(
    'a grid serving nothing says nothing — the run row is the answer',
    (tester) async {
      build(gridName: 'someone-7f3a91c4');
      await open(tester);
      expect(find.text('Nothing is being served yet.'), findsNothing);
      expect(find.text('Could not reach this machine.'), findsNothing);
      expect(find.text('Run a local model'), findsOneWidget);
    },
  );

  // `Positioned` hands down unbounded width, so a stretching Column takes every pixel its constraints
  // allow — a two-line menu wore the width of the longest model id it could ever hold. The minimum is
  // what keeps a status off a model id; the maximum is a CEILING, not a target. One test each, because
  // re-pumping reuses the State and the second open would answer from the first one's memo.
  testWidgets('a short menu is not as wide as the widest menu could be', (
    tester,
  ) async {
    await open(tester);
    final width = tester.getSize(find.byType(Material).last).width;
    expect(
      width,
      greaterThanOrEqualTo(340),
      reason: 'a status still clears a model id',
    );
    expect(
      width,
      lessThan(540),
      reason: 'and nothing is padded out to the ceiling',
    );
  });

  testWidgets('a long model id is given room, up to the ceiling', (
    tester,
  ) async {
    build(
      models: [
        {
          'id': 'Qwen3.6-35B-A3B-UD-Q5_K_XL-with-a-deliberately-long-tail',
          'node': 'macbook-m1max',
        },
      ],
    );
    await open(tester);
    final width = tester.getSize(find.byType(Material).last).width;
    expect(
      width,
      greaterThan(340),
      reason: 'a row longer than the minimum asks for more',
    );
    expect(
      width,
      lessThanOrEqualTo(540),
      reason: 'and never more than the ceiling',
    );
  });

  testWidgets(
    'a click outside closes the menu AND reaches what it was aimed at',
    (tester) async {
      // `showMenu` puts a modal barrier under the menu and that barrier EATS the dismissing click, so
      // closing the menu and then pressing a button took two clicks with the first going nowhere.
      var pressed = 0;
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 400,
                  child: ElevatedButton(
                    onPressed: () => pressed += 1,
                    child: const Text('underneath'),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: GridModelPicker(
                    notifier: notifier,
                    machineId: 'local',
                    engineLabel: 'claude',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Model'));
      await tester.pumpAndSettle();
      expect(find.text('Subscription'), findsOneWidget);

      await tester.tap(find.text('underneath'));
      await tester.pumpAndSettle();

      expect(
        find.text('Subscription'),
        findsNothing,
        reason: 'the menu closes',
      );
      expect(
        pressed,
        1,
        reason: 'and the same click lands on the button under it',
      );
    },
  );

  testWidgets('the control says it is clickable before it is clicked', (
    tester,
  ) async {
    // The pane header sits over a terminal, and without this the cursor over the control was
    // whatever the surface underneath asked for — so a menu control did not look like one.
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: GridModelPicker(
              notifier: notifier,
              machineId: 'local',
              engineLabel: 'claude',
            ),
          ),
        ),
      ),
    );
    // The control prefetches on mount; settle so the test is not measuring that work's timers.
    await tester.pumpAndSettle();

    // BOTH annotations, because the innermost one under the pointer is what a person actually sees:
    // InkWell installs its own MouseRegion, so an ancestor asking for a hand does not decide alone.
    //
    // ⚠️ This asserts the widgets' contract, NOT the cursor the OS ends up drawing. Reading that back
    // through `MouseTracker.debugDeviceActiveCursor` does not work in this harness — a bare
    // `MouseRegion(cursor: click)` over a plain box resolves to `basic` there — so a test written
    // that way would have been measuring the harness rather than the app.
    final region = tester.widget<MouseRegion>(
      find
          .ancestor(
            of: find.byType(InkWell),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    expect(region.cursor, SystemMouseCursors.click);
    expect(
      tester.widget<InkWell>(find.byType(InkWell)).mouseCursor,
      SystemMouseCursors.click,
    );
  });

  testWidgets(
    'a served model shows under Local with the machine answering it',
    (tester) async {
      build(
        models: [
          {'id': 'Qwen3.6-35B-A3B-UD-Q5_K_XL', 'node': 'macbook-m1max'},
        ],
      );
      GridModel? picked;
      await open(tester, onSelected: (m) => picked = m);

      expect(find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'), findsOneWidget);
      // The node is what makes a PRIVATE grid legible: it names which of the user's own machines
      // answers, which is the whole difference from a model on somebody else's grid.
      expect(find.text('macbook-m1max'), findsOneWidget);

      await tester.tap(find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'));
      await tester.pumpAndSettle();
      expect(picked?.id, 'Qwen3.6-35B-A3B-UD-Q5_K_XL');
    },
  );

  testWidgets('a long model id is not truncated while space sits beside it', (
    tester,
  ) async {
    // ⚠️ REGRESSION. The status column used to take the flexible half, which cut
    // `Qwen3.6-35B-A3B-UD-Q5_K_XL` down to `Qwen3.6-35B-A3B-UD-Q5_K…` with empty menu beside it.
    // The long string in this menu is the model id, so the model id is what gets the room.
    build(
      models: [
        {'id': 'Qwen3.6-35B-A3B-UD-Q5_K_XL', 'node': 'macbook-m1max'},
      ],
    );
    await open(tester);

    final title = tester.widget<Text>(find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'));
    expect(
      title.overflow,
      TextOverflow.ellipsis,
    ); // still guarded for a truly absurd name
    final rendered = tester.renderObject<RenderBox>(
      find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'),
    );
    // Laid out at its natural width rather than clipped: the painted box is as wide as the string
    // wants, which is the thing that was failing.
    expect(rendered.size.width, greaterThan(160));
  });

  testWidgets(
    'the current row is marked by a highlight, not by a tick column',
    (tester) async {
      // The tick reserved a fixed column at the start of EVERY row to keep labels aligned, which cost
      // every row that indent for one row's sake. Filling the current row instead says the same thing
      // and gives the space back.
      build(
        models: [
          {'id': 'Qwen3.6-35B-A3B-UD-Q5_K_XL', 'node': 'macbook-m1max'},
        ],
      );
      await open(tester, currentModel: 'Qwen3.6-35B-A3B-UD-Q5_K_XL');

      expect(find.byIcon(Icons.check), findsNothing);

      Container rowFor(String text) => tester.widget<Container>(
        find
            .ancestor(of: find.text(text), matching: find.byType(Container))
            .first,
      );
      // The selected row is filled; the other is not.
      expect(
        (rowFor('Qwen3.6-35B-A3B-UD-Q5_K_XL').decoration as BoxDecoration?)
            ?.color,
        isNotNull,
      );
      expect(rowFor('Anthropic').decoration, isNull);
    },
  );

  testWidgets(
    'choosing the engine login only fires when the agent is NOT already on it',
    (tester) async {
      var calls = 0;
      // Already on its own login: re-selecting it would respawn the pane for nothing.
      await open(tester, currentModel: null, onOwnLogin: () => calls++);
      await tester.tap(find.text('Anthropic'));
      await tester.pumpAndSettle();
      expect(calls, 0);

      // On a grid model: now it has somewhere to go.
      await open(tester, currentModel: 'Qwen-Test', onOwnLogin: () => calls++);
      await tester.tap(find.text('Anthropic'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  group('the last row under Local starts a local model', () {
    const served = [
      {'id': 'Qwen-Test', 'node': 'macbook-m1max'},
    ];

    testWidgets('is there after the served models', (tester) async {
      build(models: served);
      await open(tester);
      expect(find.text('Run a local model'), findsOneWidget);
      // After the models, not among them: it is the way to get another one, and a row that
      // started something sitting between two places the agent could go would read as a third.
      final row = tester.getTopLeft(find.text('Run a local model'));
      final model = tester.getTopLeft(find.text('Qwen-Test'));
      expect(row.dy, greaterThan(model.dy));
    });

    testWidgets(
      'is there when nothing is served, and when there is no grid at all',
      (tester) async {
        // The empty-state sentence is the sentence this row answers, so the row is under it — and it
        // is there even with no grid, because a person with no Local models is exactly who needs it.
        await open(tester);
        expect(find.text('Run a local model'), findsOneWidget);
        final row = tester.getTopLeft(find.text('Run a local model'));
        final sentence = tester.getTopLeft(
          find.text('No local models on this account yet.'),
        );
        expect(row.dy, greaterThan(sentence.dy));
        // Never the plumbing's name, in this row as in the rest of the menu.
        expect(find.textContaining('grid'), findsNothing);
      },
    );

    testWidgets(
      'is never filled: an action is nowhere, so it cannot be the current row',
      (tester) async {
        build(models: served);
        await open(tester, currentModel: 'Qwen-Test');
        expect(find.byIcon(Icons.check), findsNothing);
        Container rowFor(String text) => tester.widget<Container>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Container))
              .first,
        );
        expect(
          (rowFor('Qwen-Test').decoration as BoxDecoration?)?.color,
          isNotNull,
        );
        expect(rowFor('Run a local model').decoration, isNull);
      },
    );

    testWidgets('fires onRunLocalModel and nothing else', (tester) async {
      build(models: served);
      var runs = 0;
      var logins = 0;
      GridModel? picked;
      await open(
        tester,
        currentModel: 'Qwen-Test',
        onRunLocalModel: () => runs++,
        onOwnLogin: () => logins++,
        onSelected: (m) => picked = m,
      );
      await tester.tap(find.text('Run a local model'));
      await tester.pumpAndSettle();
      expect(runs, 1);
      // Not a move: the agent stays where it was. `currentModel` is set so a stray own-login call
      // would have fired — the case where it is silent for its own reason is not the one tested.
      expect(logins, 0);
      expect(picked, isNull);
      // The menu closed on the choice, like any other row.
      expect(find.text('Run a local model'), findsNothing);
    });
  });

  group('web search on the current Local model', () {
    const served = [
      {'id': 'Qwen-Test', 'node': 'macbook-m1max'},
      {'id': 'Other-Model', 'node': 'macbook-m1max'},
    ];

    testWidgets('says nothing when it is on', (tester) async {
      build(models: served);
      await open(
        tester,
        currentModel: 'Qwen-Test',
        webSearch: GridWebSearch.on,
      );
      expect(find.textContaining('Web search'), findsNothing);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Where this agent runs',
      );
    });

    testWidgets('says nothing when the daemon said nothing', (tester) async {
      build(models: served);
      await open(tester, currentModel: 'Qwen-Test');
      expect(find.textContaining('Web search'), findsNothing);
    });

    testWidgets(
      'a subtitle under the current row, and the tooltip, when it is unavailable',
      (tester) async {
        build(models: served);
        await open(
          tester,
          currentModel: 'Qwen-Test',
          webSearch: GridWebSearch.unavailable,
        );
        expect(find.text('Web search unavailable'), findsOneWidget);
        // Under the CURRENT model, not every model: the status is about this agent's launch, and the
        // other rows are places it could go, about which nothing is yet known.
        final subtitle = tester.getTopLeft(find.text('Web search unavailable'));
        final current = tester.getTopLeft(find.text('Qwen-Test'));
        final other = tester.getTopLeft(find.text('Other-Model'));
        expect(subtitle.dy, greaterThan(current.dy));
        expect(subtitle.dy, lessThan(other.dy));
        expect(
          tester.widget<Tooltip>(find.byType(Tooltip)).message,
          'Where this agent runs\nWeb search unavailable',
        );
      },
    );

    testWidgets('the other sentence when the engine cannot take it', (
      tester,
    ) async {
      build(models: served);
      await open(
        tester,
        currentModel: 'Qwen-Test',
        webSearch: GridWebSearch.unsupported,
      );
      expect(
        find.text('Web search not supported by this engine'),
        findsOneWidget,
      );
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Where this agent runs\nWeb search not supported by this engine',
      );
    });

    testWidgets(
      'never under the Subscription row, which has its own web tools',
      (tester) async {
        // A stale status with no current model (the agent came home, the frame has not caught up):
        // the subscription row must not inherit a sentence about a launch it was never part of.
        build(models: served);
        await open(
          tester,
          currentModel: null,
          webSearch: GridWebSearch.unavailable,
        );
        expect(find.textContaining('Web search'), findsNothing);
      },
    );
  });

  group('an engine that cannot run on a Local model', () {
    const served = [
      {'id': 'qwen/qwen3.6-35b-a3b', 'node': 'macbook-m1max'},
    ];
    const capable = [
      'claude',
      'codex',
      'opencode',
      'hermes',
      'grok',
      'pi',
      'copilot',
    ];

    testWidgets('is told so under Local, and offered no rows', (tester) async {
      // The daemon refuses a Cursor retarget (`GRID_ENGINE_UNSUPPORTED`): Cursor Agent can only be
      // re-pointed at another Cursor API. Offering the row anyway was a dead end that said nothing.
      build(models: served, localModelEngines: capable);
      GridModel? picked;
      await open(tester, engine: 'cursor', onSelected: (m) => picked = m);
      expect(
        find.text('Cursor can only run on its own login.'),
        findsOneWidget,
      );
      expect(find.text('qwen/qwen3.6-35b-a3b'), findsNothing);
      expect(picked, isNull);
    });

    testWidgets('a capable engine still gets the rows', (tester) async {
      build(models: served, localModelEngines: capable);
      await open(tester, engine: 'codex');
      expect(find.text('qwen/qwen3.6-35b-a3b'), findsOneWidget);
      expect(find.textContaining('own login'), findsNothing);
    });

    testWidgets(
      'an older daemon that names no engines offers everything, as before',
      (tester) async {
        build(models: served);
        await open(tester, engine: 'cursor');
        expect(find.text('qwen/qwen3.6-35b-a3b'), findsOneWidget);
      },
    );
  });
}
