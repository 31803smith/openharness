import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/agent_preference.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/shared/widgets/app_select_field.dart';
import 'package:harness/widgets/agent_picker.dart';

import 'swarm_state_test.dart' show MemoryStore;

class _SlowStore implements LocalKeyValueStore {
  final pending = Completer<String?>();
  @override
  Future<String?> read(String key) => pending.future;
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> delete(String key) async {}
}

void main() {
  test(
    'remembers the agent across launches without replacing a newer choice',
    () async {
      final store = MemoryStore();
      final preferences = AgentPreference(store);
      await preferences.select('codex');
      final restored = AgentPreference(store);
      await restored.load();
      expect(restored.value, 'codex');
      final slow = _SlowStore();
      final racing = AgentPreference(slow);
      final loading = racing.load();
      await racing.select('hermes');
      slow.pending.complete('claude');
      await loading;
      expect(racing.value, 'hermes');
    },
  );

  testWidgets('popular agents take one click and More contains every option', (
    tester,
  ) async {
    var selected = 'claude';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: StatefulBuilder(
                builder: (_, setState) => AgentPicker(
                  value: selected,
                  options: const [
                    SelectOption(value: 'codex', label: 'Codex'),
                    SelectOption(value: 'claude', label: 'Claude Code'),
                    SelectOption(value: 'cursor', label: 'Cursor'),
                    SelectOption(value: 'hermes', label: 'Hermes'),
                  ],
                  onChanged: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('new-agent-quick-codex')));
    await tester.pump();
    expect(selected, 'codex');
    expect(find.text('Hermes'), findsNothing);
    await tester.tap(find.byTooltip('More agents'));
    await tester.pumpAndSettle();
    expect(find.text('Codex'), findsNWidgets(2));
    await tester.tap(find.text('Hermes'));
    await tester.pumpAndSettle();
    expect(selected, 'hermes');
    expect(
      find.byKey(const ValueKey('new-agent-quick-hermes')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('new-agent-quick-cursor')), findsNothing);
    expect(find.byType(TextButton), findsNWidgets(3));
    expect(
      find.text('Hermes'),
      findsOneWidget,
      reason: 'The less common selection stays visible after closing the menu.',
    );
    await tester.tap(find.byKey(const ValueKey('new-agent-quick-codex')));
    await tester.pumpAndSettle();
    expect(selected, 'codex');
    expect(
      find.byKey(const ValueKey('new-agent-quick-hermes')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('new-agent-quick-cursor')), findsNothing);
    await tester.tap(find.byTooltip('More agents'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cursor'));
    await tester.pumpAndSettle();
    expect(selected, 'cursor');
    expect(
      find.byKey(const ValueKey('new-agent-quick-cursor')),
      findsOneWidget,
    );
    expect(find.text('Hermes'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
