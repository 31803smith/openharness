---
name: vega-lite
description: Build and refine Vega-Lite charts with local data, progressive previews, linked interaction, truthful encodings, checked requirements and portable exports. Use for any chart or visualization request in this harness.
---

# From question to interactive evidence

Read the workspace `brief.json` and the data before choosing marks. Use direct Vega-Lite v6 JSON. No Altair, browser build system, remote CDN or extra installation is needed. The pane watches saves and performs the same check as the commands below.

## 1. Save the question and data first

Fill the brief with `title`, `question`, `description` (including interaction instructions), `source`, `stage`, `artifact`, `data` and `requirements`. Keep paths relative to the **workspace root**, including every `data.url` inside a nested chart. All data must be local or inline; network URLs, image marks and paths outside the workspace are rejected. CSV numeric types must be deliberate (`format.parse` or typed encodings). Save real user data without replacing it. Synthetic data is appropriate for a requested illustration and must be labelled.

A useful requirement contract:

```json
{
  "minRows": 6,
  "fields": ["city", "share"],
  "marks": ["bar", "text"],
  "params": [],
  "minPanels": 1,
  "assertions": [
    {"path": "/encoding/x/scale/zero", "equals": true, "label": "Bars start at zero"}
  ]
}
```

`minRows` checks loaded input rows across distinct source tables, not rows after aggregation. `fields` checks the union of input column names. `marks` checks authored mark types. `params` checks authored parameter names, not their actual behavior. `minPanels` counts authored mark-bearing units/layers, not visible facet cells. Assertions compare exact values at RFC 6901 JSON pointers in the authored spec. Declare the finished chart's requirements up front. Before `phase polish` an unmet requirement shows as a `To do` note, not a failure; from polish on it is an error. Declare only claims the checker really measures; add exact assertions for units, scales, transforms or filters the request requires. Do not weaken requirements to silence a failure.

```bash
"$VEGA_LITE_TOOLCHAIN/vl" profile data/sample.csv
"$VEGA_LITE_TOOLCHAIN/vl" phase data
```

The profile returns row count, column types, missing values and five sample rows. CSV and TSV profiles infer numbers, booleans and dates the way Vega's `parse: "auto"` does, and so does the pane's Data tab. The chart itself only parses what you declare, so give dates and ambiguous columns an explicit `format.parse`. Missing data should be filtered or otherwise handled with an explanation, never silently filled with zero.

## 2. Build the smallest correct chart

Start with `$schema: "https://vega.github.io/schema/vega-lite/v6.json"`, a title, data, one mark and typed encodings. Save exactly that first, plain, so the pane shows the shape of the data. Add labels and interactions in a second save (`phase explore`) and styling in a third (`phase polish`). `nominal` is a category, `ordinal` is an ordered category, `quantitative` is numeric, and `temporal` is time. Use `format.parse` for ambiguous input. `width` and `height` refer to the plot, excluding axes/legends. For composed views use numeric child widths; `width: "container"` is unreliable inside concatenations.

Three complete patterns are included in `examples/` beside this skill (also `$VEGA_LITE_TOOLCHAIN/../skills/vega-lite/examples/`):

- `ranked-bars.vl.json`: sorted horizontal bars + a text layer, zero baseline, explicit axis unit and tooltip. Layered sorting can produce a conflicting-sort compiler warning; an explicit category order is deterministic and avoids it. Leave room past the maximum for labels.
- `time-brush.vl.json`: monthly lines, a legend-bound point selection, and an overview interval that controls the detail x domain. Keep dates ISO 8601, units explicit and colors stable. A few pixels of `scale.padding` on the time axis keep the first and last points and month labels inside the plot; without it, December's label drops and the end points are clipped. A target is a separate rule layer with a label; keep layer scales/legends consistent.
- `linked-views.vl.json`: scatterplot brush filters a companion bar chart, with wheel zoom and Shift-drag axis pan. Region color has the same legend configuration in both views. Normal dragging brushes; the zoom interval uses Shift-drag so gestures do not fight.

All three compiled and rendered successfully with the pinned toolchain. Treat them as grammar patterns, replacing their synthetic data and claims with the actual request.

```bash
"$VEGA_LITE_TOOLCHAIN/vl" phase encode
"$VEGA_LITE_TOOLCHAIN/vl" check
```

## 3. Make interaction useful

V6 uses `params`, with `select.type` equal to `point` or `interval`, not legacy `selection` or `single`/`multi`. Parameter names must be unique within the specification. Define each brush on the unit receiving pointer events, and refer to it with `{"filter":{"param":"brush"}}`, a conditional encoding, or `scale.domain.param` in another unit. Empty selection includes everything by default; document that behavior.

Use `mark: {"type":"circle", "tooltip":true}` for meaningful default values, or an explicit `encoding.tooltip` list with titles and formats. A point selection bound to a legend uses `fields:["region"]`, `bind:"legend"`, and a conditional opacity. Keep `legend` configuration identical where the scale is shared; `legend:null` on one child and an enabled legend on another can conflict.

For a single continuous view, an interval with `bind:"scales"` pans and wheel-zooms. A brush and scale zoom need separate gestures (see the linked example). For time series, an overview brush is often more legible than unrestricted zoom. For multiple panels, keep filters, brush predicates and naming explicit; check that all views begin with visible data. The pane offers fit, page zoom, reset selections and a temporary Explore mode for simple unit charts. Export always preserves the authored specification; include important interactions in the source itself.

```bash
"$VEGA_LITE_TOOLCHAIN/vl" phase explore
```

## 4. Polish the evidence

Choose ordered bars for comparisons, lines for time, circles for relationships, rectangles for dense matrices, and small multiples for fair comparisons. Use faceting or a limited palette rather than a rainbow legend. A line implies continuity: do not connect unrelated categories. Explicitly name aggregate measures (`mean`, `sum`, `count`) and axes. For percentages establish whether the data is 0–1 (format `.0%`) or 0–100 (unit `%`, format `.0f`). Add uncertainty bands only when lower/upper values really represent uncertainty. Use a zero baseline for bars; explain any deliberate nonzero scale for other quantitative charts.

The studio theme owns the chart's chrome: background, font, title, axis, legend and header text, grid lines, and default text-label and rule colours, in both light and dark. Leave those out of `config` and spend colour on data (`mark.color`, `scale.range`, `config.range.category`). If you do set a chrome colour, dark mode swaps any that would be illegible. Keep structural choices (`title.anchor`, font sizes, `axis.domain`, `view.stroke`) in `config` as usual.

Use meaningful, descriptive text rather than an unsupported causal claim. Keep chart titles concise and source notes truthful. Prefer system fonts, moderate grids, 12–14 px axis labels and 18–24 px chart titles. Use the pane’s Data tab to inspect actual rows and its Checks tab to inspect findings. **Look at the chart yourself**: `vl snapshot` writes `.harness/review/chart.png` (and `--theme dark` writes `chart-dark.png`). Open the image and fix clipped labels, collisions and cramped panels before calling it polished.

```bash
"$VEGA_LITE_TOOLCHAIN/vl" phase polish
"$VEGA_LITE_TOOLCHAIN/vl" snapshot
```

Export creates `exports/chart.svg`, `chart.vg.json`, `chart.vl.json` (local data inlined, the studio's light theme beneath your own config, so it looks the same in any Vega-Lite editor), and `chart.html` with the exact browser libraries embedded. The HTML keeps the authored interactions, works offline and follows the reader's light or dark preference. The pane also exports the chart as currently viewed (selections and theme) as SVG or PNG.

## 5. Verify, then have fresh eyes review it

```bash
"$VEGA_LITE_TOOLCHAIN/vl" phase verify
"$VEGA_LITE_TOOLCHAIN/vl" snapshot
```

`ready` needs three gates, reported in `.harness/verdict.json` under `evaluation`: **tool** (schema, compiler, renderer), **checks** (the brief's requirements) and **review**. For the review, a reviewer who never saw your work grades the snapshot against `review-rubric.md` (beside this skill). `vl snapshot` writes `.harness/review/request.md`, which holds the brief, the rubric, and the exact `result.json` shape tied to this version of the chart. Hand the reviewer only that file, never your conversation:

- **Claude Code:** start a subagent whose whole prompt is `Read .harness/review/request.md and follow it exactly.`
- **Codex, or any engine without subagents:** from the workspace, run a clean non-interactive session:
  `codex exec "Read .harness/review/request.md and follow it exactly." --skip-git-repo-check --ephemeral -s workspace-write -i .harness/review/chart.png </dev/null`
  or `claude -p "Read .harness/review/request.md and follow it exactly." --allowedTools Read Write`.

The reviewer writes `.harness/review/result.json`; the pane picks it up on its own. Run `"$VEGA_LITE_TOOLCHAIN/check"`. It exits 0 only when every gate passed. A failed criterion is an error finding naming what to change: fix the chart, run `vl snapshot`, and ask for a new review. Any edit to the chart or its data makes the old review stale. Never write or edit `result.json` yourself, and never soften the rubric. Then export:

```bash
"$VEGA_LITE_TOOLCHAIN/check"
"$VEGA_LITE_TOOLCHAIN/vl" export
```

## Debug in order

1. **Input / schema**: malformed JSON, typo or unsupported property. Check the indicated JSON pointer and pinned v6 dialect. Keep the last valid file while preparing a large rewrite; save atomically when possible.
2. **Compiler warning**: conflicting sorts, scales or legends. Give shared encodings consistent configuration, or resolve independently when that is analytically appropriate. Compiler warnings block readiness.
3. **Runtime / empty SVG**: check column case, date parse, filter predicates, empty datasets and invalid expressions. A schema-valid chart can still produce no data marks.
4. **Requirements**: fix the missing field, mark, param or exact assertion; verify the request has not been misunderstood.
5. **Visual quality**: look for overlapping titles, clipped labels, overly tall concatenations, misleading units and unusable selection gestures. Machine checks do not see those. Your own look at `vl snapshot` and the fresh review do.

The headless renderer cannot attach browser `window` event sources; that one exact diagnostic is suppressed during SVG checks. Interactions remain intact in browser output. Checks do not assert that every gesture works or the data is factually true. The viewer rechecks on every save; `.harness/verdict.json` is a feed, never a file to edit by hand.
