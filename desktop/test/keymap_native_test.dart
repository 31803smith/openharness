import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shortcuts/keymap_native.dart';
import 'package:harness/shortcuts/keymap.dart';
import 'package:harness/shortcuts/keymap_commands.dart';

import 'keymap_host_test.dart' show MemoryKeymap;

void main() {
  test(
    'native payload carries resolved contexts, unbinding and actual hints',
    () async {
      final keymap = MemoryKeymap();
      addTearDown(keymap.dispose);
      final defaults = nativeKeymapSnapshot(keymap);
      keymap.apply('''{"bindings":[
      {"keys":"cmd+t","command":null},
      {"keys":"cmd+o","command":"swarm.new"},
      {"keys":"cmd+k","command":null},
      {"keys":"cmd+k cmd+n","command":"swarm.new"},
      {"keys":"cmd+h","command":null,"when":"terminal"},
      {"keys":"down","command":null,"when":"picker"},
      {"keys":"ctrl+j","command":"picker.previous","when":"picker"}
    ]}''');
      final changed = nativeKeymapSnapshot(keymap);
      final contexts = changed['contexts']! as Map;
      for (final context in KeymapContext.values) {
        final rows = (contexts[context.name] as List).cast<Map>();
        final bindings = keymap.current.bindingsFor(context);
        expect(rows.length, bindings.length);
        for (final binding in bindings) {
          final row = rows.singleWhere(
            (row) => (row['keys'] as List).join(' ') == binding.sequence,
          );
          expect(row['command'], binding.command);
          expect(row['hint'], describeKeyBinding(binding));
          expect(
            row['repeatable'],
            harnessCommandById[binding.command]!.repeatable,
          );
          expect(
            row['menuAction'],
            harnessCommandById[binding.command]!.nativeAction,
          );
        }
        expect(
          rows.any((row) => (row['keys'] as List).join(' ') == 'cmd+t'),
          isFalse,
        );
      }
      expect(
        (contexts['terminal'] as List).any(
          (row) => (row['keys'] as List).join(' ') == 'cmd+h',
        ),
        isFalse,
      );
      expect(
        (contexts['workspace'] as List).any(
          (row) => (row['keys'] as List).join(' ') == 'cmd+h',
        ),
        isTrue,
      );
      final fixture = Platform.environment['HARNESS_KEYMAP_FIXTURE_PATH'];
      if (fixture != null) {
        await File(
          fixture,
        ).writeAsString(jsonEncode({'defaults': defaults, 'changed': changed}));
      }
    },
  );
}
