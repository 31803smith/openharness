# A coherent keyboard system for Harness

Research and complete default-binding audit: 2026-09-13. **Most defaults and file remapping below remain an implementation plan.** The current search change consolidates the old Cmd-P and Cmd-Shift-F experiences under Cmd-P, with an explicit Add action inside the picker. The parser/resolver and file reload core have isolated tests but are not connected to production dispatch yet. The [working queue](harness-v2-developer-tools-research.md) remains the status list.

## Principles from the tools

There is no universal expert keymap. These tools disagree about particular combinations; their useful common ground is stable commands, predictable scope, configurable bindings, and preserving the program inside the terminal.

| Primary source | Relevant behavior | Harness decision |
| --- | --- | --- |
| [Vim window commands](https://github.com/vim/vim/blob/master/runtime/doc/windows.txt) | Ctrl-W introduces window commands; h/j/k/l focus directions, while capitals move windows to edges. | Preserve these bytes inside Vim. Make focus and rearrangement distinct commands. A shifted Harness movement binding is an analogy, not identical Vim layout semantics. |
| [GNU Emacs reference](https://www.gnu.org/software/emacs/refcards/pdf/refcard.pdf) | Control and Meta are used extensively; Ctrl-X introduces commands, Ctrl-N/P move by line, and Ctrl-G cancels. | Preserve terminal Control/Meta input. Borrow Ctrl-N/P and Ctrl-G only inside Harness-owned pickers. |
| [tmux getting started](https://github.com/tmux/tmux/wiki/Getting-Started) | Prefix commands operate on persistent sessions, windows and panes. The default Ctrl-B prefix includes navigation, splitting, zoom, last-pane and command selection. | Keep the session/view distinction and reversible navigation. Do not intercept the inner tmux prefix by default. |
| [Zsh line editor](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html) | Explicit keymaps support Emacs and vi editing, and bindkey customizes widgets and sequences. | Respect the user's shell keymap; do not try to infer or replace its editing mode. |
| [fzf shell integration](https://github.com/junegunn/fzf#key-bindings-for-command-line) and [binding defaults](https://github.com/junegunn/fzf/blob/master/man/man1/fzf.1) | Incremental narrowing, configurable actions, arrow/Ctrl-N/P navigation and cancellation. Shell integration uses Ctrl-R, Ctrl-T and Alt-C. | Keep these shell keys available. Use one picker and shared picker navigation; plain letters continue entering the query. |
| [VS Code shortcuts](https://code.visualstudio.com/shortcuts/keyboard-shortcuts-macos.pdf) and [configuration](https://code.visualstudio.com/docs/configure/keybindings) | Quick Open is Cmd-P; commands are Cmd-Shift-P. Bindings have command identities, optional contexts, overrides and sequences. JSON and the visual editor configure the same system. | Keep Quick Open, add a small command mode backed by the existing actions, and make a text file the first customization interface. |
| [iTerm2 split panes](https://iterm2.com/documentation-one-page.html#split-panes) and [Ghostty actions](https://ghostty.org/docs/config/keybind/reference) | Directional split focus, reversible pane zoom and explicit split creation are first-class terminal operations. iTerm2 uses Cmd-Option-arrows for focus and Cmd-Shift-Enter for pane zoom. | Use that focus/zoom family. Reserve Cmd-D / Cmd-Shift-D for explicit splits when the layout feature exists. |
| [kitty configuration](https://sw.kovidgoyal.net/kitty/conf/#keyboard-shortcuts) | Tabs, inner windows, command navigation and configurable key mappings are separate concepts. Its defaults demonstrate that even terminal apps disagree on numeric navigation. | Choose and document Harness's object model consistently instead of mixing each app's defaults. |
| [Chrome shortcuts](https://support.google.com/chrome/answer/157179?hl=en) and [Mac conventions](https://support.apple.com/en-us/102650) | Familiar tab lifecycle, tab selection, back/forward, Find, and standard app commands. | Swarms are tabs. Keep that lifecycle familiar and restore standard Mac commands that current Harness bindings displaced. |

These references establish behavior, not a claim that every developer uses or prefers it. Control/Meta compatibility still needs exact input tests and native checks, including IME and modified-key encoding.

## Audit and proposed defaults

The current source is `desktop/lib/shortcuts/app_shortcuts.dart`, the Swarm screen's handlers, native menus in `SwarmTitlebar.swift` and `MainMenu.xib`, the terminal's handlers and the picker implementations. The legacy workspace and debug-only bindings were reviewed too.

The proposed macOS family is **Command for Swarms and common app actions; Command-Option for individual panes**. Shift reverses traversal or modifies a related action where that is already familiar. Terminal applications keep Control/Meta, ordinary keys, Escape and Tab by default. The app owns navigation keys inside its own picker.

| Action | Current binding | Proposed decision |
| --- | --- | --- |
| Quick Open / jump | Cmd-P | Keep. Return focuses an existing destination or explicitly opens an unviewed agent. |
| Add an existing agent here | Cmd-Shift-F, separate picker | Consolidated into Cmd-P by the user's latest decision. Return focuses an existing pane or opens its first view here. A visible Add to this swarm action (Cmd-Enter inside the picker) adds a shared view here. No separate default launcher, including Cmd-O. |
| Search app commands | None; Cmd-Shift-P pins | Cmd-Shift-P, reusing the picker with command mode. |
| New agent | Cmd-N; menu omits its shortcut | Keep and make menu/help agree. |
| New / close / reopen Swarm | Cmd-T / Cmd-W / Cmd-Shift-T | Keep. Closing a view does not end an agent. |
| Next / previous Swarm | Cmd-Shift-] / Cmd-Shift-[, plus Ctrl-Tab pair | Keep Command brackets; release the Control pair to terminal programs by default. Users can assign it explicitly. |
| Direct numeric selection | Cmd-1…9 focuses panes | Cmd-1…8 selects Swarm tabs; Cmd-9 selects the last tab. Cmd-Option-1…9 focuses pane positions. This is a deliberate default change to match the tab object model. |
| Back / forward | Cmd-[ / Cmd-] | Keep navigation history. |
| Full session history | Cmd-Y | Keep. |
| Directional pane focus | Cmd-arrows and Cmd-h/j/k/l | Cmd-Option-arrows. Vim-style letters are user mappings; Cmd-Option-H itself conflicts with native Hide Others and is not a safe default alias. |
| Rearrange pane | Cmd-Shift-arrows and Cmd-Shift-h/j/k/l | Cmd-Option-Shift-arrows, with distinct command IDs. |
| Zoom pane / restore | Cmd-Enter | Cmd-Shift-Enter, following established terminal apps. |
| Close pane view | Cmd-Shift-W | Cmd-Option-W. Keep normal window closing separate. |
| Last pane | Cmd-; | Retain as a searchable command. Quick Open / Return and history already support the common return loop. |
| Pin pane | Cmd-Shift-P | Retain as a searchable/context command; release Command Palette's familiar shortcut. |
| Choose layout | Cmd-S | Retain in View/commands; release Save's familiar shortcut. |
| Rename Swarm | Cmd-Shift-R | Retain in tab context menu and commands; avoid a surprising use of the reload family. |
| Needs input | Cmd-Shift-I | Keep: I identifies input, and this is an agent-specific action. |
| Find / next / previous | Cmd-F / Cmd-G / Cmd-Shift-G | Keep in the current terminal. |
| Refresh machines/agents | Cmd-R | Keep with an accurate label and explicit semantics; never reinterpret Ctrl-R history search. |
| Task routing | Cmd-B | Remove its default binding. Existing explicit/hardware entry points are a separate capability decision. |
| Settings / shortcuts help | Cmd-, / Cmd-/ | Keep and show effective configured bindings. |
| Debug inspector | Cmd-D in developer builds | Use a secondary inspector command; release split creation's familiar key. |
| Legacy sidebar toggle | Cmd-backslash, absent from Swarms | Keep absent from the active Swarm keymap. |
| Copy / paste / select all / undo / redo | Standard Mac keys through native/Flutter owners | Preserve. Audit actual event ownership, not just labels; native menu equivalents must not swallow the terminal's action. |
| Hide / Hide Others / minimize / quit / full screen | Hide's Cmd-H removed; other native defaults present | Restore Cmd-H. Preserve native app/window conventions and avoid assigning the same chord elsewhere. |
| Picker movement / acceptance / cancellation | Arrows, Ctrl-N/P, Return, Escape | The unified picker also accepts Ctrl-J/K and Ctrl-G. Return browses a machine/project or activates a destination; group opening is an explicit button. A composing-text guard has an isolated check; native IME behavior still needs validation. No global plain-letter Vim navigation in a search field. |

Do not advertise unimplemented splitting, global transcript search, terminal scrolling, or arbitrary remapping as working. Freeing a key does not by itself implement its expected action.

## File-first customization

Use one declarative, versioned text configuration, with sensible defaults inherited automatically. Proposed location: `$XDG_CONFIG_HOME/harness/keybindings.jsonc`, defaulting to `~/.config/harness/keybindings.jsonc`. Keep it separate from credentials and session state. JSON with comments follows the editor workflow without introducing an executable configuration language.

The app provides **Open Keyboard Config…**, effective bindings in help and menus, and automatic reload. A full visual keybinding editor is deferred; any future editor should modify the same file. Reading a missing config uses defaults and does not create files. Opening the config explicitly can create a small commented template.

The engine needs stable command IDs; aliases for modifier/key names; individual overrides; explicit unbinding; scoped bindings; and user-defined sequences. It should validate unknown commands, malformed keys, duplicate/ambiguous prefixes and conflicting native owners. Invalid reloads retain the last good map and report a useful error. Watch the containing directory so editor atomic-save replacement is supported, with bounded reload work and no polling per keystroke.

Resolve bindings when config or context changes. Ordinary input should perform a bounded lookup, with no disk, network or parsing work. Sequence handling must be explicit and cancelable; never introduce a delay to disambiguate a default single-key command, or replay an unsuccessful prefix into a real agent. Unbinding restores the normal terminal/platform route; what bytes a modified key can represent depends on the terminal protocol.

## Implementation and verification order

1. Build the command/config model, parser, validation and temporary-file reload tests. Keep current production defaults intact until dispatch and menu integration are ready.
2. Apply the coherent defaults and integrate one runtime resolver with native menus, the command/agent picker, help, tooltips and focused-terminal dispatch. Handle app, terminal and picker context explicitly.
3. Verify Control/Meta passthrough, exact key destinations, custom bindings, unbinding, sequences, modal/IME behavior and reload during active use with isolated sessions. Check all native menu equivalents against the same resolved definitions.
4. Rebuild/relaunch the authorized V2 preview, review the menus/help and navigation without typing tests into real agents, and publish the reviewed `app-v2` changes.
5. Resume native performance measurement after the keyboard work stabilizes. The isolated benchmark is currently calibration work, not a validated performance result. Foreground measurement is paused while the user is actively discussing the key system.
