import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/project_history.dart';

class _Store implements LocalKeyValueStore {
  String? value;
  Completer<String?>? pending;
  bool failWrites = false;
  @override
  Future<String?> read(String key) async =>
      pending == null ? value : pending!.future;
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('unavailable');
    this.value = value;
  }

  @override
  Future<void> delete(String key) async => value = null;
}

void main() {
  test(
    'remembers projects separately on each machine, including New',
    () async {
      final store = _Store();
      final history = ProjectHistory(store);
      await history.select('local', '/code/first');
      await history.select('remote', '/srv/other');
      await history.select('local', '/code/second');
      await history.select('local', '/code/first');
      await history.select('remote', null);
      final restored = ProjectHistory(store);
      await restored.load();
      expect(restored.selected('local'), '/code/first');
      expect(restored.recent('local'), ['/code/first', '/code/second']);
      expect(restored.hasSelection('remote'), isTrue);
      expect(restored.selected('remote'), isNull);
      expect(restored.recent('remote'), ['/srv/other']);
      expect(restored.hasSelection('unknown'), isFalse);
    },
  );

  test(
    'a selection made while loading wins over the saved selection',
    () async {
      final store = _Store()..pending = Completer<String?>();
      final history = ProjectHistory(store);
      final selecting = history.select('local', '/code/new');
      store.pending!.complete(
        jsonEncode({
          'local': {
            'selected': '/code/old',
            'recent': ['/code/old'],
          },
        }),
      );
      await selecting;
      expect(history.selected('local'), '/code/new');
      expect(history.recent('local'), ['/code/new', '/code/old']);
      expect(jsonDecode(store.value!)['local']['selected'], '/code/new');
    },
  );

  test(
    'bad state and unavailable storage never prevent an in-memory choice',
    () async {
      final store = _Store()
        ..value = 'not json'
        ..failWrites = true;
      final history = ProjectHistory(store);
      await history.select('local', '/code/project');
      await history.select('local', 'relative/path');
      await history.select('local', '/code/invalid\npath');
      expect(history.selected('local'), '/code/project');
      store.failWrites = false;
      await history.select('local', null);
      expect(history.recent('local'), ['/code/project']);
    },
  );
}
