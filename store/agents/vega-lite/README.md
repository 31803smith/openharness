# Vega-Lite, as a Harness agent

Ask a data question and get an interactive Vega-Lite chart: local data, typed encodings, tooltips,
brushing and linked views, with the work visible in the pane from the first save. The chart is checked
against the Vega-Lite schema, compiler and renderer and against the requirements written into the
brief, and a fresh reviewer who never saw the work grades a picture of it before anything is called
ready.

## Install

```bash
harness dsh install autonomous/vega-lite      # from the Harness Store
harness dsh install "$PWD" --link             # this folder, while working on it
```

Setup installs Vega-Lite 6.4.3, Vega 6.4.0, Vega-Embed 7.2.0 and the snapshot renderer into the
package from `package-lock.json`, with SHA-512 integrity for every dependency. Node comes from the
Harness runtime; nothing is installed globally and nothing needs a compiler, a browser or Python.
`toolchain/doctor.sh` says in one line what is missing. After setup, everything runs offline: the pane,
the checks, the snapshots and the exports.

## What the pane shows

The question first, then the data as a browsable table before any chart exists, then the chart the
moment its first save lands, then the checks. Chart, Data, Source and Checks are tabs; the chart keeps
hover values, its authored brushes, legend selections and filters, and a temporary Explore mode for
simple charts. The chart follows the pane's light or dark theme. An invalid save never blanks the
pane: the last working chart stays, dimmed, with the error above it. Exports are one click: SVG, PNG,
the Vega-Lite source, or a self-contained HTML page that works offline and follows the reader's own
light or dark preference.

## How its evaluation works

`.harness/verdict.json` records three gates, and `toolchain/check` exits 0 only when all three pass:

- **tool** — the chart is valid against the pinned Vega-Lite 6.4.3 schema, compiles without warnings,
  and really renders: Vega draws it and the scene has data marks.
- **checks** — the measurable requirements in `brief.json` (input rows, fields, mark types, interaction
  parameter names, panel count and exact JSON-pointer assertions such as a zero baseline). While
  drafting these read as to-dos; from the polish phase on, an unmet requirement is an error.
- **review** — `vl snapshot` renders the chart to a PNG offline, and a fresh-context reviewer (a
  subagent, or `codex exec` / `claude -p` on engines without them) grades it against
  `skills/vega-lite/review-rubric.md`: does it answer the question, is the encoding honest, are units
  and labels there, is it legible, is the composition and colour right. The grade is tied to a hash of
  the rendered chart, so any later edit makes it stale and `ready` goes back to false.

None of this proves the data is true, or that every gesture works. `ready` means those three gates
passed for that exact chart, and the pane says so in those words.

## Credit and stewardship

This harness wraps [Vega-Lite](https://vega.github.io/vega-lite/) and
[Vega](https://vega.github.io/vega/), by the **Vega project / University of Washington Interactive
Data Lab**, used under the BSD 3-Clause Licence. The grammar, the compiler, the renderer and the
gallery patterns the skill teaches are their work; the tile is credited to them.

The wrapper — `AGENTS.md`, the skill, the toolchain and the viewer — was written on the project's
behalf and is not maintained by the Vega project. Its maintainers are welcome to take ownership of
this package, change it, or ask for it to be withdrawn. Every vendored component and its licence is
listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md); the harness itself is MIT
([LICENSE](LICENSE)).
