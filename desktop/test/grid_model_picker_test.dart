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
  _Conn(this.models)
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'local',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  final List<Map<String, Object?>> models;

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async => {'gridName': models.isEmpty ? null : 'someone-7f3a91c4', 'models': models};
}

void main() {
  late AppNotifier notifier;

  void build({List<Map<String, Object?>> models = const []}) {
    notifier = AppNotifier(
      config: AppConfig.dev,
      authSession: AuthSession(),
      configStore: null,
      connectionForTest: (_) => _Conn(models),
    );
  }

  setUp(() => build());
  tearDown(() => notifier.dispose());

  Future<void> open(
    WidgetTester tester, {
    String? currentModel,
    GridWebSearch? webSearch,
    VoidCallback? onOwnLogin,
    ValueChanged<GridModel>? onSelected,
    VoidCallback? onRunLocalModel,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: GridModelPicker(
            notifier: notifier,
            machineId: 'local',
            engineLabel: 'claude',
            currentModel: currentModel,
            webSearch: webSearch,
            onUseOwnLogin: onOwnLogin,
            onSelected: onSelected,
            onRunLocalModel: onRunLocalModel,
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Model'));
    // The menu waits on the grid read AND the usage read; settle covers both plus the open animation.
    await tester.pumpAndSettle();
  }

  testWidgets('shows both sections, and the way back is in the first one', (tester) async {
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

  testWidgets('no grid at all says so; an empty grid says nothing — the run row is the answer', (tester) async {
    // The daemon answers `{gridName: null, models: []}` when it cannot reach a grid at all: that
    // sends you to sign in, which the run row cannot do for you. An empty grid gets no sentence —
    // the "Run a local model" row under Local is what a person does about it.
    await open(tester);
    expect(find.textContaining('sign in again'), findsOneWidget);
    // The user's vocabulary is "Local models", never "grid" — the grid is how a Local model is
    // served, not a thing the picker asks anyone to know about.
    expect(find.text('No local models on this account yet — sign in again to set them up.'), findsOneWidget);
    expect(find.textContaining('grid'), findsNothing);
  });

  testWidgets('a served model shows under Local with the machine answering it', (tester) async {
    build(models: [
      {'id': 'Qwen3.6-35B-A3B-UD-Q5_K_XL', 'node': 'macbook-m1max'},
    ]);
    GridModel? picked;
    await open(tester, onSelected: (m) => picked = m);

    expect(find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'), findsOneWidget);
    // The node is what makes a PRIVATE grid legible: it names which of the user's own machines
    // answers, which is the whole difference from a model on somebody else's grid.
    expect(find.text('macbook-m1max'), findsOneWidget);

    await tester.tap(find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'));
    await tester.pumpAndSettle();
    expect(picked?.id, 'Qwen3.6-35B-A3B-UD-Q5_K_XL');
  });

  testWidgets('a long model id is not truncated while space sits beside it', (tester) async {
    // ⚠️ REGRESSION. The status column used to take the flexible half, which cut
    // `Qwen3.6-35B-A3B-UD-Q5_K_XL` down to `Qwen3.6-35B-A3B-UD-Q5_K…` with empty menu beside it.
    // The long string in this menu is the model id, so the model id is what gets the room.
    build(models: [
      {'id': 'Qwen3.6-35B-A3B-UD-Q5_K_XL', 'node': 'macbook-m1max'},
    ]);
    await open(tester);

    final title = tester.widget<Text>(find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'));
    expect(title.overflow, TextOverflow.ellipsis); // still guarded for a truly absurd name
    final rendered = tester.renderObject<RenderBox>(find.text('Qwen3.6-35B-A3B-UD-Q5_K_XL'));
    // Laid out at its natural width rather than clipped: the painted box is as wide as the string
    // wants, which is the thing that was failing.
    expect(rendered.size.width, greaterThan(160));
  });

  testWidgets('the current row is marked by a highlight, not by a tick column', (tester) async {
    // The tick reserved a fixed column at the start of EVERY row to keep labels aligned, which cost
    // every row that indent for one row's sake. Filling the current row instead says the same thing
    // and gives the space back.
    build(models: [
      {'id': 'Qwen3.6-35B-A3B-UD-Q5_K_XL', 'node': 'macbook-m1max'},
    ]);
    await open(tester, currentModel: 'Qwen3.6-35B-A3B-UD-Q5_K_XL');

    expect(find.byIcon(Icons.check), findsNothing);

    Container rowFor(String text) => tester.widget<Container>(
      find.ancestor(of: find.text(text), matching: find.byType(Container)).first,
    );
    // The selected row is filled; the other is not.
    expect((rowFor('Qwen3.6-35B-A3B-UD-Q5_K_XL').decoration as BoxDecoration?)?.color, isNotNull);
    expect(rowFor('Anthropic').decoration, isNull);
  });

  testWidgets('choosing the engine login only fires when the agent is NOT already on it', (tester) async {
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
  });

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

    testWidgets('is there when nothing is served, and when there is no grid at all', (tester) async {
      // The empty-state sentence is the sentence this row answers, so the row is under it — and it
      // is there even with no grid, because a person with no Local models is exactly who needs it.
      await open(tester);
      expect(find.text('Run a local model'), findsOneWidget);
      final row = tester.getTopLeft(find.text('Run a local model'));
      final sentence = tester.getTopLeft(find.textContaining('sign in again'));
      expect(row.dy, greaterThan(sentence.dy));
      // Never the plumbing's name, in this row as in the rest of the menu.
      expect(find.textContaining('grid'), findsNothing);
    });

    testWidgets('is never filled: an action is nowhere, so it cannot be the current row', (tester) async {
      build(models: served);
      await open(tester, currentModel: 'Qwen-Test');
      expect(find.byIcon(Icons.check), findsNothing);
      Container rowFor(String text) => tester.widget<Container>(
        find.ancestor(of: find.text(text), matching: find.byType(Container)).first,
      );
      expect((rowFor('Qwen-Test').decoration as BoxDecoration?)?.color, isNotNull);
      expect(rowFor('Run a local model').decoration, isNull);
    });

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
      await open(tester, currentModel: 'Qwen-Test', webSearch: GridWebSearch.on);
      expect(find.textContaining('Web search'), findsNothing);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Where this agent runs');
    });

    testWidgets('says nothing when the daemon said nothing', (tester) async {
      build(models: served);
      await open(tester, currentModel: 'Qwen-Test');
      expect(find.textContaining('Web search'), findsNothing);
    });

    testWidgets('a subtitle under the current row, and the tooltip, when it is unavailable', (tester) async {
      build(models: served);
      await open(tester, currentModel: 'Qwen-Test', webSearch: GridWebSearch.unavailable);
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
    });

    testWidgets('the other sentence when the engine cannot take it', (tester) async {
      build(models: served);
      await open(tester, currentModel: 'Qwen-Test', webSearch: GridWebSearch.unsupported);
      expect(find.text('Web search not supported by this engine'), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Where this agent runs\nWeb search not supported by this engine',
      );
    });

    testWidgets('never under the Subscription row, which has its own web tools', (tester) async {
      // A stale status with no current model (the agent came home, the frame has not caught up):
      // the subscription row must not inherit a sentence about a launch it was never part of.
      build(models: served);
      await open(tester, currentModel: null, webSearch: GridWebSearch.unavailable);
      expect(find.textContaining('Web search'), findsNothing);
    });
  });
}
