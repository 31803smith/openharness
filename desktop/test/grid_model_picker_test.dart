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
    VoidCallback? onOwnLogin,
    ValueChanged<GridModel>? onSelected,
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
            onUseOwnLogin: onOwnLogin,
            onSelected: onSelected,
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

  testWidgets('an empty grid says nobody is serving, not that there is no grid', (tester) async {
    // The daemon answers `{gridName: null, models: []}` when it cannot reach a grid at all, and
    // these two facts need different sentences — one sends you to sign in, the other to serve a
    // model. A single "no models" would send a person looking in the wrong place.
    await open(tester);
    expect(find.textContaining('sign in again'), findsOneWidget);
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
}
