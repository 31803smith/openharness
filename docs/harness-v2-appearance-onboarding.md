# Appearance and first use

Research and implementation notes, 2026-09-13. The product decisions below are Harness adaptations, not claims that the referenced tools endorse them.

## Palette selection

The useful common pattern is a named preset, a preview and an immediate result. Developers can personalize a workspace without first learning how its colors are configured.

| Primary source | Observed behavior | Harness decision |
| --- | --- | --- |
| [iTerm2 color preferences](https://iterm2.com/documentation-preferences-profiles-colors.html) | Presets and individual colors belong to profiles; color schemes can be imported and exported, with separate light/dark colors available. | Put the palette in Appearance and make selection reversible. Keep palette and typography separate. |
| [Ghostty themes](https://ghostty.org/docs/features/theme) | Named built-in themes, previews, custom theme files and light/dark pairs. | Offer a small, curated set first. One choice coordinates the app rather than asking users to configure each region. |
| [Apple Terminal profiles](https://support.apple.com/guide/terminal/profiles-change-terminal-windows-trml107/mac) | Profiles collect window colors, background, font and cursor preferences. | Show a miniature workspace so a preset explains its effect before selection. |
| [GNOME Terminal colors](https://help.gnome.org/gnome-terminal/app-colors.html) | Built-in, system and custom colors; changes apply and save automatically. ANSI palette colors and true-color output are distinct. | Apply immediately and persist. Keep explicit colors emitted by agents intact. |
| [Superlogical](https://www.superlogical.com/) | Public material describes a product plan and beta signup. It does not establish a shipped theme chooser. | Do not infer a theme feature or copy an unverified interaction. |

Implemented: six original dark presets in Settings → Appearance: **Graphite, Dusk, Midnight, Slate, Forest and Ember**. Graphite is the neutral default; Dusk preserves the earlier plum treatment. Preview cards show the tabs, search field, canvas and two agents. Mouse or keyboard selection updates Flutter tokens, retained terminal defaults and the native macOS titlebar. The preference loads before the first frame and rapid changes persist in order.

The existing ANSI color ramp and explicit agent-emitted colors remain intact. A palette change does not replace terminal controllers, alter fonts, send input, attach sessions or modify an agent's configuration. Light palettes, imports and a color editor are future options, not disabled controls in this first version.

Verification includes persistence/reload, keyboard operation, narrow layout, contrast, retained terminal identity and native titlebar/query identity. Primary text meets 7:1 on each terminal background; the tested secondary text meets 4.5:1 on the search, card and workspace surfaces. These checks cover Harness defaults, not arbitrary colors emitted by an agent.

## Native appearance during startup and sign-in

Saved colors now travel with the initial native `configure` request, before the app's explicit show request. Previously only an authenticated Swarm screen supplied those colors, so the native titlebar used Graphite during startup/sign-in even when Flutter had loaded a different palette. Clearing a workspace also used to reset the native colors because its teardown packet intentionally omits palette data. That omission now means retain the current palette.

New swarm and Search remain disabled until the workspace enables them. Repeated native configuration preserves the current palette and one titlebar accessory. The existing tab controls, search editor, query and composition survive later palette updates.

The window setup future now awaits configure, show and focus requests directly. The installed window library's callback is synchronous and previously allowed that future to report completion before its async native work finished. Delayed-reply checks reproduced the issue; error responses now reach the awaited setup call. These checks exercise actual Dart request ordering and a hidden AppKit window. Live first-frame presentation and macOS foreground activation remain unmeasured.

## Reaching the workspace while account details load

The startup audit found that both sign-in and refresh waited for `/api/auth/me` before requesting machines. That profile supplies display identity; CLI authentication and daemon readiness are already confirmed separately. Account details now load alongside machine discovery. The workspace can show available agents and their terminal capability state while the profile remains pending, and the account updates when its response arrives.

Repeated refreshes share a pending profile request, and a failed profile can be retried without holding up machine recovery. Session ownership checks discard late responses after sign-out, replacement sign-in or disposal. They also cover downstream agent and capability loading, so an old request cannot reattach an agent after its workspace has gone.

Fourteen isolated profile/startup lifecycle checks and the existing first-run/machine suites pass: 118 focused tests in total. These establish request independence, notification and recovery behavior with synthetic data. They do not measure real sign-in duration, network latency or user activation.

## Onboarding evidence and direction

| Primary source | Observed behavior | Harness adaptation |
| --- | --- | --- |
| [Zed getting started](https://zed.dev/docs/getting-started) | An empty editor offers useful starting actions such as opening a folder or cloning a repository; the welcome screen gives way to work. | Make the empty workspace actionable and let it disappear as soon as an agent is visible. |
| [VS Code getting started](https://code.visualstudio.com/docs/getstarted/overview) and [walkthroughs](https://code.visualstudio.com/docs/editing/getting-started/tips-and-tricks) | A short route to a first project, with optional walkthroughs and contextual learning. | Lead with the first agent. Teach grouping and shortcuts where the user can immediately use them. |
| [Warp installation and setup](https://docs.warp.dev/getting-started/quickstart/installation-and-setup) | Current setup allows sign-in to be optional and can import an existing configuration. | Reuse an existing environment wherever possible. Evaluate Harness's actual authentication requirements before changing its sign-in boundary. |

The initial source audit found that an unprepared computer reached a three-stage dependency wizard before sign-in, while an authenticated empty workspace led with “Start a swarm,” generic search, New agent, machines and projects. This exposed several unfamiliar choices before the first useful session. Browser sign-in remains a real requirement of the current CLI-backed authentication flow.

Implemented first-use changes:

- Setup combines review and method choice in one screen. It shows only missing tools and a direct **Install N tools** action. Manual commands remain available through a secondary **Manual setup** action. Read-only startup checks, explicit installation consent, verification, terminal handoff and failure recovery are preserved. The three-stage rail and intermediate Continue action are gone.
- Sign-in leads with the value and a static example of two familiar coding agents in one swarm. The example cannot run or submit a task. Browser progress, cancellation, errors and the privacy footer remain in the same card; the primary action is visible at the minimum window size.
- An empty first workspace offers up to three existing, available agents directly. A ready local computer with no agents gets a simple folder → coding agent → work explanation instead of empty Machines and Projects columns. The full machine list stays visible for multiple machines, linking issues, offline hosts and ongoing discovery. Existing work removes the first-workspace guidance. No persistent tour state is added.
- New agent places **Project folder** before **Coding agent** and names the local target **This computer**. It prefers an installed coding agent when that fact is known; an asynchronous probe may improve the default but cannot replace an explicit user choice or a submitted launch. Existing profile, installation and permission behavior is preserved.
- New agent opens immediately against a dimmed backdrop. Failed engine checks get a short explanation; troubleshooting remains in Advanced. Machine, folder and coding-agent pickers are reachable with Tab; selection works with Enter/Space and arrows, and Escape closes an open picker. Folder selection restores focus when it returns. Hidden Advanced controls cannot receive Tab focus, while their profile discovery continues. Isolated keyboard tests complete the first-agent path on macOS, Windows and Linux variants without sending a task to an agent.
- Both actual search fields remain available and continue showing results at the field being edited. The first-use agent rows use the existing, revalidated navigation action. Returning users retain the regular New swarm screen.

First-use validation uses isolated state and stubbed machines, agent creation, folder selection and provisioning. It checks direct existing-agent navigation, a new agent becoming visible with no automatic task input, an installed default, explicit-choice preservation after a late probe, and one deliberate install action reaching sign-in. The first visual pass also led to keeping the setup action beside its content and preserving machine-linking rows. Rendered fixtures cover sign-in at 880×560, setup and both empty/populated discovery states at 1280×800.

These are implementation and fixture results, not a measured conversion rate. A fresh-install dependency or provider sign-in may take longer than a few seconds. Observe new users' time to first useful agent, uncertainty at the folder/agent choice, and ability to add a second agent before claiming the onboarding succeeds for everyone.

## First-agent recovery pass

Rechecked the primary-source guidance on 2026-09-13: [Zed's welcome page](https://zed.dev/docs/getting-started) disappears after a project opens; [VS Code's first-agent quickstart](https://code.visualstudio.com/docs/agents/quickstart) proceeds from a folder through a real task and verification. The useful adaptation here is to make the existing first-agent path dependable and explain recovery where it is needed. A compulsory tour or sample task is not needed to exercise it.

The audit reproduced a pending-launch bug: Escape dismissed New agent despite its disabled Cancel button, leaving the request running without its outcome visible. The form now keeps the pending request visible with a readable “Creating agent…” state. It permits dismissal again when the request completes. A failed request retains the machine, folder and coding agent; selecting another folder or agent clears the obsolete error. Completion still opens the requested agent, with no automatic task input.

Known missing/invalid-folder failures now name the target machine and ask the user to choose another folder. Missing tmux gets its required recovery instead of a wire code. Other server details remain visible. A request timeout is described as an unconfirmed outcome and directs the user to Search before creating another agent; it is never automatically retried. Protocol-level creation idempotency and late-reply reconciliation remain separate future reliability work.

Validation: the new pending-launch regression failed before the fix and passed afterward. Forty-six focused onboarding/profile/split/async checks passed, plus isolated 880×560 renders of pending, invalid-folder and timeout states. These checks use synthetic state and requests; they do not install software, launch a provider, or send a task to a real agent.

The next pass removes one intermediate click for a known empty local workspace. **Choose folder…** opens the native directory chooser directly. The ordinary form then shows that folder and prefers an installed coding agent. Availability probing runs while the user chooses, and the form reuses the same probe. Cmd-N and the returning-user New agent action keep their existing behavior. This is our adaptation of the folder-first flow, not a measured claim about user activation.

The chooser is opened only by deliberate activation. Duplicate activation, cancellation, changed target identity and offline/unlinked state are checked before showing its result. Sixty-five focused onboarding/profile/engine/split/search checks pass, including completion with no automatic agent input, keyboard-only ordinary creation, late availability, cancellation and stale-target cases. Isolated 880×560 welcome/form renders were reviewed. The native OS chooser itself was stubbed; live first-install and provider sign-in remain separate validation.

## Arriving at New swarm

A later full-screen probe found that first launch focused the shell, while arriving from a populated swarm automatically covered the welcome choices with suggestions. The inline field now receives focus on arrival with its popup closed. The user can type immediately, click for suggestions, or reveal them with the configured picker keys. Tab reaches the primary folder action in the first-workspace path. The first opening key reveals the choices without activating an unseen agent or swarm. Escape closes suggestions while preserving text and the caret; typing again reopens them in place.

The [W3C combobox pattern](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/) documents a collapsed default and several possible expansion triggers, including Down Arrow, focus and typing. Our choice is to keep the welcome useful while making search immediately available. This is a Harness interaction decision, not a claim of complete ARIA or native accessibility conformance. Keymap overrides, composition ownership, explicit command mode and both search locations retain their existing behavior.

The full Flutter screen was rendered at 880×560 for fresh welcome, prefilled creation, New swarm after work and inline results. Regression checks cover first arrival, close-last-swarm, keyboard opening, retained query/selection/composition, native-search cancellation and the first folder action. The render uses Flutter's fallback titlebar; native field behavior is checked separately in a hidden AppKit window. Live first-install observation and native input-to-display timing remain unmeasured.
