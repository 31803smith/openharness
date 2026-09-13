import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/shortcuts/app_keymap.dart';
import 'package:harness/shortcuts/keymap.dart';
import 'package:harness/shortcuts/keymap_commands.dart';
import 'package:harness/shortcuts/keymap_host.dart';
import 'package:harness/shortcuts/keymap_keyboard.dart';

class MemoryKeymap extends AppKeymap {
  ResolvedKeymap map = harnessDefaultKeymap;
  @override
  ResolvedKeymap get current => map;
  void apply(String source) {
    map = ResolvedKeymap(
      harnessDefaultBindings,
      KeymapConfig.parse(source, commands: harnessCommandById.keys.toSet()),
    );
    version++;
    notifyListeners();
  }
}

Future<void> key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool cmd = false,
  bool ctrl = false,
  bool alt = false,
  bool shift = false,
}) async {
  final mods = [
    if (cmd) LogicalKeyboardKey.metaLeft,
    if (ctrl) LogicalKeyboardKey.controlLeft,
    if (alt) LogicalKeyboardKey.altLeft,
    if (shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final modifier in mods) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyEvent(key);
  for (final modifier in mods.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
}

void main() {
  test(
    'new defaults separate swarm selection, pane focus and terminal input',
    () {
      String? command(
        String keys, [
        KeymapContext context = KeymapContext.terminal,
      ]) => harnessDefaultKeymap
          .match(context, keys.split(' ').map(KeyStroke.parse))
          .command;
      expect(command('cmd+1'), 'swarm.select_1');
      expect(command('cmd+9'), 'swarm.select_9');
      expect(command('cmd+alt+1'), 'pane.focus_1');
      expect(command('cmd+alt+left'), 'pane.focus_left');
      expect(command('cmd+shift+enter'), 'pane.zoom');
      expect(command('cmd+shift+p'), 'navigation.commands');
      for (final chord in [
        'ctrl+tab',
        'ctrl+b',
        'alt+c',
        'cmd+h',
        'cmd+s',
        'cmd+b',
        'cmd+d',
        'cmd+shift+w',
      ]) {
        expect(command(chord), isNull, reason: chord);
      }
      expect(command('ctrl+n', KeymapContext.picker), 'picker.next');
      expect(command('cmd+p', KeymapContext.picker), 'navigation.quick_open');
      expect(command('cmd+['), 'navigation.back');
      expect(command('cmd+[', KeymapContext.picker), 'picker.back');
    },
  );

  test(
    'Mac native editing and window conflicts are rejected before activation',
    () {
      for (final keys in ['cmd+h', 'cmd+q', 'cmd+c', 'cmd+alt+h']) {
        final map = ResolvedKeymap(
          harnessDefaultBindings,
          KeymapConfig.parse(
            '{"bindings":[{"keys":"$keys","command":"pane.focus_left"}]}',
            commands: harnessCommandById.keys.toSet(),
          ),
        );
        expect(
          () => AppKeymap.validateNativeKeys(map, macOS: true),
          throwsFormatException,
        );
        AppKeymap.validateNativeKeys(map, macOS: false);
      }
      final map = ResolvedKeymap(
        harnessDefaultBindings,
        KeymapConfig.parse(
          '{"bindings":[{"keys":"cmd+k cmd+c","command":"pane.focus_left"}]}',
          commands: harnessCommandById.keys.toSet(),
        ),
      );
      AppKeymap.validateNativeKeys(map, macOS: true);
    },
  );

  testWidgets(
    'configured bindings dispatch before the focused owner and unbinding restores its route',
    (tester) async {
      final map = MemoryKeymap();
      final focus = FocusNode();
      final delivered = <String>[];
      var searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: KeymapProvider(
            keymap: map,
            child: KeymapHost(
              keymap: map,
              enabled: () => true,
              actions: {'navigation.quick_open': () => searches++},
              child: KeymapRegion(
                contextKind: KeymapContext.terminal,
                child: Focus(
                  focusNode: focus,
                  autofocus: true,
                  onKeyEvent: (_, event) {
                    final stroke = keyStrokeForEvent(event);
                    if (event is KeyDownEvent && stroke != null) {
                      delivered.add(stroke.toString());
                    }
                    return KeyEventResult.handled;
                  },
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyP, cmd: true);
      expect(searches, 1);
      expect(delivered, isEmpty);
      await key(tester, LogicalKeyboardKey.keyB, ctrl: true);
      await key(tester, LogicalKeyboardKey.keyC, alt: true);
      await key(tester, LogicalKeyboardKey.tab, ctrl: true);
      expect(delivered, ['ctrl+b', 'alt+c', 'ctrl+tab']);
      map.apply(
        '{"bindings":[{"keys":"cmd+p","command":null},{"keys":"ctrl+o","command":"navigation.quick_open","when":"terminal"}]}',
      );
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyP, cmd: true);
      await key(tester, LogicalKeyboardKey.keyO, ctrl: true);
      expect(searches, 2);
      expect(delivered.last, 'cmd+p');
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      map.dispose();
    },
  );

  testWidgets(
    'modal picker actions stay local and respect active text composition',
    (tester) async {
      final map = MemoryKeymap();
      final focus = FocusNode();
      final text = TextEditingController(text: 'draft');
      var selected = 0, swarms = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: KeymapProvider(
            keymap: map,
            child: KeymapHost(
              keymap: map,
              enabled: () => false,
              actions: {'swarm.new': () => swarms++},
              child: KeymapRegion(
                contextKind: KeymapContext.picker,
                actions: {
                  'picker.next': () => selected++,
                  'picker.accept': () => selected += 10,
                },
                child: Material(
                  child: TextField(
                    controller: text,
                    focusNode: focus,
                    autofocus: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await key(tester, LogicalKeyboardKey.keyN, ctrl: true);
      expect(selected, 1);
      await key(tester, LogicalKeyboardKey.keyT, cmd: true);
      expect(swarms, 0);
      text.value = text.value.copyWith(
        composing: const TextRange(start: 0, end: 5),
      );
      await key(tester, LogicalKeyboardKey.enter);
      expect(selected, 1);
      text.clearComposing();
      await key(tester, LogicalKeyboardKey.enter);
      expect(selected, 11);
      expect(text.text, 'draft');
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      text.dispose();
      map.dispose();
    },
  );
}
