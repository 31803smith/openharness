import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/screens/swarm_screen.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/usage/models_menu_controller.dart';
import 'package:harness/usage/usage_accounts.dart';
import 'package:harness/usage/usage_controller.dart';
import 'package:harness/usage/usage_source.dart';
import 'package:harness/usage/usage_window.dart';

import 'swarm_state_test.dart' show createApp;

class _Source implements UsageSource {
  _Source(this.provider, this.answer);
  @override
  final UsageProvider provider;
  Future<ProviderUsage> Function() answer;
  int calls = 0;
  @override
  Future<ProviderUsage> read() {
    calls++;
    return answer();
  }
}

void main() {
  final instant = DateTime.utc(2026, 9, 13, 12);
  ProviderUsage reading({
    double session = 85,
    double weekly = 30,
    DateTime? reset,
    DateTime? fetched,
    String? account = 'aabbccddeeff0011',
  }) => ProviderUsage(
    provider: UsageProvider.claude,
    status: UsageStatus.ok,
    account: account,
    fetchedAt: fetched ?? instant,
    windows: [
      UsageWindow(label: 'Session', usedPercent: session, resetsAt: reset),
      UsageWindow(label: 'Weekly', usedPercent: weekly),
    ],
  );

  test(
    'remaining means the limiting window, with account deduplication',
    () async {
      final source = _Source(UsageProvider.claude, () async => reading());
      final usage = UsageController(
        sources: [source],
        autoStart: false,
        remote: () async => [
          MachineUsage(machineName: 'Shared Mac', readings: [reading()]),
          MachineUsage(
            machineName: 'Other Mac',
            readings: [reading(account: '1122334455667788', session: 50)],
          ),
        ],
      );
      final menu = ModelsMenuController(usage: usage, now: () => instant);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      await menu.refresh();
      expect(menu.rows, hasLength(2));
      expect(menu.rows.first['title'], 'Anthropic');
      expect(menu.rows.first['status'], '15% remaining');
      expect(menu.rows.first['details'], contains('Weekly — 70% remaining'));
      expect(menu.rows.first['account'], 'Account aabbcc');
      expect(menu.rows.toString(), isNot(contains('Shared Mac')));
      expect(menu.rows.last['title'], 'Anthropic');
      expect(menu.rows.last['account'], 'Account 112233');
      expect(menu.rows.last['status'], '50% remaining');
      expect(menu.rows.toString(), isNot(contains('aabbccddeeff0011')));
    },
  );

  test(
    'no startup work; opening coalesces and caches requests for a minute',
    () async {
      var now = instant;
      var answer = Completer<ProviderUsage>();
      final source = _Source(UsageProvider.claude, () => answer.future);
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => now);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      expect(source.calls, 0);
      final first = menu.refresh();
      expect(menu.refresh(), same(first));
      expect(source.calls, 1);
      answer.complete(reading());
      await first;
      await menu.refresh();
      expect(source.calls, 1);
      now = now.add(const Duration(minutes: 1));
      answer = Completer<ProviderUsage>();
      final second = menu.refresh();
      expect(source.calls, 2);
      answer.complete(reading());
      await second;
    },
  );

  test('unidentified accounts do not invent an account label', () async {
    final source = _Source(
      UsageProvider.claude,
      () async => reading(account: null),
    );
    final usage = UsageController(sources: [source], autoStart: false);
    final menu = ModelsMenuController(usage: usage, now: () => instant);
    addTearDown(usage.dispose);
    addTearDown(menu.dispose);
    await menu.refresh();
    expect(menu.rows.single['title'], 'Anthropic');
    expect(menu.rows.single['account'], '');
  });

  test(
    'unknown, expired and invalid readings never become made-up percentages',
    () async {
      ProviderUsage value = const ProviderUsage(
        provider: UsageProvider.claude,
        status: UsageStatus.signedOut,
      );
      var now = instant;
      final source = _Source(UsageProvider.claude, () async => value);
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => now);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      await menu.refresh();
      expect(menu.rows.single['status'], 'Not signed in');
      for (final next in [
        reading(reset: instant),
        reading(session: double.nan),
        reading(fetched: instant.subtract(const Duration(minutes: 3))),
      ]) {
        value = next;
        now = now.add(const Duration(minutes: 1));
        await menu.refresh();
        expect(menu.rows.single['status'], 'Usage unavailable');
        expect(menu.rows.single['details'].toString(), isNot(contains('%')));
      }
    },
  );

  test(
    'a positive fraction of remaining usage is not rounded to zero',
    () async {
      final source = _Source(
        UsageProvider.claude,
        () async => reading(session: 99.6),
      );
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => instant);
      addTearDown(usage.dispose);
      addTearDown(menu.dispose);
      await menu.refresh();
      expect(menu.rows.single['status'], '<1% remaining');
    },
  );

  test(
    'source errors and a late response after disposal are contained',
    () async {
      final answer = Completer<ProviderUsage>();
      final source = _Source(UsageProvider.codex, () => answer.future);
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage, now: () => instant);
      addTearDown(usage.dispose);
      var notifications = 0;
      menu.addListener(() => notifications++);
      final request = menu.refresh();
      menu.dispose();
      final count = notifications;
      answer.completeError(StateError('synthetic secret must not reach UI'));
      await request;
      expect(notifications, count);
    },
  );

  testWidgets(
    'native Models opens lazily without changing the swarm or search',
    (tester) async {
      const channel = MethodChannel('harness/swarm_tabs');
      final messenger = tester.binding.defaultBinaryMessenger;
      final messages = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        messages.add(call);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final source = _Source(
        UsageProvider.codex,
        () async => const ProviderUsage(
          provider: UsageProvider.codex,
          status: UsageStatus.signedOut,
        ),
      );
      final usage = UsageController(sources: [source], autoStart: false);
      final menu = ModelsMenuController(usage: usage);
      final app = createApp();
      final original = app.activeSwarmId;
      final projects = SwarmProjectStore();
      await tester.pumpWidget(
        MaterialApp(
          home: SwarmScreen(
            notifier: app,
            nativeTabs: true,
            projectStore: projects,
            modelsMenu: menu,
          ),
        ),
      );
      expect(source.calls, 0);
      final previousUpdates = messages
          .where((c) => c.method == 'update')
          .length;
      final reply = Completer<void>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('modelsOpened'),
        ),
        (_) => reply.complete(),
      );
      await reply.future;
      await tester.pump();
      expect(source.calls, 1);
      expect(app.activeSwarmId, original);
      expect(
        messages.where((c) => c.method == 'update').length,
        previousUpdates,
      );
      expect(messages.where((c) => c.method == 'closeSearch'), isEmpty);
      final snapshot =
          messages.lastWhere((c) => c.method == 'modelsState').arguments as Map;
      expect((snapshot['subscriptions'] as List).single['title'], 'OpenAI');
      expect(
        (snapshot['subscriptions'] as List).single['status'],
        'Not signed in',
      );
      await tester.pumpWidget(const SizedBox());
      expect(
        (messages.lastWhere((c) => c.method == 'modelsState').arguments
            as Map)['subscriptions'],
        isEmpty,
      );
      menu.dispose();
      usage.dispose();
      app.dispose();
      projects.dispose();
    },
  );
}
