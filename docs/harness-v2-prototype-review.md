# What V2 should borrow from the Harness prototypes

Reviewed 2026-09-13. The source is the clean local checkout of [autonomous-ai/harness-new-ui](https://github.com/autonomous-ai/harness-new-ui) at `19ced37`, with its matching origin. The public GitHub page could not be fetched by the web tool; the source and running `http://127.0.0.1:5173/` were inspected directly.

**Keep the scope small: durable terminals, immediate navigation, and a dependable way to handle an interruption and return.** The prototypes provide useful interaction experiments. They do not establish native terminal correctness, measured performance, or what exceptional developers universally prefer.

## What was reviewed

All six live variants were inspected at the existing desktop viewport: Harness, Harness + Grid, Swarms, Swarms v3, Swarms v4, and Swarms + Models. The walkthrough exercised V4 search and its contextual preview, Needs you and Return, V3 Find and a temporary Daily Report preview, and the Models inventory. It did not submit mock instructions, send handoffs, create agents, or alter pane membership. The original V4 comparison selection was restored.

Source review covered `App.tsx`, `SwarmsV4Workspace.tsx`, `data/swarmsV4.ts`, `HARNESS.md`, the V3/V4 notes, the earlier Swarms review, and product-direction history. The V4 notes clearly label their developer walkthroughs as **AI simulations**, not visits or endorsements from the people used as inspiration. Earlier proposed contracts remain historical evidence; the user's current V2 decisions govern implementation.

| Prototype | Useful lesson | Decision for V2 |
| --- | --- | --- |
| Harness | Related work can span machines and branches. Its permanent tree compresses the terminal canvas, and repeated context truncates titles. | Keep searchable project/branch/machine context and machine/project starters. Keep the permanent tree absent. |
| Harness + Grid | Execution machine and inference provider are different concepts. Adding both to every pane makes identification harder. | Preserve accurate machine identity. Leave model routing and compute administration outside this milestone. |
| Swarms | A chosen working set and ordinary tabs are easy to understand; mixed machines need no extra hierarchy. | Keep the native tab/canvas foundation, explicit membership, and close-view semantics. Preserve the newer Chrome geometry rather than copying the browser mockup's strip. |
| Swarms v3 | A large readable terminal helps; temporary inspection can preserve the originating workspace. Primary/supporting/shelf roles introduce extra arrangement decisions. | Keep zoom and exact return. Do not adopt the role hierarchy, two-supporting-pane limit, promotion controls, or persistent shelf. |
| Swarms v4 | Stable sessions, explicit right/down splits, contextual search preview, draft/caret recovery, and an attention round trip address daily friction. | Borrow these behaviors selectively. Do not inherit its permanent session strip, footer, second metadata row, or default replacement of the focused pane. |
| Swarms + Models | Model/account details can be inspected on demand, but per-pane model controls and a top-level library compete with the work. | Keep the dashboard absent. Existing usage and hardware capabilities stay secondary; they do not justify a new daily navigation surface. |

## The three promises, with concrete changes

### 1. Work stays where you left it

The durable idea shared with tmux is session identity independent of the view. V2 already shares controllers across Swarms and closes views without ending agents. Finish reconnect preservation, scroll/search/draft continuity and close/reopen behavior before widening the feature set.

Borrow V4's **explicit split right/down** interaction as the next layout improvement. A split should add beside the chosen pane, with user-controlled resizing and no eviction or automatic rearrangement when an agent's state changes. This requires a deliberate extension of V2's layout model; it is not implemented merely because the prototype can draw a split tree. Retain existing arrangements and provide a compatible migration before changing their representation.

Do not copy V4's default "open here" behavior into Cmd+P: that replaces the current pane when a session is not visible. In V2, Return should continue to focus the existing destination; adding a view remains explicitly labeled. Stable behavior matters more than reducing one click by surprising the user.

### 2. Reach the right work immediately

The strongest small addition is an **optional preview inside the existing Cmd+P picker**. V4's `workshop` query demonstrated why: a result named `zsh` becomes recognizable when its folder, branch, and recent output are visible. No second global finder or permanent sidebar is needed.

Carry the following into one bounded follow-up:

- Highlight matched text, including the machine/project/branch field responsible for a match; retain deterministic ranking and the highlighted identity during discovery updates.
- Allow a keyboard-controlled preview using already-retained output and metadata only. Bound the excerpt, show unavailable context honestly, and never attach, reconnect, acquire control, or scan every transcript as the selection moves.
- Add precise machine/project/branch filters when they remove ambiguity. These are navigation filters, not a new organizational hierarchy.

This follows [fzf's incremental narrowing and preview design](https://github.com/junegunn/fzf). `git ls-files | fzf` illustrates its small composable contract: receive candidates, narrow them, return the chosen value. Harness should reuse that interaction model, not run shell preview commands on every search keystroke. V4's own scorer is a small custom fuzzy matcher, not an embedded fzf runtime.

The prototype's `>` command mode could eventually expose the existing app command catalog in the same picker. Defer a second registry or a large command system; first verify that people cannot already find the relevant command through native menus and the shortcut sheet.

### 3. Handle a decision and return to the same place

Borrow the V3/V4 **temporary inspection and explicit Return** behavior. V2 already has Needs input and previous-destination navigation; strengthen the same loop instead of adding a new inbox, dashboard, or mandatory arrival screen. The return target includes the Swarm, pane, zoom, reading position, unsent draft, caret and actual focus.

Keep a question distinct from a reported result and an unverified completion. Status comes from real events, with freshness and unavailable-state handling. The preview's generic reply box is not a safe substitute for an agent's native approval semantics. Route the developer to the actual agent interaction unless a supported adapter can identify and answer the exact request.

V4's editable handoff is an interesting later idea. A production version needs an explicit recipient, actual checkout/change evidence, reviewable text and delivery confirmation. Start with ordinary copy/paste and an editor/diff handoff; do not build a generic orchestrator or infer that storing text means another agent received it.

## What stays out, or becomes smaller

- **No mandatory primary/supporting hierarchy, session shelf, extra footer, duplicate project tree or permanent context row.** Use the terminal area for output; disclose context in the compact header, picker, tooltip and menu.
- **No copied Ctrl+B prefix by default.** A real nested tmux session already uses it. Configurable keymaps and deliberate passthrough need runtime tests; the browser's prefix simulation cannot prove compatibility.
- **No model/compute dashboard, marketplace, autonomous manager, full IDE/Git client or generic handoff system in this milestone.** Existing agents, shells and editors already perform much of this work.
- **No backdrop blur, artificial transition delay, replaying output animation or repeated healthy-state spinner.** A quiet working surface and measured response are more valuable than constant signs of activity.
- **Wallpaper remains in empty New swarm only.** Appearance controls belong in View/context menus. Active Swarms keep one flat color continuous with the selected tab.

## Remaining foundations the prototypes cannot prove

An ordinary local/remote shell must be easy to open in the correct directory. Remappable commands must coexist with Vim, zsh, tmux, IME and accessibility keys. [Ghostty's shell integration](https://ghostty.org/docs/features/shell-integration) offers useful examples of directory inheritance, prompt navigation and output selection; these should use real terminal signals rather than guessed screen text. CLI/API operations should use the same stable session identities as the UI.

Those are gaps to verify and prioritize, not a checklist to implement all at once. Current order: finish the reliability/menu/header/project work; measure real input and navigation under output load; then add the bounded Cmd+P preview/highlight improvement. Explicit splits and keymap/shell compatibility follow with their own focused validation. The [working queue](harness-v2-developer-tools-research.md) remains the single status list.

Success means fewer wrong destinations, no surprise layout changes, no lost editing or reading context, and less effort to resume work. Real daily use with local and remote agents must establish that result; attractive sample screens and simulated reviewers cannot.
