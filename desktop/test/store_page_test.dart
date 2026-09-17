// A harness's page in the Harness Store, past the happy path the screen test
// pins: every machine's row and what its install is doing, Get/Open/Remove
// under double clicks and pages that vanish mid-dialog, engines as the probes
// saw them, viewer packages, links, pictures, reviews, the shelves around the
// page, and a store whose control plane has no ratings routes at all (404).
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/api/api_client.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/dsh_catalog.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/store/store_controller.dart';
import 'package:harness/store/store_models.dart';
import 'package:harness/store/store_screen.dart';

import 'support/real_fonts.dart';

const _marp = DshEntry(
  id: 'autonomous/marp',
  name: 'Marp',
  engine: 'claude',
  category: 'Slides',
  author: 'Yuki Hattori',
  description: 'Describe a talk; get a keynote.',
  installed: true,
  viewer: true,
  homepage: 'https://marp.app',
  upstream: 'https://github.com/marp-team/marp-cli',
  repo: 'https://github.com/autonomous-ai/autonomous-marp',
  license: 'MIT',
);
const _typst = DshEntry(
  id: 'autonomous/typst',
  name: 'Typst',
  engine: 'claude',
  category: 'Documents',
  author: 'Typst GmbH',
);
const _docViewer = DshEntry(
  id: 'autonomous/doc-viewer',
  name: 'Doc Viewer',
  engine: '',
  kind: 'viewer',
  installed: true,
  category: 'Documents',
  author: 'Autonomous',
);

class _Notifier extends AppNotifier {
  _Notifier()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      );

  final installs = <(String, String)>[];
  final removals = <(String, String)>[];
  Completer<String?>? installGate;
  Completer<String?>? removeGate;
  int probes = 0;

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {
    probes++;
  }

  @override
  Future<void> probeDsh(String machineId, {bool force = false}) async {
    probes++;
  }

  @override
  Future<String?> installDsh(String machineId, String id) async {
    installs.add((machineId, id));
    return installGate?.future;
  }

  @override
  Future<String?> removeDsh(String machineId, String id) async {
    removals.add((machineId, id));
    return removeGate?.future;
  }

  void changed() => notifyListeners();

  MachineState machine(
    String id, {
    String? name,
    bool local = false,
    bool? online,
    List<DshEntry>? dsh,
    List<EngineAvailability>? engines,
  }) {
    final state =
        MachineState(
            Machine(
              machineId: id,
              authMode: MachineAuthMode.remote,
              name: name ?? id,
            ),
          )
          ..localOnly = local
          ..nodeOnline = online;
    if (dsh != null) state.dsh.replace(dsh);
    if (engines != null) state.engines.replace(engines);
    machineStates[id] = state;
    return state;
  }
}

class _Store implements StoreApi {
  List<StoreRating> rated = const [];
  StoreReviews Function(String harnessId)? page;
  Object? failReviews;
  Object? failPut;
  final puts = <(String, int)>[];
  final deletes = <String>[];
  int ratingReads = 0;
  final reviewReads = <String>[];

  @override
  Future<List<StoreRating>> ratings() async {
    ratingReads++;
    return rated;
  }

  @override
  Future<StoreReviews> reviews(String harnessId) async {
    reviewReads.add(harnessId);
    if (failReviews case final error?) throw error;
    return page?.call(harnessId) ??
        StoreReviews(
          rating: StoreRating.none(harnessId),
          reviews: const [],
          mine: null,
        );
  }

  @override
  Future<StoreReview> putReview(
    String harnessId, {
    required int rating,
    String? title,
    String? body,
  }) async {
    if (failPut case final error?) throw error;
    puts.add((harnessId, rating));
    return StoreReview(
      id: 'mine',
      harnessId: harnessId,
      rating: rating,
      authorName: 'You',
      mine: true,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteReview(String harnessId) async => deletes.add(harnessId);
}

/// The store tab, opened with [seed]'s machines — by default this computer,
/// with Marp installed and Typst not.
Future<(_Notifier, _Store)> _open(
  WidgetTester tester, {
  String? initialHarness,
  void Function(_Notifier app)? seed,
  _Store? store,
  StoreApi? api,
  bool injectApi = true,
  bool settle = true,
  Size size = const Size(1280, 2400),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final notifier = _Notifier();
  addTearDown(notifier.dispose);
  (seed ??
      (app) => app.machine(
        'machine-1',
        name: 'studio-mac',
        local: true,
        dsh: const [_marp, _typst, _docViewer],
        engines: const [EngineAvailability(engine: 'claude', installed: true)],
      ))(notifier);
  final fake = store ?? _Store();
  // The store lives in its own tab, as the start page's card opens it.
  notifier.openStore();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StoreTab(
          notifier: notifier,
          api: injectApi ? (api ?? fake) : null,
          source: 'test',
          initialHarness: initialHarness,
        ),
      ),
    ),
  );
  // A spinner or a skeleton never settles; those tests pump frames instead.
  settle ? await tester.pumpAndSettle() : await tester.pump();
  await tester.pump();
  return (notifier, fake);
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder matching) =>
    find.descendant(of: _key(key), matching: matching);

StoreReview _review(
  String id, {
  required int daysAgo,
  bool mine = false,
  String? title,
  String? body,
}) => StoreReview(
  id: id,
  harnessId: 'autonomous/marp',
  rating: 4,
  title: title,
  body: body,
  authorName: 'Reviewer $id',
  mine: mine,
  updatedAt: DateTime.now().subtract(Duration(days: daysAgo, minutes: 5)),
);

void main() {
  // Real glyph widths: the review dialog's buttons are laid out against Arial,
  // not against Ahem's squares, which overflow a row no person would see.
  setUpAll(loadRealFonts);

  group('Get, Open and Remove', () {
    testWidgets(
      'Get installs on this machine once however fast the clicks, and a failure is said',
      (tester) async {
        final (app, _) = await _open(
          tester,
          initialHarness: 'autonomous/typst',
        );
        app.installGate = Completer<String?>();
        expect(_in('store-primary-action', find.text('Get')), findsOneWidget);
        await tester.tap(_key('store-primary-action'));
        await tester.tap(_key('store-get:machine-1'));
        expect(app.installs, [('machine-1', 'autonomous/typst')]);
        await tester.pump();
        expect(
          tester.widget<FilledButton>(_key('store-primary-action')).onPressed,
          isNull,
          reason: 'busy while the install runs',
        );
        expect(
          _in(
            'store-machine:machine-1',
            find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(_key('store-get:machine-1'), findsNothing);

        app.installGate!.complete('kicad-cli is not on studio-mac');
        await tester.pumpAndSettle();
        expect(find.text('kicad-cli is not on studio-mac'), findsOneWidget);
        expect(_key('store-get:machine-1'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(_key('store-primary-action')).onPressed,
          isNotNull,
        );
      },
    );

    testWidgets('an install that ends after the page is gone says nothing', (
      tester,
    ) async {
      final (app, _) = await _open(tester, initialHarness: 'autonomous/typst');
      app.installGate = Completer<String?>();
      await tester.tap(_key('store-get:machine-1'));
      await tester.pump();
      await tester.tap(_key('store-back'));
      await tester.pumpAndSettle();
      expect(_key('store-page:autonomous/typst'), findsNothing);
      app.installGate!.complete('clone failed');
      await tester.pumpAndSettle();
      expect(find.text('clone failed'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Remove asks first, Cancel keeps it, and a linked install says only its link goes',
      (tester) async {
        final (app, _) = await _open(
          tester,
          initialHarness: 'autonomous/marp',
          seed: (app) => app.machine(
            'machine-1',
            name: 'studio-mac',
            local: true,
            dsh: [
              DshEntry(
                id: _marp.id,
                name: _marp.name,
                engine: 'claude',
                installed: true,
                linked: true,
              ),
            ],
          ),
        );
        expect(
          _in(
            'store-machine:machine-1',
            find.text('Installed · linked to a checkout'),
          ),
          findsOneWidget,
        );
        await tester.tap(_key('store-remove:machine-1'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'This is linked to a checkout on that machine; only the link goes. Harnesses already open keep running.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(app.removals, isEmpty);
        expect(find.textContaining('only the link goes'), findsNothing);
      },
    );

    testWidgets('Remove runs once at a time, and a refusal is said', (
      tester,
    ) async {
      final (app, _) = await _open(tester, initialHarness: 'autonomous/marp');
      app.removeGate = Completer<String?>();
      await tester.tap(_key('store-remove:machine-1'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Marp from studio-mac?'), findsOneWidget);
      await tester.tap(_key('store-confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(app.removals, [('machine-1', 'autonomous/marp')]);
      expect(
        _in('store-machine:machine-1', find.byType(CircularProgressIndicator)),
        findsOneWidget,
      );
      expect(_key('store-remove:machine-1'), findsNothing);
      app.removeGate!.complete(
        'Update the harness CLI on studio-mac to remove harnesses',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Update the harness CLI on studio-mac to remove harnesses'),
        findsOneWidget,
      );
      expect(_key('store-remove:machine-1'), findsOneWidget);
    });

    testWidgets(
      'a harness that leaves the catalog while Remove asks is not removed',
      (tester) async {
        final (app, _) = await _open(tester, initialHarness: 'autonomous/marp');
        await tester.tap(_key('store-remove:machine-1'));
        await tester.pumpAndSettle();
        app.machineStates['machine-1']!.dsh.replace(const [_typst]);
        app.changed();
        await tester.pumpAndSettle();
        expect(_key('store-page:autonomous/marp'), findsNothing);
        await tester.tap(_key('store-confirm'));
        await tester.pumpAndSettle();
        expect(app.removals, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Open, from the page or a machine row, opens New Harness on that machine in a tab of its own',
      (tester) async {
        final (app, _) = await _open(tester, initialHarness: 'autonomous/marp');
        final tabs = app.swarms.length;
        expect(_in('store-primary-action', find.text('Open')), findsOneWidget);
        await tester.tap(_key('store-primary-action'));
        await tester.pumpAndSettle();
        expect(find.text('New Harness'), findsOneWidget);
        expect(app.swarms.length, tabs + 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          app.swarms.length,
          tabs,
          reason: 'a dismissed dialog leaves no tab',
        );

        await tester.tap(_key('store-open:machine-1'));
        await tester.pumpAndSettle();
        expect(find.text('New Harness'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(app.swarms.length, tabs);
      },
    );
  });

  testWidgets(
    'every machine has a row — this computer first, then by name — saying where its install stands',
    (tester) async {
      DshInstallRun run(String phase, {String? line}) => DshInstallRun(
        _typst.id,
      )..apply(DshInstallProgress(id: _typst.id, phase: phase, line: line));
      final (app, _) = await _open(
        tester,
        initialHarness: 'autonomous/typst',
        settle: false,
        seed: (app) {
          app.machine('juliet', dsh: const [_typst]);
          app.machine('india').dsh.error =
              'This machine could not report its harnesses';
          app.machine('hotel');
          app.machine('golf').dsh.error = 'UNSUPPORTED';
          app.machine(
            'foxtrot',
            dsh: const [
              DshEntry(
                id: 'autonomous/typst',
                name: 'Typst',
                engine: 'claude',
                installed: true,
                linked: true,
              ),
            ],
          );
          app
              .machine('echo', dsh: const [_typst])
              .dsh
              .runs[_typst.id] = DshInstallRun(_typst.id)
            ..apply(DshInstallProgress(id: _typst.id, phase: 'clone'))
            ..apply(
              DshInstallProgress(
                id: _typst.id,
                phase: 'failed',
                detail: 'no space left',
              ),
            );
          app.machine('delta', dsh: const [_typst]).dsh.runs[_typst.id] = run(
            'doctor',
            line: 'miss typst-cli (cargo install typst-cli)',
          )..apply(DshInstallProgress(id: _typst.id, phase: 'failed'));
          app.machine('charlie', dsh: const [_typst]).dsh.runs[_typst.id] = run(
            'queued',
          );
          app.machine('Beta', dsh: const [_typst]).dsh.runs[_typst.id] = run(
            'doctor',
          );
          app.machine('alpha', dsh: const [_typst]).dsh.runs[_typst.id] = run(
            'setup',
          );
          app
              .machine(
                'machine-1',
                name: 'zulu-mac',
                local: true,
                dsh: const [_typst],
              )
              .dsh
              .runs[_typst.id] = run(
            'clone',
          );
        },
      );
      final order = [
        'machine-1',
        'alpha',
        'Beta',
        'charlie',
        'delta',
        'echo',
        'foxtrot',
        'golf',
        'hotel',
        'india',
        'juliet',
      ];
      final tops = [
        for (final id in order) tester.getTopLeft(_key('store-machine:$id')).dy,
      ];
      expect(tops, [...tops]..sort(), reason: 'this computer, then by name');

      void says(String id, String status) => expect(
        _in('store-machine:$id', find.text(status)),
        findsOneWidget,
        reason: id,
      );
      says('machine-1', 'zulu-mac · this computer');
      says('machine-1', 'Fetching…');
      says('alpha', 'alpha');
      says('alpha', 'Setting up the toolchain…');
      says('Beta', 'Checking…');
      says('charlie', 'Installing…');
      for (final id in ['machine-1', 'alpha', 'Beta', 'charlie']) {
        expect(
          _in('store-machine:$id', find.byType(CircularProgressIndicator)),
          findsOneWidget,
          reason: id,
        );
      }
      says('delta', 'miss typst-cli (cargo install typst-cli)');
      says('echo', 'Install failed');
      final failed = tester.widget<Text>(
        _in('store-machine:echo', find.text('Install failed')),
      );
      expect(
        failed.style?.color,
        isNot(
          tester
              .widget<Text>(
                _in('store-machine:juliet', find.text('Not installed')),
              )
              .style
              ?.color,
        ),
        reason: 'a failure is not in the quiet colour',
      );
      expect(_in('store-get:delta', find.text('Try again')), findsOneWidget);
      says('foxtrot', 'Installed · linked to a checkout');
      expect(_key('store-open:foxtrot'), findsOneWidget);
      expect(_key('store-remove:foxtrot'), findsOneWidget);
      says(
        'golf',
        'Update the harness CLI on this machine to install harnesses',
      );
      says('hotel', 'Asking…');
      says('india', 'This machine could not report its harnesses');
      for (final id in ['golf', 'hotel', 'india']) {
        expect(
          tester.widget<FilledButton>(_key('store-get:$id')).onPressed,
          isNull,
          reason: '$id has not said it can install',
        );
      }
      says('juliet', 'Not installed');

      await tester.tap(_key('store-get:delta'));
      await tester.pump();
      await tester.tap(_key('store-get:juliet'));
      await tester.pump();
      expect(app.installs, [
        ('delta', 'autonomous/typst'),
        ('juliet', 'autonomous/typst'),
      ]);
    },
  );

  testWidgets(
    'an engine page reads the probes: asking, installed with Open, installable with Get, or neither',
    (tester) async {
      // One rating, from a control plane that sent no bars for it.
      const rating = StoreRating(
        harnessId: 'engine/claude',
        average: 5,
        count: 1,
        histogram: [0, 0, 0, 0, 0],
      );
      final store = _Store()
        ..rated = const [rating]
        ..page = ((_) =>
            const StoreReviews(rating: rating, reviews: [], mine: null));
      final (app, _) = await _open(
        tester,
        store: store,
        initialHarness: 'claude',
        seed: (app) {
          app.machine('machine-1', name: 'studio-mac', local: true);
          app.machine(
            'alpha',
            engines: const [
              EngineAvailability(engine: 'claude', installed: true),
            ],
          );
          app.machine(
            'beta',
            engines: const [
              EngineAvailability(engine: 'claude', installed: false),
            ],
          );
          app.machine(
            'gamma',
            engines: const [
              EngineAvailability(
                engine: 'claude',
                installed: false,
                installable: true,
              ),
            ],
          );
        },
      );
      expect(find.text('Anthropic · Code · Coding agent'), findsOneWidget);
      expect(store.reviewReads, [
        'engine/claude',
      ], reason: 'an engine is rated under engine/');
      expect(
        _in('store-machine:machine-1', find.text('Asking…')),
        findsOneWidget,
      );
      expect(
        _in('store-machine:machine-1', find.byType(TextButton)),
        findsNothing,
      );
      expect(_in('store-machine:alpha', find.text('alpha')), findsOneWidget);
      expect(_key('store-open:alpha'), findsOneWidget);
      expect(
        _in('store-machine:beta', find.text('Not installed')),
        findsOneWidget,
      );
      expect(_key('store-get:beta'), findsNothing, reason: 'nothing to offer');
      expect(_key('store-get:gamma'), findsOneWidget);
      // A rating with no bars drawn still reads as its number.
      expect(find.text('5.0 · 1 rating'), findsOneWidget);
      expect(find.text('out of 5 · 1 rating'), findsOneWidget);

      final tabs = app.swarms.length;
      // Get on an engine is Open: the daemon installs it on the way.
      expect(_in('store-primary-action', find.text('Get')), findsOneWidget);
      await tester.tap(_key('store-primary-action'));
      await tester.pumpAndSettle();
      expect(find.text('New Harness'), findsOneWidget);
      expect(app.installs, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.swarms.length, tabs);
    },
  );

  testWidgets(
    'a viewer package has a page but nothing to open, and a store with no machines says so',
    (tester) async {
      final (app, _) = await _open(
        tester,
        initialHarness: 'autonomous/doc-viewer',
      );
      expect(
        find.text('Autonomous · Documents · Viewer package'),
        findsOneWidget,
      );
      expect(_key('store-primary-action'), findsNothing);
      expect(_key('store-remove:machine-1'), findsOneWidget);
      expect(_key('store-open:machine-1'), findsNothing);

      // Its machine goes away, and the page with it.
      app.machineStates.clear();
      app.changed();
      await tester.pump();
      expect(_key('store-page:autonomous/doc-viewer'), findsNothing);
    },
  );

  testWidgets('with no machines an engine page has no action and says so', (
    tester,
  ) async {
    await _open(tester, initialHarness: 'codex', seed: (_) {});
    expect(find.text('No machines yet.'), findsOneWidget);
    expect(_key('store-primary-action'), findsNothing);
  });

  testWidgets(
    'links open outside the app, the licence is only words, and pictures that fail leave no hole',
    (tester) async {
      final launched = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _open(
        tester,
        initialHarness: 'autonomous/marp',
        seed: (app) => app.machine(
          'machine-1',
          local: true,
          dsh: const [
            DshEntry(
              id: 'autonomous/marp',
              name: 'Marp',
              engine: 'claude',
              upstream: 'https://github.com/marp-team/marp-cli',
              screenshots: [
                'https://example.com/deck-1.png',
                'https://example.com/deck-2.png',
              ],
            ),
          ],
        ),
      );
      expect(find.text('Website'), findsNothing);
      expect(find.text('Package source'), findsNothing);
      await tester.tap(find.text('Upstream project'));
      await tester.pump();
      expect(launched, ['https://github.com/marp-team/marp-cli']);

      final pictures = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is NetworkImage,
      );
      expect(pictures, findsWidgets);
      // The test HTTP client answers every request 400: both pictures fail.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.descendant(of: pictures, matching: find.byType(RawImage)),
        findsNothing,
        reason: 'a picture that failed draws nothing, not a broken frame',
      );
    },
  );

  testWidgets(
    'every link the registry names is a chip, the licence without an arrow',
    (tester) async {
      await _open(tester, initialHarness: 'autonomous/marp');
      for (final label in [
        'Website',
        'Upstream project',
        'Package source',
        'Licence · MIT',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    },
  );

  group('reviews', () {
    StoreReviews marpPage(
      String id, {
      bool withMine = true,
      bool empty = false,
    }) => StoreReviews(
      rating: const StoreRating(
        harnessId: 'autonomous/marp',
        average: 4,
        count: 7,
        histogram: [0, 1, 1, 2, 3],
      ),
      reviews: empty
          ? const []
          : [
              if (withMine)
                _review('mine', daysAgo: 0, mine: true, title: 'Sharp decks'),
              _review('r1', daysAgo: 1, body: 'Fast.'),
              _review('r5', daysAgo: 5),
              _review('r35', daysAgo: 35),
              _review('r70', daysAgo: 70),
              _review('r400', daysAgo: 400),
              _review('r800', daysAgo: 800),
            ],
      mine: withMine
          ? _review('mine', daysAgo: 0, mine: true, title: 'Sharp decks')
          : null,
    );

    testWidgets('each review says who and when, and yours can be edited', (
      tester,
    ) async {
      final store = _Store()..page = marpPage;
      await _open(tester, store: store, initialHarness: 'autonomous/marp');
      expect(find.text('4.0 · 7 ratings'), findsOneWidget);
      expect(
        _in('store-write-review', find.text('Edit your review')),
        findsOneWidget,
      );
      for (final (id, age) in [
        ('mine', 'You · today'),
        ('r1', 'Reviewer r1 · yesterday'),
        ('r5', 'Reviewer r5 · 5 days ago'),
        ('r35', 'Reviewer r35 · 1 month ago'),
        ('r70', 'Reviewer r70 · 2 months ago'),
        ('r400', 'Reviewer r400 · 1 year ago'),
        ('r800', 'Reviewer r800 · 2 years ago'),
      ]) {
        expect(
          _in('store-review:$id', find.text(age)),
          findsOneWidget,
          reason: id,
        );
      }
      expect(_in('store-review:mine', find.text('Edit')), findsOneWidget);
      expect(_in('store-review:r1', find.text('Edit')), findsNothing);
      expect(_in('store-review:r1', find.text('Fast.')), findsOneWidget);

      // Edit from the card: the dialog holds what was written, and can delete it.
      await tester.tap(_in('store-review:mine', find.text('Edit')));
      await tester.pumpAndSettle();
      expect(find.text('Your review of Marp'), findsOneWidget);
      expect(
        tester.widget<TextField>(_key('store-review-title')).controller!.text,
        'Sharp decks',
      );
      expect(_in('store-review-post', find.text('Save')), findsOneWidget);
      final reads = store.reviewReads.length;
      await tester.tap(_key('store-review-delete'));
      await tester.pumpAndSettle();
      expect(store.deletes, ['autonomous/marp']);
      expect(
        store.reviewReads.length,
        reads + 1,
        reason: 'the page is read again',
      );
    });

    testWidgets('a dismissed review writes nothing, and a failed one is said', (
      tester,
    ) async {
      final store = _Store()
        ..page = ((id) => marpPage(id, withMine: false, empty: true))
        ..failPut = StateError('offline');
      await _open(tester, store: store, initialHarness: 'autonomous/marp');
      expect(find.text('No reviews yet. Be the first.'), findsOneWidget);
      await tester.tap(_key('store-write-review'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Rate Marp'), findsNothing);
      expect(store.puts, isEmpty);

      await tester.tap(_key('store-write-review'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: _key('store-review-stars'),
              matching: find.byType(Icon),
            )
            .last,
      );
      await tester.pump();
      await tester.tap(_key('store-review-post'));
      await tester.pumpAndSettle();
      expect(find.text('Your review could not be posted'), findsOneWidget);
    });

    testWidgets(
      'a rated harness whose reviews will not load still shows its stars',
      (tester) async {
        final store = _Store()
          ..rated = const [
            StoreRating(
              harnessId: 'autonomous/marp',
              average: 3.5,
              count: 2,
              histogram: [0, 0, 1, 1, 0],
            ),
          ]
          ..failReviews = StateError('offline');
        await _open(tester, store: store, initialHarness: 'autonomous/marp');
        expect(find.text('3.5 · 2 ratings'), findsOneWidget);
        expect(find.text('Reviews are unavailable right now.'), findsOneWidget);
        expect(find.text('No reviews yet. Be the first.'), findsNothing);
      },
    );
  });

  testWidgets(
    'a control plane without ratings (404) leaves a store with no stars that still installs',
    (tester) async {
      final client = _NotFoundClient();
      final (app, _) = await _open(
        tester,
        api: ApiStoreApi(client),
        initialHarness: 'autonomous/typst',
      );
      expect(client.asked, containsAll(['ratings', 'reviews']));
      expect(find.text('Ratings and reviews'), findsNothing);
      expect(find.textContaining('not on the Harness server'), findsNothing);
      expect(find.textContaining('rating'), findsNothing);
      await tester.tap(_key('store-primary-action'));
      await tester.pumpAndSettle();
      expect(app.installs, [('machine-1', 'autonomous/typst')]);
    },
  );

  group('shelves', () {
    testWidgets(
      'See all lists every harness, and the engines See all is Code',
      (tester) async {
        await _open(tester);
        await tester.tap(find.widgetWithText(TextButton, 'See all').first);
        await tester.pumpAndSettle();
        expect(_key('store-catalog:All harnesses'), findsOneWidget);
        expect(
          find.text('Find something you have always wanted to make.'),
          findsOneWidget,
        );
        expect(_key('store-card:autonomous/marp'), findsOneWidget);
        expect(_key('store-card:claude'), findsOneWidget);

        await tester.tap(_key('store-shelf-discover'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'See all').last);
        await tester.pumpAndSettle();
        expect(_key('store-catalog:Code'), findsOneWidget);
        expect(_key('store-card:autonomous/marp'), findsNothing);
        expect(find.textContaining('harnesses to explore.'), findsOneWidget);
      },
    );

    testWidgets(
      'a category counts what it holds, empties honestly, and a new domain is Other',
      (tester) async {
        final (app, _) = await _open(
          tester,
          seed: (app) => app.machine(
            'machine-1',
            local: true,
            dsh: const [
              _typst,
              DshEntry(
                id: 'someone/loom',
                name: 'Loom',
                engine: 'codex',
                category: 'Knitting',
              ),
            ],
          ),
        );
        expect(_key('store-shelf-category:Other'), findsOneWidget);
        await tester.tap(_key('store-shelf-category:Other'));
        await tester.pumpAndSettle();
        expect(find.text('1 harness to explore.'), findsOneWidget);
        expect(_key('store-card:someone/loom'), findsOneWidget);

        await tester.tap(_key('store-shelf-category:Media'));
        await tester.pumpAndSettle();
        // The machine answers again without Typst while the shelf is open.
        app.machineStates['machine-1']!.dsh.replace(const []);
        app.changed();
        await tester.pumpAndSettle();
        expect(find.text('Nothing here yet.'), findsOneWidget);
        // And with no machine left to ask, it is still asking.
        app.machineStates.clear();
        app.changed();
        await tester.pumpAndSettle();
        expect(find.text('Asking your machines…'), findsOneWidget);
      },
    );

    testWidgets('search counts its results', (tester) async {
      await _open(tester);
      await tester.enterText(_key('store-search'), 'keynote');
      await tester.pumpAndSettle();
      expect(find.text('1 result'), findsOneWidget);
      await tester.enterText(_key('store-search'), 'autonomous');
      await tester.pumpAndSettle();
      expect(find.text('2 results'), findsOneWidget);
      await tester.enterText(_key('store-search'), '  ');
      await tester.pumpAndSettle();
      expect(
        _key('store-catalog:Search results'),
        findsNothing,
        reason: 'blank is Discover',
      );
    });

    testWidgets(
      'a card\'s action opens where it is installed — here, else an online machine — else the page',
      (tester) async {
        final (app, _) = await _open(
          tester,
          seed: (app) {
            app.machine(
              'machine-1',
              name: 'studio-mac',
              local: true,
              dsh: const [_typst],
            );
            app.machine(
              'remote',
              online: true,
              dsh: const [
                DshEntry(
                  id: 'autonomous/typst',
                  name: 'Typst',
                  engine: 'claude',
                  installed: true,
                ),
                DshEntry(
                  id: 'autonomous/marp',
                  name: 'Marp',
                  engine: 'claude',
                  installed: true,
                ),
              ],
            );
            app.machine(
              'offline',
              online: false,
              dsh: const [
                DshEntry(
                  id: 'autonomous/manim',
                  name: 'Manim',
                  engine: 'claude',
                  category: 'Math animation',
                  installed: true,
                ),
              ],
            );
          },
        );
        await tester.tap(_key('store-shelf-category:Media'));
        await tester.pumpAndSettle();
        final tabs = app.swarms.length;

        expect(
          _in('store-action:autonomous/typst', find.text('Open')),
          findsOneWidget,
        );
        await tester.tap(_key('store-action:autonomous/typst'));
        await tester.pumpAndSettle();
        expect(find.text('New Harness'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(app.swarms.length, tabs);

        // Installed only on a machine that is offline: nowhere to open it.
        await tester.tap(_key('store-action:autonomous/manim'));
        await tester.pumpAndSettle();
        expect(_key('store-page:autonomous/manim'), findsOneWidget);
        expect(app.swarms.length, tabs);
      },
    );
  });

  testWidgets('without an injected API nothing is asked under test', (
    tester,
  ) async {
    final (app, _) = await _open(tester, injectApi: false);
    expect(app.probes, 0);
    expect(_key('store-card:autonomous/marp'), findsOneWidget);
  });

  testWidgets('a store built and torn down in one frame asks nobody anything', (
    tester,
  ) async {
    final app = _Notifier();
    addTearDown(app.dispose);
    app.machine('machine-1', local: true, dsh: const [_marp]);
    final store = _Store();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _WideThenNarrow(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth > 400
                  ? StoreTab(
                      notifier: app,
                      api: store,
                      initialHarness: 'autonomous/marp',
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StoreTab), findsNothing);
    expect(app.probes, 0);
    expect(store.ratingReads, 0);
    expect(store.reviewReads, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

/// The store's calls against a control plane that predates the store: every
/// store route answers 404, through the real envelope unwrap.
class _NotFoundClient extends ApiClient {
  _NotFoundClient() : super(config: AppConfig.dev, session: AuthSession());

  final asked = <String>[];

  Never _notFound(String what) {
    asked.add(what);
    unwrapApiResponse(
      Response(
        requestOptions: RequestOptions(),
        statusCode: 404,
        data: {
          'success': false,
          'error': {'message': 'Route not found'},
        },
      ),
    );
    throw StateError('unreachable');
  }

  @override
  Future<Map<String, dynamic>?> storeRatings() async => _notFound('ratings');

  @override
  Future<Map<String, dynamic>?> storeReviews(String harnessId) async =>
      _notFound('reviews');
}

/// Lays its child out twice in its first layout — wide, then narrow — so a
/// [LayoutBuilder] below it mounts a subtree and removes it within one frame,
/// before that frame's post-frame callbacks run. What a window resize across a
/// breakpoint can do to a widget in the frame it was built.
class _WideThenNarrow extends SingleChildRenderObjectWidget {
  const _WideThenNarrow({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWideThenNarrow();
}

class _RenderWideThenNarrow extends RenderProxyBox {
  bool _first = true;

  @override
  void performLayout() {
    if (_first) {
      _first = false;
      child!.layout(constraints);
    }
    child!.layout(BoxConstraints.loose(Size(100, constraints.maxHeight)));
    size = constraints.biggest;
  }
}
