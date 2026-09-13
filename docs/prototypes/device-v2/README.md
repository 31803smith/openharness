# Harness V2 — launch page

A local launch page for the Harness V2 app and USB-connected device, with an animated workspace inside a desk photograph, four independent feature demos, and a guided keynote. Built with React 19, TypeScript, Vinext/Vite, Tailwind CSS, and the scaffolded Shadcn/Base UI primitives. No backend, microphone permission, or physical device is required.

## Run locally

Requires Node 22.13 or newer.

```sh
cd docs/prototypes/device-v2
npm install
npm run dev
```

Open **http://localhost:5177**. This prototype is local only; do not deploy it to Sites or another hosting service.

## Explore

The page walks through five primary folds: **desk setup → Focus → Voice → Needs you → Updates**. Each feature keeps its copy, controls, and demonstration together. Desktop layouts size the demos to the viewport; narrow screens stack them naturally. There are no feature tabs. Needs you comes before Updates to distinguish a decision that unblocks work from a completed result that can wait.

- **A working desk:** just a 27-inch monitor, the small Harness device, and a straight USB cable disappearing into the monitor stand. The V2 app has six terminal panes across the full monitor width, with machine names in each pane and no left sidebar. One 40.5-second timeline keeps monitor focus and the device's agent, engine icon, and status in sync. It opens on The API working, shows its two-line result when it finishes, then moves through Storefront, Test suite, Payments (Needs you), Deployment (finished), and Observability. Active terminals advance at independent rates; completed output stops. Typography is scaled as approximately 13px text on a 1920px desktop viewed inside the photo. The feature demos below use larger, readable text. Pause freezes both displays, and resuming continues from the same point. The animation also pauses offscreen or when the tab is hidden; reduced-motion preferences show a still workspace.
- **Watch the reveal:** seven guided scenes, automatic playback, pause, scene selection, previous/next, and replay. Touching the device pauses the story so you can explore.
- **Focus:** swipe the round display horizontally, scroll sideways on a trackpad while hovering over it, or use its edge arrows to move through agents. Horizontal trackpad momentum advances only one agent per gesture. Tap the Swarm name at the top of the device to change Swarms. The name highlights when pressed. The desktop and device share focus.
- **Readable workspace:** the desktop shows two panes at a time, keeping the focused agent visible. Other agents remain reachable by swiping. Phones show one focused pane. The active pane has a clear border, and the app footer names the agent controlled by Harness.
- **See what finished:** swipe to The API or Release notes to see the completed state. A small engine icon sits beside the name; a two-line result replaces the status. The result stays until new work is sent to that agent.
- **Slide to scroll:** drag vertically on the device for continuous scrolling, or use a mouse wheel or two fingers on a trackpad while hovering over the screen. The focused desktop terminal follows while the device keeps its status or completion summary visible. “Try scrolling” gives a smooth demonstration. You can also scroll a desktop terminal or use its up/down controls. Each terminal remembers its reading position; scroll bounds follow the rendered content and viewport size.
- **Say the word:** double tap the device or use the demo button. The listening, transcription, and sent states are simulated. The destination stays locked even if desktop focus changes.
- **Needs you:** a raised hand in warm gold means an agent needs your input to continue. The dedicated section starts with Release notes in focus. Tap the hand to jump straight to Payments, answer its sample question, and return to the original Swarm, agent, and reading position. Later leaves the question open.
- **Updates:** a clear green checkmark marks a finished result. The API has finished while Storefront stays in focus. Tap the checkmark to read the two-line result on the device, then return to your work. No answer or approval is needed. New work clears an obsolete completion notice.
- **Keyboard:** tab to the round display, use left/right arrows to change agents, up/down to scroll, V for voice, and Escape to leave a screen. Dialogs support Escape and focus management. Motion respects the system’s reduced-motion preference.
- **Expand the app:** explore the simulated V2 desktop at a larger size.

Each feature and the keynote have separate demo state. Replay resets only that section. Agents, terminal output, account decisions, and voice messages are fictional and never sent to an agent or external account. Hardware is shown with the proposed interface; this is not a firmware implementation. USB is the only connection represented.

The small display prioritizes the agent name with a small engine icon, one status, and a Swarm switcher. Icons are optically sized and aligned against the name's letter height, with consistent spacing across engines. Finished tasks replace the status with a six-to-ten-word result on two lines. Action requests use a warm-gold raised hand; completed-update indicators use a green checkmark. The same icons appear in the hero and app previews. Different silhouettes distinguish them without relying on color. Tapping either count goes straight to its agent. The result itself stays free of extra icons. Written model names, machines, timing, and terminal details stay on the desktop.

## Validation

```sh
npm test
npm run typecheck
npm run lint
npm run build
```

Tests cover the two-pane viewport, Swarm ordering and focus memory, locked voice routing, cancelled capture, direct request navigation, decision/deferral, passive completion notices, exact reading-position restoration, measured scroll bounds, continuous drag, horizontal trackpad momentum, independent feature scenarios, and the hero's synchronized focus, completion, output, and loop boundaries.

## Source map

- `components/harness-experience.tsx`: the product page, desk hero, and scroll reveals.
- `components/hero-workspace.tsx`: synchronized monitor and device displays, visibility-aware clock, and playback control.
- `components/device-hardware.tsx`: interactive UI over the photographed device.
- `components/desktop-preview.tsx`: linked Swarm and terminal simulation.
- `components/feature-walkthrough.tsx`: four separate interactive feature sections and expanded desktop.
- `components/keynote.tsx`: the guided reveal and playback controls.
- `lib/demo-state.ts`: pure interaction state and sample agents.
- `lib/feature-demos.ts`: isolated starting scenarios for Focus, Voice, Needs you, and Updates.
- `lib/hero-workspace.ts`: fictional agent output, machine assignments, and the shared hero timeline.
- `app/globals.css`: visual system, responsive layouts, and motion.
- `app/feature-walkthrough.css`: viewport-aware hero and feature layouts, compact cards, and their responsive rules.
- `app/hero-workspace.css`: alignment of both live displays to the photograph, realistic typography, and transitions.

## Product photography and provenance

Original hardware photography comes from [Autonomous’s Harness device page](https://www.autonomous.ai/harness-device).

- `public/images/harness-desk-connected.webp`: the approved 1672 × 941 hero, created with the built-in `image_gen` tool. It shows a 27-inch monitor, the device's small 52.5 mm body, and a straight black cable disappearing into the stand, with no keyboard or visible connector. Hardware scale references the [manufacturer's dimension drawing](https://cdn.autonomous.ai/production/ecm/260722/spec.webp). The [approved review PNG](assets/reviews/hero-monitor-device-v2.png) was encoded as WebP without cropping, resizing, or compositing. Exact prompts: [monitor and device composition](assets/reviews/hero-monitor-device-v1.prompt.txt) and [straight cable refinement](assets/reviews/hero-monitor-device-v2.prompt.txt). Prior photographs, including `harness-desk-27in.webp` with split keyboards, remain available for reference.
- `public/images/harness-front.png`: imagegen edit of the [front product photograph](https://cdn.autonomous.ai/production/ecm/260731/2.webp), restaged with a blank screen and a transparent background for the layered product stage. The live circular interface is HTML, not baked into the image.
- `public/images/harness-lifestyle-v2.png`: imagegen edit of the [desk photograph](https://cdn.autonomous.ai/production/ecm/260723/b3-2.jpg), replacing the original screen with the proposed V2 direction. Hardware, cable, keyboard, and desk remain pictured.
- Engine icons reuse the repository’s `desktop/assets/engine-icons` files. The Claude mark follows `desktop/lib/widgets/engine_identity.dart`.

The front image uses a normalized display center at `50.36% / 42.38%` with a circular overlay diameter of `54.39%`. Keep these coordinates aligned when replacing the photograph.

The hero photograph remains intact. A live HTML workspace covers its monitor at `left: 22.58%; top: 6.16%; width: 54.86%; height: 59.3%`. A circular HTML display covers only the device's black glass at `left: 47.7%; top: 82.48%; width: 4.55%; aspect-ratio: 1`. Both coordinates are relative to the same image container, so the screens remain attached when the hero is letterboxed or resized. The bezel, cradle, cable, and stand stay photographic. Both screens consume one frame from `getHeroFrame`; there are no independent focus or status timers. These displays are decorative simulations described by the photograph's alt text; terminal updates do not create screen-reader announcements.
