import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/sharing/share_harness_dialog.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/ws/ws_conn.dart';

import 'support/real_fonts.dart';

void main() {
  setUpAll(loadRealFonts);
  Future<void> show(WidgetTester tester, ShareAction manage, {Size size = const Size(900, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      home: RepaintBoundary(key: const Key('sharing-preview'), child: Scaffold(
        body: Builder(builder: (context) => TextButton(onPressed: () {
          showDialog<void>(context: context, builder: (_) => ShareHarnessDialog(name: 'Climate dashboard', manage: manage));
        }, child: const Text('Open share'))),
      )),
    ));
    await tester.tap(find.text('Open share'));
    await tester.pump(); await tester.pump(const Duration(milliseconds: 300));
  }
  Map<String, dynamic> person(String email, {String? error, bool pending = false, bool expired = false, int watching = 0}) => {
    'id': email, 'email': email, 'expiresAt': '2026-10-17T00:00:00.000Z',
    'error': error, 'pending': pending, 'expired': expired, 'watching': watching,
  };
  final submit = find.widgetWithText(FilledButton, 'Share harness');

  testWidgets('invites normalized emails, shows live presence and immediately removes access', (tester) async {
    var shares = <Map<String, dynamic>>[];
    final calls = <(String, Map<String, dynamic>)>[];
    await show(tester, (action, payload) async {
      calls.add((action, payload));
      if (action == 'invite') shares = [person('ken@example.com', watching: 1), person('diego@example.com')];
      if (action == 'remove') shares.removeWhere((row) => row['id'] == payload['id']);
      return {'shares': shares};
    });
    expect(find.text('Only you have access.'), findsOneWidget);
    expect(find.text('Can view'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'KEN@example.com; diego@example.com, ken@example.com');
    await tester.tap(submit); await tester.pump();
    expect(calls.last, ('invite', {'emails': ['ken@example.com', 'diego@example.com'], 'days': 30}));
    expect(find.text('2 people now have view-only access.'), findsOneWidget);
    expect(find.text('Watching now · Can view'), findsOneWidget);
    expect(find.textContaining('Shared with you'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Optional artifact for visual review; no golden files or production filesystem writes.
    final output = Platform.environment['HARNESS_SHARE_SCREENSHOT'];
    if (output != null) {
      final boundary = tester.firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary));
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await tester.runAsync(() => File(output).writeAsBytes(png!.buffer.asUint8List()));
      image.dispose();
    }
    await tester.tap(find.widgetWithText(TextButton, 'Remove').first); await tester.pump();
    expect(calls.last, ('remove', {'id': 'ken@example.com'}));
    expect(find.text('ken@example.com'), findsNothing);
    expect(find.text('Access removed.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(calls.last.$1, 'list');
    await tester.tap(find.text('Done')); await tester.pumpAndSettle();
    expect(find.text('Share harness'), findsNothing);
  });

  testWidgets('validates addresses locally and prevents duplicate submissions while saving', (tester) async {
    final pending = Completer<Map<String, dynamic>>();
    var invites = 0;
    await show(tester, (action, _) async {
      if (action == 'invite') { invites++; return pending.future; }
      return {'shares': []};
    });
    for (final invalid in ['', 'bad', List.generate(21, (i) => 'a$i@example.com').join(',')]) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.tap(submit); await tester.pump();
      expect(find.textContaining('Enter up to 20 valid'), findsOneWidget);
    }
    expect(invites, 0);
    await tester.enterText(find.byType(TextField), 'ken@example.com');
    await tester.tap(submit); await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(invites, 1);
    pending.complete({'shares': [person('ken@example.com', pending: true)]}); await tester.pump();
    expect(find.text('Waiting for connection'), findsOneWidget);
    expect(find.textContaining('Invitations saved.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders pending, expired and rejected grants clearly at a narrow width', (tester) async {
    await show(tester, (_, _) async => {'shares': [
      person('ken@example.com', pending: true), person('diego@example.com', expired: true),
      person('owner@example.com', error: 'You already own this harness.'),
    ]}, size: const Size(440, 680));
    expect(find.text('Waiting for connection'), findsOneWidget);
    expect(find.text('Expired · add again to renew'), findsOneWidget);
    expect(find.text('You already own this harness.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('shows actionable errors, recovers on retry and survives dismissal during a request', (tester) async {
    var fails = true;
    await show(tester, (_, _) async {
      if (fails) throw const WsRequestFailure(responseType: 'harness_share_list_result', code: 'UNSUPPORTED');
      return {'shares': []};
    });
    expect(find.text('Update Harness on this machine to start sharing.'), findsOneWidget);
    fails = false;
    await tester.tap(find.text('Retry')); await tester.pump();
    expect(find.text('Only you have access.'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    final pending = Completer<Map<String, dynamic>>();
    await show(tester, (_, _) => pending.future);
    await tester.tap(find.text('Done')); await tester.pumpAndSettle();
    pending.complete({'shares': []}); await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale presence refresh cannot erase a newly saved invitation', (tester) async {
    var lists = 0;
    final stale = Completer<Map<String, dynamic>>();
    await show(tester, (action, _) async {
      if (action == 'list' && ++lists > 1) return stale.future;
      return {'shares': action == 'invite' ? [person('ken@example.com')] : []};
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.enterText(find.byType(TextField), 'ken@example.com');
    await tester.tap(submit); await tester.pump();
    stale.complete({'shares': []}); await tester.pump();
    expect(find.text('ken@example.com'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
