---
name: craft-the-viewer
description: Build the harness's viewer pane — the work in progress shown stage by stage as the agent writes, an interaction bar per artifact type, delightful to look at and touch — reusing or upgrading a shared viewer before building a new one. Use at the viewer stage and whenever a proof shows the pane lagging, blank, broken or dull.
---

# Craft the viewer

The pane is the product. A person watches it while the agent works, and keeps playing with it after.
Two failures to avoid above all: a pane that shows nothing until the end, and a pane that shows the end
result as a flat picture.

```bash
"$BUILDER" stage viewer active --note "<reuse|upgrade|new>: <why>"
```

## Choose: reuse, upgrade, or new

Look at the shared viewers in `$BUILDER_REFERENCE/store/viewers/` first (read each README):

| Viewer | Shows |
|---|---|
| `autonomous/cad-viewer` | STEP, GLB, STL, 3MF, DXF, URDF: orbit, section, measure |
| `autonomous/model-viewer` | glTF as a Blender-style viewport: outliner, shading, measure |
| `autonomous/doc-viewer` | PDF: thumbnails, outline, find, zoom, spreads |
| `autonomous/video-viewer` | renders: every version, chapters, frame-accurate scrubbing |
| `autonomous/game-viewer` | playable web games, build progress, versions, last good build kept |
| `autonomous/mujoco-viewer` | live physics, actuators on sliders, replay |
| `autonomous/film-viewer` | storyboards, a film player, notes on the timeline |
| `autonomous/web-viewer` | HTML/CSS/JS with live reload |

- **Reuse** (`"viewer": { "use": "autonomous/<viewer>" }`) when a shared viewer already shows this
  artifact at the bar below *and* can show this domain's stages.
- **Upgrade** when a shared viewer is close: build the upgrade as your own viewer in this package,
  starting from a copy of that viewer (keep its licence notices), and note in `.builder/decisions.md`
  what should flow back to the shared one.
- **New** when the domain's artifact deserves its own experience: a score you can hear, a map you can
  pan, a chart whose points you can hover. Most harnesses worth building land here.

## The interaction bar, by artifact type

Meet every item for your type. Then add the one thing that makes this domain delightful.

| Artifact | The bar |
|---|---|
| Chart / plot | hover tooltips with values, zoom and pan on continuous axes, legend toggles, crisp at any size, the data table one click away |
| Document / page | pages as thumbnails, zoom, fit width, find, current page follows the edit |
| Score / notation | pages, play and pause with the playing note highlighted, tempo, jump to a bar |
| Map | pan and zoom, layers toggle, click a feature for its attributes, scale bar, basemap switch |
| 3D model | orbit, pan, zoom, fit, select a part, measure, wireframe or section |
| Diagram / graph | pan and zoom, select a node to see its details, fit to screen |
| Image / render | fit and 1:1, zoom, compare with the previous version |
| Audio | waveform or piano roll, play, scrub, loop a section |
| Animation / video | play, scrub frame-accurately, loop, the list of renders |
| Simulation | play, pause, step, reset, the parameters on controls |
| Interactive app / game | runs in the pane, keyboard and mouse, restart |

## Progressive: the stages from the brief

The brief lists the domain's stages. The viewer shows each one the moment its first file exists:

- **Before the first save** the pane is not blank: it shows the harness's name, what it is about to
  make, and the stages as an empty track.
- **Each stage has a look.** The data table before the chart; a bare staff before the notes; the base
  map before the analysis layers. Transition smoothly between them (fade, morph) rather than flashing.
- **Errors never blank the pane.** Keep showing the last good render, dim it, and overlay the error with
  the file and line it points at. The game viewer's "uninterrupted last working game" is the model.
- **Follow the work.** Scroll to or highlight what just changed: the slide just edited, the bar just
  added, the layer just styled.
- **The verdict's phases** drive a stage track in the pane that matches the pane header.

## The protocol (every viewer)

- A long-running server started by `viewer.command` with `HARNESS_VIEWER_PORT`, `HARNESS_WORKSPACE`,
  `HARNESS_DSH_DIR`; listen on `127.0.0.1:$HARNESS_VIEWER_PORT` only.
- Serve the page and files from the workspace and nothing outside it (resolve, then check the prefix;
  bad percent-encoding is a 400, not a crash).
- Watch the workspace recursively, ignore `.harness/`, `.git/`, `node_modules/`, `.claude/`,
  `.agents/` and output folders you write yourself, debounce (about 150 ms), and push a change event
  (server-sent events are simplest).
- **Re-run the check on every change and write the verdict**, so the pane header moves without the
  agent running anything. `$BUILDER_REFERENCE/store/agents/marp/toolchain/viewer.mjs` does all of this
  in about 130 lines of Node with no dependencies: start from it.
- No network at runtime: vendor every script and font into the package (pinned in the lockfile), and set
  a Content-Security-Policy that keeps fetches on the page's own origin.
- Dark and light: follow `prefers-color-scheme`, and design both on purpose.
- `?snapshot=1` renders deterministically (no animation, final state of the current files) so
  `"$BUILDER" snapshot` and proofs can take clean pictures.

## Delight checklist

- The first thing on screen is the artifact, large; chrome is quiet and minimal.
- The artifact follows the theme. A renderer that paints its own white background (a chart, a page,
  a canvas) gets the theme's colours in dark mode, or sits on a deliberate paper surface the design
  calls for; never a stray white box inside a dark pane.
- Type and spacing are deliberate; nothing overflows at 900 px wide or at 2560 px.
- Motion is smooth and short (150–300 ms), and there is none under `prefers-reduced-motion`.
- Every control has a visible hover state and a keyboard shortcut for the important ones.
- Nothing says "TODO", "placeholder", "Lorem", or shows a raw stack trace.

## Try it like a person

```bash
"$BUILDER" proof open viewer-check      # a workspace with the viewer running, shown live in the Studio
"$BUILDER" snapshot viewer-check        # a picture of what the pane shows right now
```

Write the domain's files by hand into that workspace in stages and watch each stage appear. Look at
every snapshot yourself (read the PNG). Then check both themes and a narrow width.

## Done

Reuse, upgrade or new decided and written down; the bar met for the artifact type; every stage visible
as it lands; errors keep the last good render; snapshots look good in dark and light.

```bash
"$BUILDER" stage viewer done --note "<viewer>: <the delightful part>"
```
