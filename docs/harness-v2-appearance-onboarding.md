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
- Both actual search fields remain available and continue showing results at the field being edited. The first-use agent rows use the existing, revalidated navigation action. Returning users retain the regular New swarm screen.

First-use validation uses isolated state and stubbed machines, agent creation, folder selection and provisioning. It checks direct existing-agent navigation, a new agent becoming visible with no automatic task input, an installed default, explicit-choice preservation after a late probe, and one deliberate install action reaching sign-in. The first visual pass also led to keeping the setup action beside its content and preserving machine-linking rows. Rendered fixtures cover sign-in at 880×560, setup and both empty/populated discovery states at 1280×800.

These are implementation and fixture results, not a measured conversion rate. A fresh-install dependency or provider sign-in may take longer than a few seconds. Observe new users' time to first useful agent, uncertainty at the folder/agent choice, and ability to add a second agent before claiming the onboarding succeeds for everyone.
