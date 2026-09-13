# A coherent keyboard system for Harness

Updated 2026-09-13 after the user's review. **The earlier proposed modifier-heavy defaults are withdrawn.** The user explicitly chose to retain Cmd-H/J/K/L and Cmd-arrows for pane movement, Cmd-S for layout, Cmd-R for refresh, and Cmd-B for Boss mode. Cmd-L stays move right. File remapping is not enabled in the running preview yet.

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
| Search and open agents/swarms | Keep Cmd-P and the same direct-open behavior in both search fields. |
| Machine/project search result | Open its swarm directly; no intermediate Browse agents step. |
| Other existing shortcuts | Preserve until a concrete problem justifies a reviewed change. Do not silently switch Cmd-number navigation, zoom, tab traversal, or closing to the earlier proposed alternatives. |
| File customization | One commented config file with reload; menus, help and dispatch must agree. |
| Commands in search | Approved: optional `>` mode for existing actions. Preserve existing defaults, including Cmd-Shift-P for pin; no new conflicting command shortcut. |

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

## Implementation status and next steps

1. **Built and tested in isolation:** parser, resolver, validation, overrides/unbinding, sequences and file reload core. These are not yet connected to production dispatch.
2. **Needs revision:** the unused draft command catalog still contains the withdrawn defaults. Reconcile it with the current `app_shortcuts.dart` bindings before enabling it. The preserved runtime integration patch also needs rebasing onto the two search fields and direct group opening.
3. **Next implementation:** one runtime binding system for the agent workspace, search, native menus, help and tooltips, retaining the agreed defaults above. Audit native owners for conflicts with those defaults instead of assuming system conventions win.
4. **Validation:** exact action and focus destinations, custom remaps, unbinding, repeated movement, sequences, cancellation, modal/IME behavior, and live config reload in isolated agent fixtures. Do not type tests into real agents.
5. **Delivery:** rebuild and inspect the preview only after integration passes. The broader [working queue](harness-v2-developer-tools-research.md) tracks product proposals separately from authorized fixes.
