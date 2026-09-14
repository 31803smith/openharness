import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shared/layouts/window_size.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/swarm_tab_strip.dart';

import 'swarm_state_test.dart' show createApp;

/// A tab carries a 2pt right margin inside its own box, so measuring the tab
/// measures the margin with it.
const double _margin = 2;

AppNotifier _appWith(int swarms) {
  final app = createApp();
  while (app.swarms.length < swarms) {
    app.newSwarm();
  }
  addTearDown(app.dispose);
  return app;
}

/// Sizes the WINDOW rather than wrapping the strip in a box: a `SizedBox` wider
/// than the test surface is silently clamped back to it, which would have every
/// wide case here quietly measuring 800pt instead.
Future<void> _mount(
  WidgetTester tester,
  AppNotifier app,
  double width, {
  VoidCallback? onNavigate,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SwarmTabStrip(
            notifier: app,
            attention: 0,
            onRename: (_) {},
            onNavigate: onNavigate ?? () {},
            onNotifications: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _tabWidth(WidgetTester tester, AppNotifier app) =>
    tester.getSize(find.byKey(ValueKey(app.swarms.first.id)).first).width -
    _margin;

void main() {
  testWidgets('a window with room draws every tab at its full width', (
    tester,
  ) async {
    final app = _appWith(2);
    await _mount(tester, app, 1400);

    expect(_tabWidth(tester, app), SwarmTabStrip.maxTabWidth);
  });

  testWidgets('tabs give up width before the strip starts scrolling', (
    tester,
  ) async {
    final app = _appWith(8);
    await _mount(tester, app, 1400);

    final width = _tabWidth(tester, app);
    expect(width, lessThan(SwarmTabStrip.maxTabWidth));
    expect(width, greaterThan(SwarmTabStrip.minTabWidth));
  });

  testWidgets('a tab stops shrinking at the width that still holds a name', (
    tester,
  ) async {
    final app = _appWith(24);
    await _mount(tester, app, 500);

    expect(_tabWidth(tester, app), SwarmTabStrip.minTabWidth);
  });

  testWidgets('a wide strip keeps every action out as a button', (
    tester,
  ) async {
    await _mount(tester, _appWith(2), 1400);

    expect(find.byKey(const ValueKey('swarm-search-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('swarm-notifications-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swarm-overflow-button')), findsNothing);
  });

  testWidgets('a compact strip folds the actions away but keeps the badge', (
    tester,
  ) async {
    await _mount(tester, _appWith(2), WindowSizeClass.compactMax - 1);

    expect(find.byKey(const ValueKey('swarm-search-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('swarm-notifications-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('swarm-overflow-button')), findsOneWidget);
  });

  testWidgets('the folded actions still run from the overflow menu', (
    tester,
  ) async {
    var navigated = 0;
    await _mount(tester, _appWith(2), 420, onNavigate: () => navigated++);

    await tester.tap(find.byKey(const ValueKey('swarm-overflow-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Navigate'));
    await tester.pumpAndSettle();

    expect(navigated, 1);
  });
}
