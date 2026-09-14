# A coherent keyboard system for Harness

Current continuation: [goal, plan, and acceptance criteria](harness-v2-handoff.md)
and [Harness entry](harness-agent-first-tabs.md). Updated September 14, 2026.
**Command-1 through Command-9 now select tabs in their current visual order**,
replacing their former pane-focus defaults. An unavailable number does nothing.
Command-H/J/K/L and Command-arrows still move between panes, retaining each tab's
last focused pane when switching back.

Cmd-T opens New Harness, Cmd-N opens Add Agent, and Shift-Cmd-N creates a fresh
agent. Add uses immediate single selection; there is no multi-select or Shift-Enter
staging. Cmd-Shift-P opens command mode. The Navigate directory and default Cmd-P
were removed by the agent-first update. Cmd-S, Cmd-R and Cmd-B keep their layout,
refresh and task-routing behavior. File remapping remains available; menus and
help reflect the effective bindings.

## Product contract

Harness is a workspace for directing agents such as Claude Code and Codex. The research should borrow effective interaction patterns from developer tools and adapt them to this workflow. It must not turn Harness into a general-purpose terminal or optimize its defaults around hypothetical nested Vim/Emacs/tmux sessions.

Command is the easy Harness prefix: one modifier plus a key for frequent actions. Preserve existing effective bindings. Additional modifiers are appropriate only for less frequent related variants, such as rearranging rather than focusing a pane. Do not impose three-key combinations on frequent navigation just because another application uses them.

Keep ordinary typing and editing predictable inside the actual agent CLI, search field, or dialog. This is input correctness, not a requirement to support a new shell or editor product. Composition must finish without accidentally submitting a search result or moving to another agent.

## Decisions now agreed

| Action | Decision |
| --- | --- |
| Focus adjacent pane | Keep Cmd-H/J/K/L and Cmd-arrows. |
| Layout | Keep Cmd-S. The user explicitly resolved the Cmd-L conflict in favor of the complete H/J/K/L family. |
| Refresh machines/agents | Keep Cmd-R. The user considered using it for relayout and chose to preserve refresh. |
| Boss mode / task routing | Keep Cmd-B. |
| Select a tab | Cmd-1…Cmd-9 select positions 1…9 in the visible tab order. Reordering tabs changes those positions. Closing or switching tabs preserves each tab’s pane focus. |
| Local Add agent | New Harness, floating +, and Split share immediate existing-agent selection and a prominent Create Agent action. Keep the target tab/position. |
| Machine/project results | One group result seeds its existing agents into the current tab. There is no multi-select basket or separate group-creation step. |
| Other existing shortcuts | Preserve until a concrete problem justifies a reviewed change. Numbered tab selection is now explicitly approved; preserve zoom, traversal and closing. |
| File customization | One commented config file with reload; menus, help and dispatch must agree. |
| Commands in search | Approved: Cmd-Shift-P opens `>` command mode, following the later user decision. Pin remains in File, commands and custom bindings; it is absent from pane headers. |

The previous full default-binding audit is preserved in Git history. Its evidence is useful, but its proposed defaults do not override these decisions.

## What the research contributes

| Primary source | Useful interaction pattern for Harness |
| --- | --- |
| [Vim window commands](https://github.com/vim/vim/blob/master/runtime/doc/windows.txt) | Spatial H/J/K/L movement and a clear distinction between focusing and rearranging. Keep the user's simpler Command prefix. |
| [tmux](https://github.com/tmux/tmux/wiki/Getting-Started) | Stable sessions, predictable pane navigation, last-pane return and zoom. Borrow the operations, not the cumbersome Ctrl-B prefix. |
| [GNU Emacs](https://www.gnu.org/software/emacs/refcards/pdf/refcard.pdf) | Consistent command families, configurable bindings, and immediate cancellation. |
| [Zsh line editor](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html) | Named actions and explicit configuration rather than guessing a user's editing mode. |
| [fzf bindings](https://github.com/junegunn/fzf/blob/master/man/man1/fzf.1) | Incremental narrowing, clear selection, configurable actions and an optional preview when it helps identification. |
| [VS Code configuration](https://code.visualstudio.com/docs/configure/keybindings) | Stable command IDs, overrides, unbinding, contexts, and a file that a future visual editor can also edit. |
| [iTerm2](https://iterm2.com/documentation-one-page.html#split-panes) and [Ghostty](https://ghostty.org/docs/config/keybind/reference) | Direct pane control and reversible zoom. Their particular modifier combinations are not automatically appropriate for Harness. |
| [kitty configuration](https://sw.kovidgoyal.net/kitty/conf/#keyboard-shortcuts) | Customizable command mappings with a clear distinction between tabs and panes. |
| [Chrome shortcuts](https://support.google.com/chrome/answer/157179?hl=en) | Familiar tab lifecycle, History and Find where those behaviors fit the agent workspace. |

These sources document tool behavior; they do not establish one universal expert keymap. The user's actual workflow and daily-use evidence govern the choices.

## File-first customization

Location: `$XDG_CONFIG_HOME/harness/keybindings.jsonc`, defaulting to `~/.config/harness/keybindings.jsonc`. Use declarative JSON with comments, inherited defaults, stable command IDs, individual overrides, explicit unbinding, contexts and optional user-defined sequences. No executable configuration language is needed.

Opening Keyboard Config can create a commented template; simply starting the app with no config should create nothing. Automatic reload must tolerate atomic editor saves. An invalid edit keeps the last good bindings and shows a useful error. A full visual editor is deferred; it should edit this same file if later needed.

Parse and resolve when configuration changes, never on each keystroke. A lookup must perform no disk or network work. Sequences must be cancelable and must not replay a failed prefix as a message to an agent. Default frequent actions need no prefix timeout.

## Implementation and validation

Production startup loads the optional file before the workspace opens. Settings and the shortcut sheet show the effective bindings for Workspace, Agent input or Search, including unassigned commands. **Edit keyboard config** creates a commented template only when explicitly invoked, lists the stable command IDs, and opens the associated editor. The startup path, watcher and dispatch never rewrite existing user configuration.

Flutter owns configured workspace/terminal keys before the focused input, with live composition checks. Both search fields use their own picker context. Their Enter/add actions and displayed hints update together; the command result list also refreshes its shortcut labels after a configuration change. Prefixes are temporary and never replay into agent input. Cmd-N opens Add; Cmd-Shift-P opens command mode. Numbered keys select tabs in workspace, terminal and picker contexts, with modal/composition guards still respected.

Native menu labels come from the same resolved snapshot. The main menu yields configured first strokes to Flutter, which owns both search editors, text selection, composition and result navigation. The titlebar contains tabs, New Harness and Notifications. The floating Add button is inside the swarm, with the effective Cmd-N hint; Create Agent is prominent inside Add. Button activation waits for the destination's Flutter frame before returning native keyboard focus to the content view. Ordinary Mac editing, font and window commands remain native; custom bindings using reserved strokes are rejected.

Current validation covers the shared editor, effective remaps, terminal IME,
numbered tab selection through Flutter and the native command bridge, reordered
tabs, preserved pane focus and the first subsequent terminal key. Native fixtures
consume the Dart-exported bindings. These are synthetic correctness checks; no
real agents receive test input. Current build and test counts are in the progress log.

See the [progress log](harness-v2-progress.md) for build/artifact status and the [working queue](harness-v2-developer-tools-research.md) for the next product improvements. These fixtures do not establish native input-to-display latency or first-install conversion rates; those remain separate measurements.
