import '../logging/debug_surface.dart';
import 'app_shortcuts.dart';
import 'keymap.dart';

/// Stable identities are the public dotfile interface. Labels, defaults,
/// native menus and the command picker read this same catalog.
class HarnessCommand {
  const HarnessCommand(
    this.id,
    this.label,
    this.group, {
    this.keys = const [],
    this.action,
    this.nativeAction,
    this.context = KeymapContext.workspace,
    this.repeatable = false,
  });
  final String id, label;
  final ShortcutGroup group;
  final List<String> keys;
  final ShortcutAction? action;
  final String? nativeAction;
  final KeymapContext context;
  final bool repeatable;
}

final harnessCommands = <HarnessCommand>[
  const HarnessCommand(
    'navigation.quick_open',
    'Search agents, swarms, machines and projects',
    ShortcutGroup.navigate,
    keys: ['cmd+p'],
    action: ShortcutAction.switchAgent,
    nativeAction: 'jump',
  ),
  const HarnessCommand(
    'navigation.commands',
    'Search commands',
    ShortcutGroup.actions,
    keys: ['cmd+shift+p'],
    nativeAction: 'commands',
  ),
  const HarnessCommand(
    'swarm.new',
    'New swarm',
    ShortcutGroup.navigate,
    keys: ['cmd+t'],
    action: ShortcutAction.newSwarm,
    nativeAction: 'new',
  ),
  const HarnessCommand(
    'swarm.close',
    'Close this swarm',
    ShortcutGroup.navigate,
    keys: ['cmd+w'],
    action: ShortcutAction.closeSwarm,
    nativeAction: 'closeActive',
  ),
  const HarnessCommand(
    'swarm.reopen',
    'Reopen last closed agent or swarm',
    ShortcutGroup.navigate,
    keys: ['cmd+shift+t'],
    action: ShortcutAction.reopenClosedSwarm,
    nativeAction: 'reopen',
  ),
  const HarnessCommand(
    'swarm.next',
    'Next swarm',
    ShortcutGroup.navigate,
    keys: ['cmd+shift+]'],
    action: ShortcutAction.nextSwarm,
    nativeAction: 'next',
    repeatable: true,
  ),
  const HarnessCommand(
    'swarm.previous',
    'Previous swarm',
    ShortcutGroup.navigate,
    keys: ['cmd+shift+['],
    action: ShortcutAction.previousSwarm,
    nativeAction: 'previous',
    repeatable: true,
  ),
  const HarnessCommand(
    'swarm.rename',
    'Rename this swarm',
    ShortcutGroup.actions,
    action: ShortcutAction.renameSwarm,
    nativeAction: 'renameActive',
  ),
  const HarnessCommand(
    'navigation.back',
    'Go back',
    ShortcutGroup.navigate,
    keys: ['cmd+['],
    action: ShortcutAction.previousAgent,
    nativeAction: 'historyBack',
    repeatable: true,
  ),
  const HarnessCommand(
    'navigation.forward',
    'Go forward',
    ShortcutGroup.navigate,
    keys: ['cmd+]'],
    action: ShortcutAction.nextAgent,
    nativeAction: 'historyForward',
    repeatable: true,
  ),
  const HarnessCommand(
    'navigation.history',
    'Show full history',
    ShortcutGroup.navigate,
    keys: ['cmd+y'],
    action: ShortcutAction.showHistory,
    nativeAction: 'showHistory',
  ),
  const HarnessCommand(
    'navigation.needs_input',
    'Show agents needing input',
    ShortcutGroup.navigate,
    keys: ['cmd+shift+i'],
    action: ShortcutAction.showAttention,
    nativeAction: 'notifications',
  ),
  for (var i = 1; i <= 9; i++)
    HarnessCommand(
      'swarm.select_$i',
      i == 9 ? 'Select the last swarm' : 'Select swarm $i',
      ShortcutGroup.navigate,
      keys: ['cmd+$i'],
    ),
  for (var i = 1; i <= 9; i++)
    HarnessCommand(
      'pane.focus_$i',
      'Focus pane $i',
      ShortcutGroup.panes,
      keys: ['cmd+alt+$i'],
    ),
  const HarnessCommand(
    'pane.focus_left',
    'Focus the pane to the left',
    ShortcutGroup.panes,
    keys: ['cmd+alt+left'],
    action: ShortcutAction.focusPaneLeft,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.focus_right',
    'Focus the pane to the right',
    ShortcutGroup.panes,
    keys: ['cmd+alt+right'],
    action: ShortcutAction.focusPaneRight,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.focus_above',
    'Focus the pane above',
    ShortcutGroup.panes,
    keys: ['cmd+alt+up'],
    action: ShortcutAction.focusPaneAbove,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.focus_below',
    'Focus the pane below',
    ShortcutGroup.panes,
    keys: ['cmd+alt+down'],
    action: ShortcutAction.focusPaneBelow,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.move_left',
    'Move the pane left',
    ShortcutGroup.panes,
    keys: ['cmd+alt+shift+left'],
    action: ShortcutAction.movePaneLeft,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.move_right',
    'Move the pane right',
    ShortcutGroup.panes,
    keys: ['cmd+alt+shift+right'],
    action: ShortcutAction.movePaneRight,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.move_up',
    'Move the pane up',
    ShortcutGroup.panes,
    keys: ['cmd+alt+shift+up'],
    action: ShortcutAction.movePaneUp,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.move_down',
    'Move the pane down',
    ShortcutGroup.panes,
    keys: ['cmd+alt+shift+down'],
    action: ShortcutAction.movePaneDown,
    repeatable: true,
  ),
  const HarnessCommand(
    'pane.zoom',
    'Zoom or restore the focused pane',
    ShortcutGroup.panes,
    keys: ['cmd+shift+enter'],
    action: ShortcutAction.zoomPane,
    nativeAction: 'zoomPane',
  ),
  const HarnessCommand(
    'pane.close',
    'Remove the focused agent from this swarm',
    ShortcutGroup.panes,
    keys: ['cmd+alt+w'],
    action: ShortcutAction.closePane,
    nativeAction: 'closePane',
  ),
  const HarnessCommand(
    'pane.last',
    'Return to the last pane',
    ShortcutGroup.panes,
    action: ShortcutAction.lastPane,
  ),
  const HarnessCommand(
    'pane.pin',
    'Pin or unpin the focused pane',
    ShortcutGroup.panes,
    action: ShortcutAction.pinPane,
  ),
  const HarnessCommand(
    'pane.layout',
    'Choose a layout',
    ShortcutGroup.panes,
    action: ShortcutAction.showLayout,
    nativeAction: 'layout',
  ),
  const HarnessCommand(
    'terminal.find',
    'Find in the focused terminal',
    ShortcutGroup.navigate,
    keys: ['cmd+f'],
    action: ShortcutAction.findTerminal,
    nativeAction: 'findTerminal',
  ),
  const HarnessCommand(
    'terminal.find_next',
    'Next terminal match',
    ShortcutGroup.navigate,
    keys: ['cmd+g'],
    action: ShortcutAction.findNext,
    nativeAction: 'findNext',
    repeatable: true,
  ),
  const HarnessCommand(
    'terminal.find_previous',
    'Previous terminal match',
    ShortcutGroup.navigate,
    keys: ['cmd+shift+g'],
    action: ShortcutAction.findPrevious,
    nativeAction: 'findPrevious',
    repeatable: true,
  ),
  const HarnessCommand(
    'agent.new',
    'New agent',
    ShortcutGroup.actions,
    keys: ['cmd+n'],
    action: ShortcutAction.newAgent,
    nativeAction: 'newAgent',
  ),
  const HarnessCommand(
    'machine.link',
    'Link machine',
    ShortcutGroup.actions,
    nativeAction: 'linkMachine',
  ),
  const HarnessCommand(
    'project.add',
    'Add project',
    ShortcutGroup.actions,
    nativeAction: 'addProject',
  ),
  const HarnessCommand(
    'machines.refresh',
    'Refresh machines and agents',
    ShortcutGroup.actions,
    keys: ['cmd+r'],
    action: ShortcutAction.reload,
    nativeAction: 'reload',
  ),
  const HarnessCommand(
    'task.route',
    'Route a task',
    ShortcutGroup.actions,
    action: ShortcutAction.routeTask,
  ),
  const HarnessCommand(
    'app.settings',
    'Open Settings',
    ShortcutGroup.actions,
    keys: ['cmd+comma'],
    action: ShortcutAction.showSettings,
    nativeAction: 'settings',
  ),
  const HarnessCommand(
    'keyboard.help',
    'Keyboard shortcuts',
    ShortcutGroup.actions,
    keys: ['cmd+slash'],
    action: ShortcutAction.showShortcuts,
    nativeAction: 'showShortcuts',
  ),
  const HarnessCommand(
    'keyboard.open_config',
    'Open keyboard config',
    ShortcutGroup.actions,
    nativeAction: 'openKeymap',
  ),
  if (kDebugSurfaceEnabled)
    const HarnessCommand(
      'app.debug',
      'Open the debug log',
      ShortcutGroup.actions,
      action: ShortcutAction.showDebug,
    ),
  const HarnessCommand(
    'picker.next',
    'Next result',
    ShortcutGroup.navigate,
    keys: ['down', 'ctrl+n', 'ctrl+j'],
    context: KeymapContext.picker,
    repeatable: true,
  ),
  const HarnessCommand(
    'picker.previous',
    'Previous result',
    ShortcutGroup.navigate,
    keys: ['up', 'ctrl+p', 'ctrl+k'],
    context: KeymapContext.picker,
    repeatable: true,
  ),
  const HarnessCommand(
    'picker.accept',
    'Open the selected result',
    ShortcutGroup.navigate,
    keys: ['enter'],
    context: KeymapContext.picker,
  ),
  const HarnessCommand(
    'picker.add_here',
    'Add the selected agent to this swarm',
    ShortcutGroup.actions,
    keys: ['cmd+enter'],
    context: KeymapContext.picker,
  ),
  const HarnessCommand(
    'picker.cancel',
    'Close search',
    ShortcutGroup.navigate,
    keys: ['escape', 'ctrl+g'],
    context: KeymapContext.picker,
  ),
  const HarnessCommand(
    'picker.back',
    'Return to all results',
    ShortcutGroup.navigate,
    keys: ['cmd+['],
    context: KeymapContext.picker,
  ),
];

final harnessCommandById = {
  for (final command in harnessCommands) command.id: command,
};
final harnessDefaultBindings = [
  for (final command in harnessCommands)
    for (final keys in command.keys)
      KeyBinding(
        keys: keys.split(' ').map(KeyStroke.parse),
        command: command.id,
        context: command.context,
      ),
];
final harnessDefaultKeymap = ResolvedKeymap(
  harnessDefaultBindings,
  const KeymapConfig.empty(),
);

String describeKeyStroke(KeyStroke stroke) => [
  if (stroke.control) '⌃',
  if (stroke.alt) '⌥',
  if (stroke.shift) '⇧',
  if (stroke.command) '⌘',
  const {
        'left': '←',
        'right': '→',
        'up': '↑',
        'down': '↓',
        'enter': '↵',
        'escape': 'Esc',
        'tab': '⇥',
        'space': 'Space',
        'comma': ',',
        'period': '.',
        'slash': '/',
        'backslash': r'\',
        'semicolon': ';',
        'quote': "'",
        'backquote': '`',
        'bracketleft': '[',
        'bracketright': ']',
        'minus': '-',
        'equal': '=',
        'backspace': '⌫',
        'delete': '⌦',
      }[stroke.key] ??
      stroke.key.toUpperCase(),
].join();
String describeKeyBinding(KeyBinding binding) =>
    binding.keys.map(describeKeyStroke).join(' ');
