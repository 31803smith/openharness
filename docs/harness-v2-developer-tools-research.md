# What Harness should learn from developers' daily tools

Research and source audit: 2026-09-12. Recommendation for the existing `app-v2` build.

Harness should make three things excellent: **keep work alive, reach any work instantly, and steer agents without losing concentration.** A developer should be able to spend a whole day here directing their existing agents.

This is a qualitative sample of firsthand accounts and tool authors' documentation, not a survey of all exceptional developers. “World-class” has no objective tool list. Publication dates matter: several authors have changed their workflows. Product documentation establishes advertised behavior; it does not independently establish performance, reliability or developer affection.

## Current implementation queue

Updated 2026-09-13 after user review. Keep the existing simple Command shortcuts: H/J/K/L and arrows for movement, S for layout, B for Boss mode. The modifier-heavy proposal and general-purpose-terminal assumption are withdrawn. This is the working list; [the progress log](harness-v2-progress.md) records checks and remaining gaps.

| Status | Work |
| --- | --- |
| In the preview | Real machine/project data; native Swarm tabs; wallpaper only in New swarm; Cmd+P jump, Needs input and terminal Find. |
| Fixed and rebuilt | Cmd+P stale focus/offscreen targets; retained offline output and composer drafts; blocking frozen overlays removed. |
| In the rebuilt preview | Settings gear removed on macOS; native File/History menus and Cmd+P routing. Menus and picker typing verified live; focus/input regression tests pass. |
| Rebuilt; native menu reviewed live | Models replaces Swarm; Subscription shows existing account limits, while API, Local and Add Model are disabled placeholders. History uses provider icons and restores both closed agents and closed Swarms. Recovery is covered with isolated sessions; live agents were not closed to test it. |
| Rebuilt and reviewed live | Chrome-style Back/Forward, Recently Closed/Visited and full session History; compact branch-aware headers; Workshop includes its requested iMac Home agent. |
| In the rebuilt preview; regression verified | Preserve the session, terminal view, Find, viewport, selection and draft context through reconnect/keyframe replacement. Stale output/input/upload completions cannot affect the replacement stream. A real remote interruption remains to be validated. |
| Rebuilt; live search/project review passed | One top-right Cmd-P search for agents, Swarms, machines and projects, with Open and explicit Add here actions. Follow-up in validation: New swarm searches in place, and machine/project results open their swarm directly. Separate Add picker, floating pane + and titlebar bell removed. New swarm uses only the selected mountain/lake wallpaper; rotation and other assets removed. Native typing, Cmd-P select-all and Escape were verified from an existing empty New swarm after the focus correction. |
| Implemented; measured in isolation | Unified search construction and ranking avoid repeated scans/metadata work. Median catalog construction fell 50% in the 2,059-destination debug fixture; native input-to-display measurement remains separate. |
| In progress | [Audit all shortcuts and implement a coherent agent-workspace key system with file-first remapping](harness-v2-keyboard-system.md). Config parser/resolver and live reload core pass isolated tests. The catalog now derives the live defaults and feeds `>` search commands. Finish runtime remapping, native menus and help while retaining those defaults. Remapping is not yet enabled. |
| Calibration in progress; foreground runs paused | Native Release input/navigation fixture with synthetic terminals. No validated latency result yet; resume after the keyboard work stabilizes. Live keyboard/tab/drag and real remote interruption checks remain. |
| Resizing and commands implemented; splits/preview next | `>` commands work in both search fields. Controlled resizing uses the existing gaps, saves proportions, protects usable sizes, retains terminal elements and has keyboard access through search; Cmd-S resets through the layout picker. The full 1,131-test suite passed before the final temporary-hint refinement, which passed focused checks. Deliberate right/down splits and optional cached search preview remain next. Match highlighting is the smaller search refinement. [The six-prototype review](harness-v2-prototype-review.md) records what to borrow and what stays out. |
| Keep deferred | Workflow canvases, autonomous manager layers, a full IDE/Git client and a marketplace. |

## Remaining ideas for review

No additional product confirmation blocks the approved milestone. These are the remaining research ideas, with a recommendation to **defer all five**:

| Idea | Why defer |
| --- | --- |
| Open an agent's changes in an external editor/diff tool | Useful later; first establish accurate checkout/change context across machines. |
| Jump between prompts, answers, errors and changes | Requires reliable agent markers; guessing from text would make navigation unpredictable. |
| Swarm CLI/API for scripts | Stabilize the app's operations first, then expose those same operations through the existing CLI. |
| Structured agent-to-agent handoff | Improve the existing Boss mode before adding another coordination workflow. |
| Visual shortcut editor | Deliver the approved file config first; a later editor should edit that same file. |

API/local-model connections and Add Model remain disabled by explicit user instruction. The dashboard, permanent shelf/sidebar, workflow canvas, manager layers and marketplace stay out. Usage ledger and hardware features remain available away from the main work loop; this is not a proposal to delete them.

Newly authorized follow-ups: consistent Models account IDs and complete status labels; swarm machine context in History; one four-pane swarm icon; readable search actions without repeated row labels; research terminal palette selection and add a small coordinated Appearance palette chooser.

## What people actually describe using

| Developer / primary evidence | Tools and behavior in the account | What Harness can learn |
| --- | --- | --- |
| **Mitchell Hashimoto**, [AI adoption journey, February 2026](https://mitchellh.com/writing/my-ai-adoption-journey) | Describes learning Claude Code, later using Amp, giving agents verification tools and keeping background work going. Explicitly turns off agent desktop notifications to protect deep work. | Preserve the developer's control of attention. Make waiting work easy to find voluntarily. Give agents fast access to the project's real verification commands. |
| **ThePrimeagen**, [tmux-sessionizer source and personal mappings](https://github.com/ThePrimeagen/tmux-sessionizer) and [Harpoon](https://github.com/ThePrimeagen/harpoon/tree/harpoon2), inspected September 2026 | Connects tmux, fzf, Vim and zsh mappings. Sessionizer reaches project sessions; Harpoon gives frequently used destinations direct keys. | Search is useful for unfamiliar destinations; repeated movement should become a direct jump. Switching to existing work should not create another copy of it. |
| **Julia Evans**, [fish, September 2024](https://jvns.ca/blog/2024/09/12/reasons-i--still--love-fish/) and [Helix, October 2025](https://jvns.ca/blog/2025/10/10/notes-on-switching-to-helix-from-vim/) | Praises fish's defaults, completion, history and multiline paste. After years of Vim/Neovim, tries Helix because language features work with less configuration. | Excellent defaults matter alongside customization. Keyboard fluency should not require maintaining a large configuration or relearning ordinary text entry. |
| **Peter Steinberger**, [workflow, August 2025](https://steipete.me/posts/2025/optimal-ai-development-workflow) and [updated workflow, December 2025](https://steipete.me/posts/2025/shipping-at-inference-speed) | August: Ghostty, Claude Code, an editor beside it, a few visible agents and CLI tools. December: Codex, queued follow-ups, multiple projects and iterative steering. Reports little need for elaborate orchestration systems. | Make terminal rendering, paste, identifiable sessions and steering dependable. Support a small working set well. A project board or autonomous manager is not a prerequisite. |
| **Simon Willison**, [parallel coding agents, October 2025](https://simonwillison.net/2025/Oct/5/parallel-coding-agents/) and [Git with coding agents](https://simonwillison.net/guides/agentic-engineering-patterns/using-git-with-coding-agents/), inspected September 2026 | Uses several agent products, terminals and isolated checkouts. Describes review as a substantial cognitive burden. Git provides inspection, recovery and context from recent changes. | Keep agents interchangeable, preserve project identity, and make it easy to inspect the result. “Finished generating” is not the same state as “reviewed and accepted.” |
| **Mario Zechner**, [minimal coding agent, November 2025](https://mariozechner.at/posts/2025-11-30-pi-coding-agent/) | Explains building Pi after becoming frustrated with changing behavior, unwanted features, flicker and hidden context. Values inspectable interactions, a documented session format and a small core. | Favor stable behavior and explicit actions. Expose useful data and commands for extensions. A generic agent should not need to adopt a proprietary workflow to fit into Harness. |

These accounts do not agree on everything. Hashimoto described one background agent; Steinberger described several projects. Some use worktrees or separate checkouts; others avoid that overhead. Evans values minimal configuration; ThePrimeagen builds personal mappings. Harness should support these choices through a small set of dependable operations.

## Tool behaviors worth carrying forward

The Harness column is a product inference, rather than a claim that the source endorses this app.

| Tool | Specific behavior | Harness application |
| --- | --- | --- |
| [tmux](https://github.com/tmux/tmux) | Terminals outlive an attached screen and can be reattached. | A session owns the work; tabs and panes are views. Closing a view never ends an agent. Reconnection restores the correct session, viewport and focus. Host reboot recovery must be distinguished from a process that never stopped. |
| [fzf](https://github.com/junegunn/fzf) | Fast narrowing, previews, shell integration and programmable actions. | One fast jump interface for agents, swarms and projects, with keyboard preview and clear destinations. Search already-open work without altering membership. |
| [Harpoon](https://github.com/ThePrimeagen/harpoon/tree/harpoon2) | A small chosen working set and direct navigation keys. | Quick return to the last agent and chosen destinations. Build on existing pane index keys and last-focus behavior before adding another favorites system. |
| Vim / Neovim, as used in [Sessionizer](https://github.com/ThePrimeagen/tmux-sessionizer) | Consistent mappings connect editor, shell and multiplexer navigation. | Predictable directional focus, moves and zoom; remappable app commands. Keep direct Command movement and make the focused agent and temporary modes obvious. A complete second editor is unnecessary. |
| zsh / fish and [fzf shell integration](https://github.com/junegunn/fzf#key-bindings-for-command-line) | Completion and history remain part of the user's shell workflow. | Borrow incremental narrowing and recent destinations for finding agents. Preserve actual coding-agent prompt editing; a general shell, aliases and nested editors are outside this milestone. |
| [Ghostty shell integration](https://ghostty.org/docs/features/shell-integration) | Working-directory inheritance, prompt navigation and command-output selection. | Start related work in the correct folder; make output easy to navigate and copy. Prefer reliable signals supplied by each coding agent; do not guess prompt boundaries from arbitrary screen text. |
| [Mosh](https://mosh.org/) | Roaming, reconnection and local echo address remote interaction latency. | Keep local navigation responsive during network trouble and clearly show connection state. Evaluate prediction separately: an arbitrary agent TUI cannot safely be treated like a simple shell prompt. |
| Git, as described in [Willison's guide](https://simonwillison.net/guides/agentic-engineering-patterns/using-git-with-coding-agents/) | Inspectable changes, history and recovery. | Open the relevant diff, editor or test result from an agent. Preserve existing Git tools and workspace choices. A new Git client is unnecessary for the first version. |

## Superlogical and Herdr

[Superlogical's announcement](https://www.superlogical.com/) describes a terminal multiplexer first, followed by composability and production operation. It emphasizes durable sessions across environments and native scrollback, selection and scrolling. The page still presents a plan and a beta signup; those are not evidence of a shipped, measured experience.

[Herdr's own site](https://herdr.dev/) describes persistent terminals, multiple agents, local and SSH machines, agent state and CLI/socket control. These are product claims checked against its published material, not an independent reliability audit.

The opportunity for Harness is to make movement among real agents across real machines unusually effortless. Matching a feature count is not a useful goal. The daily experience should answer: where was I, what needs me, what changed, and can I get back to work immediately?

## Audit of the current Harness build

| Decision | Existing surface or behavior | Action and reason |
| --- | --- | --- |
| **Keep and finish** | Native Swarm tabs, terminal panes, directional focus, zoom, last-pane and close/reopen | These already support a small working set. Finish native alignment, overflow, accessibility and measured interaction latency. |
| **Keep and harden** | Shared terminal controllers, saved membership, reconnect and local/remote discovery | This is the foundation. Preserve input ownership, scrollback and chosen arrangements through interruption. Validate remote failures on real linked machines; do not infer that a disconnected agent stopped. |
| **Implemented; verify in daily use** | One `Cmd+P` search for agents, Swarms, machines and projects | Fuzzy search covers name/project/branch/folder/machine context, with recent destinations and shared-terminal reuse. Enter focuses/opens work; explicit Add here adds it to the captured Swarm. The separate `Cmd+Shift+F` picker is removed. Navigation preserves focus/layout and terminal ownership without retrying a stream. No dialog fade or backdrop blur. |
| **Implemented; verify in daily use** | **Needs input** replaces the notifications list; `Cmd+Shift+I` opens it | Search live questions and agent/project/machine context; jump without changing ownership or chosen membership. `Cmd+P`, Return goes back to prior work. Resolved/replaced questions cannot trigger stale navigation. Unavailable terminals remain explicit. Opens on request with no fade, blur or polling. |
| **Implemented; verify in daily use** | Terminal Find with `Cmd+F`, `Cmd+G` and `Cmd+Shift+G` | Search retained output and move between literal matches without sending input. Escape restores the previous scroll position and prompt focus. The compact field uses the existing header, then disappears. These familiar bindings are documented by [Apple Terminal](https://support.apple.com/en-euro/guide/terminal/trmlshtcts/mac) and [Chrome](https://support.google.com/chrome/answer/157179?co=GENIE.Platform%3DDesktop&hl=en). Retained offline panes now remain searchable; never-attached panes retain setup guidance. |
| **Removed blocking chrome** | Full-pane frozen and reconnect overlays | Read-only status and explicit Reconnect/Take control actions live in the header. Retained output, selection, search and unsent composer text survive unavailable-machine presentation. Ordinary tab navigation never retries a dead stream. |
| **Preserve input correctness** | Real agent CLIs | Verify selection, multiline/image paste, scrollback and composition in Claude Code, Codex and other supported agents. Ordinary-shell creation and nested editor compatibility are outside this milestone. |
| **Remove from active work — implemented** | Wallpaper behind populated Swarms | Use the selected workspace palette, matching the native tab. Wallpaper fills only an empty New swarm canvas and its decoded cache entry is evicted when that view is disposed. |
| **In the rebuilt preview** | Chrome-style History, Models menu and Settings in the app menu | Settings stays in the macOS app menu with `Cmd+,`. File groups creation, linking, renaming, closing and Reopen Last Closed. History includes closed agents and Swarms, with provider icons for agents. Cmd+P lives in Edit, Needs Input in View. Models has live Subscription usage and explicitly disabled API/Local/Add Model placeholders. Lists are bounded and session-local. The non-macOS toolbar retains Settings access. |
| **In the rebuilt preview** | Wallpaper rotation and repeated metadata removed | The selected mountain/lake image is the only wallpaper; rotation button, menu actions and other assets are removed. Headers show one agent title, available branch, machine and controls. Repeated project-name text is removed; full folder/branch context remains on demand. Narrow panes use a machine icon with its full-name tooltip. |
| **Removed avoidable waiting** | Settings route transitions and section cross-fades | Implemented: Settings now opens/closes and switches sections immediately. Removed the 170/120 ms route and 200/90 ms section fades; existing route/modal checks pass. Reserve animation for feedback that helps understanding. |
| **Keep optional; stop expanding** | Usage ledger and hardware/dial settings | Usage can answer a real cost question; hardware supports existing users. Keep these away from the main work loop. Do not delete capabilities or data merely because they were absent from this small research sample. |
| **Keep absent** | Grid dashboard, permanent workspace sidebar, pane footers | The authenticated V2 shell already removed these. The user now explicitly requested a compact Models menu; this does not authorize restoring the Grid dashboard or model setup flows. API, Local and Add Model remain disabled by request. |
| **Defer** | Workflow canvases, autonomous manager-of-managers, social features, a plugin marketplace, a full IDE or a new Git client | None is required to prove the first three promises. Add only after repeated daily-use evidence identifies a concrete need. |

Source inspection: `desktop/lib/screens/swarm_screen.dart`, `widgets/swarm_dialogs.dart`, `state/swarm_catalog.dart`, `shortcuts/app_shortcuts.dart`, `settings/settings_screen.dart`, `settings/settings_section.dart`, `widgets/new_agent_dialog.dart`, and `macos/Runner/SwarmTitlebar.swift`. Existing checks and implementation details are recorded in [the handoff](harness-v2-progress.md) and [performance notes](harness-v2-performance.md).

## Native menu convention

Apple's [native menu documentation](https://developer.apple.com/documentation/swiftui/building-and-customizing-the-menu-bar-with-swiftui) shows File handling New Message, Close and opening a conversation in a window. File represents creating/opening/closing the app's work, beyond documents on disk. For Harness, the corresponding work is a Swarm or agent view. Keep Edit's standard text actions, View's layout/font controls, and the system Window menu.

Chrome is the user's primary interaction reference. Chromium's [menu definition](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/ui/cocoa/main_menu_builder.mm) and [History bridge](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/ui/cocoa/history_menu_bridge.mm) inform Back/Forward, direct Recently Closed/Recently Visited sections, and Show Full History. Harness shows up to 10 closed agents or Swarms and 15 recent destinations there. Navigation retains at most 64 recent identities, a 128-entry exact-pane Back/Forward trail, and a combined 24-close recovery list. Show Full History searches those recoverable destinations and explicitly says **This session**. History does not persist across app exit or collect terminal commands, prompts or output. These bounded session records are not a durable all-time browser history.

## Reductions and prototype follow-up

[The prototype review](harness-v2-prototype-review.md) covers all six variants in `harness-new-ui` at `19ced37`. Keep the terminal canvas and chosen Swarms; borrow optional contextual preview, explicit splits and exact return selectively. Leave out V3's primary/supporting hierarchy, persistent shelf, extra status/footer/context rows, model dashboard, and V4's default replacement of the active pane. Use the current easy Command prefix instead of copying Ctrl+B.

The fzf follow-up is one improvement to Cmd+P: match highlights, a bounded preview of already-retained context, and precise filters where names are ambiguous. It must perform no network work or terminal attachment while navigating results. Remappable keys remain authorized work. Editor/diff handoff and structured prompt/output navigation are parked research ideas; ordinary-shell creation is outside the current product direction. They are not all new features to build at once; reliability and measured interaction performance come first.

## The next small product milestone

1. **A terminal workspace people trust.** Finish the current native polish and verify typing, paste, selection, scrollback, resize, tab changes, input ownership and reconnect. No lost sessions, duplicate input or hidden layout changes. New swarms can be welcoming; active work stays visually quiet.
2. **One jump to any work.** Reach an agent or project on any connected machine, reuse the existing view, and return to the previous one. No network wait to navigate already-loaded work. Adding an agent remains an explicit action.
3. **A short path through decisions.** Jump to a waiting agent, inspect the real output or diff, give direction and return. Preserve each agent's native interaction and approval semantics. Add structured shortcuts only where its integration can support them accurately.

A modest CLI/API for the same operations can follow these stable primitives. It should compose with existing scripts and editors; the CLI already has daemon/agent mechanisms, so inventory and extend those before inventing a parallel orchestration system.

## How to judge whether this is working

These are proposed acceptance criteria, not measured results or evidence of product-market fit.

- Perform the ordinary loop entirely by keyboard: find an agent, switch, focus, zoom, inspect, answer and return. Navigation must not accidentally create a new view.
- Keep local input/focus/selection work within a display-frame budget on target hardware; measure input-to-display separately from framework CPU time. At 60 Hz a frame is about 16.7 ms, and at 120 Hz about 8.3 ms. Report p50/p95/p99 under output load, including cold and warm paths.
- Show an already-loaded Swarm without reconnecting its terminals or waiting for disk, discovery or a UI transition. Network round-trip time remains distinct from app overhead.
- Close and reopen the desktop client, interrupt a connection and resume without losing the chosen layout or sending input twice. A machine actually going offline must be represented honestly.
- Have experienced terminal users try real projects with several agents across multiple machines. Observe lost focus, hunts, unwanted interruptions and time spent configuring. Use these repeated observations to decide what to remove next; famous developers' preferences are useful starting hypotheses, not substitutes for this trial.

The product should leave a developer thinking: **all my work is here, it stays alive, and I can reach the right thing immediately.**
