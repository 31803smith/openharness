import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app_shortcuts.dart';
import 'keymap.dart';
import 'keymap_commands.dart';
import 'keymap_store.dart';

/// A window's configuration, injectable so tests never read a user's dotfiles.
class AppKeymap extends ChangeNotifier {
  AppKeymap({this.store}) {
    store?.addListener(_changed);
  }
  final KeymapStore? store;
  int version = 0;
  ResolvedKeymap get current => store?.current ?? harnessDefaultKeymap;
  String? get error => store?.error;
  String? get path => store?.file.path;
  void _changed() {
    version++;
    notifyListeners();
  }

  Future<void> start() async {
    await store?.start();
  }

  static KeymapStore fileStore() => KeymapStore(
    file: File(KeymapStore.defaultPath()),
    defaults: harnessDefaultBindings,
    commands: harnessCommandById.keys.toSet(),
    validate: (map) => validateNativeKeys(map, macOS: Platform.isMacOS),
  );

  Iterable<KeyBinding> bindings(
    String command, {
    KeymapContext context = KeymapContext.workspace,
  }) => current
      .bindingsFor(context)
      .where((binding) => binding.command == command);

  String? hint(
    String command, {
    KeymapContext context = KeymapContext.workspace,
  }) {
    final binding = bindings(command, context: context).firstOrNull;
    return binding == null ? null : describeKeyBinding(binding);
  }

  /// These are names of actual AppKit commands, not all system shortcuts.
  /// The second stroke of an explicit sequence can still use an editing key.
  static void validateNativeKeys(ResolvedKeymap map, {required bool macOS}) {
    if (!macOS) return;
    final reserved = {
      for (final chord in [
        'cmd+q',
        'cmd+m',
        'cmd+alt+h',
        'cmd+ctrl+f',
        'cmd+c',
        'cmd+v',
        'cmd+x',
        'cmd+a',
        'cmd+z',
        'cmd+shift+z',
        'cmd+alt+shift+v',
        'cmd+backquote',
        'cmd+shift+backquote',
      ])
        KeyStroke.parse(chord),
    };
    for (final context in KeymapContext.values) {
      for (final binding in map.bindingsFor(context)) {
        if (binding.custom && reserved.contains(binding.keys.first)) {
          throw FormatException(
            '${binding.keys.first} belongs to a native Mac editing or window command; choose another first key',
          );
        }
      }
    }
  }

  @override
  void dispose() {
    store?.removeListener(_changed);
    super.dispose();
  }
}

/// InheritedTheme lets dialogs/routes carry the same live configuration.
/// The provider rebuilds only on config changes, never on individual keys.
class KeymapProvider extends StatelessWidget {
  const KeymapProvider({super.key, required this.keymap, required this.child});
  final AppKeymap keymap;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: keymap,
    builder: (context, _) =>
        KeymapTheme(keymap: keymap, version: keymap.version, child: child),
  );
}

class KeymapTheme extends InheritedTheme {
  const KeymapTheme({
    super.key,
    required this.keymap,
    required this.version,
    required super.child,
  });
  final AppKeymap keymap;
  final int version;
  static AppKeymap? of(BuildContext context, {bool listen = true}) =>
      (listen
              ? context.dependOnInheritedWidgetOfExactType<KeymapTheme>()
              : context.getInheritedWidgetOfExactType<KeymapTheme>())
          ?.keymap;
  @override
  bool updateShouldNotify(KeymapTheme oldWidget) =>
      keymap != oldWidget.keymap || version != oldWidget.version;
  @override
  Widget wrap(BuildContext context, Widget child) =>
      KeymapProvider(keymap: keymap, child: child);
}

/// Pickers provide their own actions. A terminal only changes scope/IME state;
/// the containing workspace continues to own its navigation commands.
class KeymapRegion extends InheritedWidget {
  const KeymapRegion({
    super.key,
    required this.contextKind,
    this.actions,
    this.composing,
    required super.child,
  });
  final KeymapContext contextKind;
  final Map<String, VoidCallback>? actions;
  final bool Function()? composing;
  static KeymapRegion? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<KeymapRegion>();
  @override
  bool updateShouldNotify(KeymapRegion oldWidget) => false;
}

String? effectiveShortcutHint(BuildContext context, ShortcutAction action) {
  final command = harnessCommands
      .where((command) => command.action == action)
      .firstOrNull;
  final map = KeymapTheme.of(context);
  if (command == null) return null;
  final binding = (map?.current ?? harnessDefaultKeymap)
      .bindingsFor(KeymapContext.workspace)
      .where((binding) => binding.command == command.id)
      .firstOrNull;
  return binding == null ? null : describeKeyBinding(binding);
}

String withEffectiveShortcutHint(
  BuildContext context,
  String label,
  ShortcutAction action,
) {
  final hint = effectiveShortcutHint(context, action);
  return hint == null ? label : '$label  $hint';
}
