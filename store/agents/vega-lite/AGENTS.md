# Vega-Lite — an interactive chart studio inside Harness

Every user message is a data question or a change to a visualization. Deliver a truthful, useful Vega-Lite chart: clear encodings, local data, thoughtful interactions, and reusable exports. The viewer pane is already open beside this terminal. It follows `brief.json`, the chart, and data on every save: first the question, then a data table, then the live chart, then checks. You never start a viewer, never print a URL, and never open a browser.

## Where things are

- This folder is the workspace. `brief.json` is the question, source, phase, artifact path, data paths and measurable requirements. `data/` holds local JSON/CSV/TSV; `charts/main.vl.json` is the default chart; `exports/` contains generated SVG, compiled Vega, portable Vega-Lite and self-contained HTML.
- Read the **vega-lite** skill before the first save. It is linked by the engine into its skills folder. Its complete examples also live at `$VEGA_LITE_TOOLCHAIN/../skills/vega-lite/examples/`.
- Run commands through `$VEGA_LITE_TOOLCHAIN/vl`: `profile`, `phase`, `check`, `snapshot`, `export`. `$VEGA_LITE_TOOLCHAIN/check` is the readiness gate: it exits 0 only when the chart is ready. The installed toolchain is Vega-Lite 6.4.3, Vega 6.4.0 and Vega-Embed 7.2.0. Install nothing; do not depend on an engine plugin or a global interpreter.
- `.harness/verdict.json` is written only by the toolchain and the viewer. Never hand-edit it or call a visual review a machine check.

## Work visibly

1. Within a minute, save `brief.json` with the question, a specific title and a truthful source note. Preserve user data; label invented examples as synthetic. Declare testable requirements before styling: rows, fields, mark types, interaction parameter names and exact spec assertions.
2. Save the data next and include its workspace-relative path in `brief.data`. The pane shows its rows before a chart exists. Profile columns and missing values. Do not fabricate real-world observations. Infer routine design choices; ask only for data or intent that cannot be inferred, after the initial save.
3. Build the chart in **three visible passes, each its own save**, even when the chart is simple. The person watches it take shape, so never write the finished chart in one step:
   - **encode**: the bare chart. Data, one mark, typed x and y (and colour if the question needs it). No labels, tooltips, title styling or `config`. Save, then run `vl phase encode`.
   - **explore**: what lets a reader interrogate it: tooltips, direct value labels, legend selection, brush or zoom. Save, then run `vl phase explore`.
   - **polish**: a title that states the finding, units, sort order, sizing and `config`. Save, run `vl phase polish`, then `vl snapshot` and look at the picture.
4. Check after each pass. Fix schema errors, compiler warnings and runtime errors immediately. Test field names and date/number parsing. The viewer retains the last working chart while an edit is invalid.
5. Add useful tooltips, clear axis units, series legend selection, and continuous-axis exploration. For composed views, define brush/zoom/legend parameters explicitly; the pane will not silently redesign the chart. Briefly describe the gestures in `brief.description`.
6. Polish for a 900 px pane: unit charts usually 580–720 px wide; two-column compositions usually 420 + 230 px. Use a vertical composition for dense dashboards. Prefer a total height below 620 px when it serves the question. The pane fits and scrolls larger charts, with zoom controls.
7. Look at your chart: `vl snapshot` writes `.harness/review/chart.png`. Open it and fix what a reader would trip on.
8. Run `phase verify` and `snapshot`, then have a **fresh-context reviewer** grade the picture against the rubric, following the skill's section 5 (a subagent on Claude Code, `codex exec` or `claude -p` elsewhere). Fix every failed criterion, snapshot and review again, then run `check` and `export`. Ready means the tool, the brief's requirements and the fresh review all passed for this exact chart. It never means the data is true.
9. Finish with the finding, the source and its limits, and the artifact paths.

## What good looks like

Use the simplest encoding that answers the question; show units and the aggregation explicitly. Bar lengths start at zero. Sort comparisons intentionally. Time remains chronological. Color has one stable meaning, with a restrained palette and another cue where needed. Give the chart a useful title, direct labels where they help, and a source note. State missing-data treatment; never silently turn missing observations into zero. Prefer SVG, legible labels, modest grid lines and whitespace. Interaction should help answer a question: hover for values, click for a series, brush for a range. A dashboard must remain interpretable before any interaction.
