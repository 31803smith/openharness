import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shortcuts/keymap.dart';

const commands = {'navigation.quick_open', 'pane.focus_left', 'picker.next'};
KeyBinding bind(
  String keys,
  String? command, [
  KeymapContext context = KeymapContext.workspace,
]) => KeyBinding(
  keys: keys.split(' ').map(KeyStroke.parse),
  command: command,
  context: context,
);
KeymapMatch match(
  ResolvedKeymap map,
  String keys, [
  KeymapContext context = KeymapContext.terminal,
]) => map.match(context, keys.split(' ').map(KeyStroke.parse));

void main() {
  test('a retired preview binding does not break other custom shortcuts', () {
    final config = KeymapConfig.parse('''{"bindings":[
      {"keys":"cmd+i","command":"picker.preview","when":"picker"},
      {"keys":"cmd+ctrl+h","command":"pane.focus_left"}
    ]}''', commands: commands);
    expect(config.bindings.single.command, 'pane.focus_left');
  });

  test('dotfile accepts comments, aliases and trailing commas', () {
    final config = KeymapConfig.parse('''
      // Keep the defaults and add my preferred movement key.
      {
        "version": 1,
        "bindings": [
          {"keys": "SUPER + CONTROL + H", "command": "pane.focus_left", "when": "terminal"},
          /* Leave this chord to my terminal. */
          {"keys": "cmd+alt+left", "command": null},
        ],
      }
    ''', commands: commands);
    final map = ResolvedKeymap([
      bind('cmd+alt+left', 'pane.focus_left'),
    ], config);
    expect(match(map, 'cmd+ctrl+h').command, 'pane.focus_left');
    expect(match(map, 'cmd+alt+left').matched, false);
    expect(match(map, 'cmd+ctrl+h', KeymapContext.workspace).matched, false);
  });

  test('string escapes and comment-like strings retain their exact value', () {
    const command = 'url://a"/*b*/';
    final config = KeymapConfig.parse(
      r'{"bindings":[{"keys":"cmd+p","command":"url://a\"/*b*/"}]}',
      commands: {command},
    );
    expect(config.bindings.single.command, command);
  });

  test('invalid edits are rejected with actionable diagnostics', () {
    for (final source in [
      '{"version":2}',
      '{"binding":[]}',
      '{"bindings":[{"keys":"cmd+p","command":"unknown"}]}',
      '{"bindings":[{"keys":"cmd+p"}]}',
      '{"bindings":[{"keys":"cmd+p","command":null,"when":"typo"}]}',
      '{"bindings":[{"keys":"cmd+cmd+p","command":null}]}',
      '{"bindings":[{"keys":"cmd","command":null}]}',
      '{"bindings":[{"keys":"made-up","command":null}]}',
      '{"bindings":[{"keys":"a b c d e","command":null}]}',
      '{"bindings":[{"keys":"cmd+p","command":null},{"keys":"super+p","command":null}]}',
      '{"bindings":[,]}',
      '{,}',
      '/* unfinished',
    ]) {
      expect(
        () => KeymapConfig.parse(source, commands: commands),
        throwsFormatException,
        reason: source,
      );
    }
  });

  test('decoder offsets still point into the original commented file', () {
    const source = '/* comment */\n{"bindings": ?}';
    try {
      KeymapConfig.parse(source, commands: commands);
      fail('Expected syntax error');
    } on FormatException catch (error) {
      expect(error.offset, source.indexOf('?'));
    }
  });

  test('terminal overrides do not change workspace or modal picker keys', () {
    final map = ResolvedKeymap([
      bind('cmd+p', 'navigation.quick_open'),
      bind('ctrl+n', 'picker.next', KeymapContext.picker),
    ], KeymapConfig([bind('cmd+p', null, KeymapContext.terminal)]));
    expect(match(map, 'cmd+p').matched, false);
    expect(
      match(map, 'cmd+p', KeymapContext.workspace).command,
      'navigation.quick_open',
    );
    expect(
      match(map, 'cmd+p', KeymapContext.picker).command,
      'navigation.quick_open',
    );
    expect(match(map, 'ctrl+n', KeymapContext.picker).command, 'picker.next');
    expect(match(map, 'ctrl+n', KeymapContext.terminal).matched, false);
  });

  test('explicit workspace overrides also replace terminal defaults', () {
    final map = ResolvedKeymap([
      bind('cmd+p', 'navigation.quick_open'),
      bind('cmd+p', 'pane.focus_left', KeymapContext.terminal),
    ], KeymapConfig([bind('cmd+p', null)]));
    expect(match(map, 'cmd+p').matched, false);
  });

  test('sequences need explicit removal of an ambiguous shorter binding', () {
    final defaults = [bind('cmd+p', 'navigation.quick_open')];
    final sequence = bind('cmd+p h', 'pane.focus_left');
    expect(
      () => ResolvedKeymap(defaults, KeymapConfig([sequence])),
      throwsFormatException,
    );
    final map = ResolvedKeymap(
      defaults,
      KeymapConfig([bind('cmd+p', null), sequence]),
    );
    expect(match(map, 'cmd+p').prefix, true);
    expect(match(map, 'cmd+p').command, null);
    expect(match(map, 'cmd+p h').command, 'pane.focus_left');
    expect(match(map, 'cmd+p l').matched, false);
    expect(match(map, 'cmd+p h j').matched, false);
  });

  test(
    'prefix ambiguity is rejected in both insertion orders and across scopes',
    () {
      expect(
        () => ResolvedKeymap([
          bind('cmd+p h', 'pane.focus_left'),
          bind('cmd+p', 'navigation.quick_open'),
        ], const KeymapConfig.empty()),
        throwsFormatException,
      );
      expect(
        () => ResolvedKeymap([
          bind('cmd+p h', 'pane.focus_left', KeymapContext.terminal),
        ], KeymapConfig([bind('cmd+p', 'navigation.quick_open')])),
        throwsFormatException,
      );
    },
  );

  test('unbinding a prefix releases its entire inherited sequence tree', () {
    final map = ResolvedKeymap([
      bind('cmd+p h', 'pane.focus_left'),
      bind('cmd+p p', 'navigation.quick_open'),
    ], KeymapConfig([bind('cmd+p', null)]));
    expect(match(map, 'cmd+p').matched, false);
    expect(match(map, 'cmd+p h').matched, false);
  });

  test(
    'oversized binding lists and unknown fields fail instead of being ignored',
    () {
      expect(
        () => KeymapConfig.parse(
          '{"bindings":[${List.filled(513, '{}').join(',')}]}',
          commands: commands,
        ),
        throwsFormatException,
      );
      expect(
        () => KeymapConfig.parse(
          '{"bindings":[{"keys":"cmd+p","command":null,"scope":"terminal"}]}',
          commands: commands,
        ),
        throwsFormatException,
      );
    },
  );
}
