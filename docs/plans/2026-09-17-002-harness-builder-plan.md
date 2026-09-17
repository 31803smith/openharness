# Harness Builder: a domain-specific harness that builds domain-specific harnesses

Status: in progress · 2026-09-17 · branch `harness-builder`
Builds on: `2026-09-17-001-zero-to-one-ideas.md` (idea 1), `store/spec/README.md` (the contract),
`store/README.md` (the authoring guide), and the 18 built-in harnesses as the quality bar.

## Decisions

- **The Builder is a harness.** `store/agents/harness-builder`, a DSH like any other: an engine, a
  playbook in `AGENTS.md` and skills, a toolchain, a verdict, and a viewer (Builder Studio).
- **Claude Code first; engine-portable output.** The Builder runs on Claude Code. What it writes must
  run on any engine the spec supports: `AGENTS.md` plus `SKILL.md` bundles, no engine-only syntax
  without a fallback, and a manifest whose `engine` is a choice, not an assumption.
- **Autonomous.** No human approval gates. The Builder researches, decides, builds, proves and
  packages on its own, and writes down why at every step.
- **Research first.** Nothing is written until the tool is understood: how it is driven headless,
  what its users call done, what can verify the work, and which open-source viewers already exist.
- **Skills are expert workflows**, the sequence an expert follows with the tool, proved by running
  them, never by reading them back.
- **The work in progress is the product.** The viewer shows every stage as the agent reaches it, meets
  a minimum interaction bar for its artifact type, and is delightful to look at and play with. Reuse
  or upgrade a shared viewer before building a new one.
- **Evaluation is declared and honest.** Every harness states how its output is judged: the tool's own
  verifier, checks against the brief, a model review, or none. A model review is a step the harness's
  agent performs with fresh context, not a separate API call.
- **A ladder of three, then KiCad.** Easy, medium, hard, each proving more of the Builder, before a
  target as ambitious as KiCad.

## The ladder

| Rung | Target | Why this rung | Toolchain | Evaluation | Viewer |
|---|---|---|---|---|---|
| Easy | **Vega-Lite** (charts) | Pure spec → picture; one pip wheel; proves the whole loop end to end | `vl-convert-python` (PyPI and conda-forge, no browser) + vendored `vega-embed` | Tool: the compiler validates and renders; checks: fields and marks the brief names | Interactive charts (tooltips, pan and zoom, selections), stages: data → encoding → polish |
| Medium | **LilyPond** (sheet music) | A real compiler with a binary toolchain; output you can see *and* hear | Official pinned release tarballs (macOS arm64/x86_64, Linux), checksummed | Tool: compile errors and warnings; checks: key, time, bars, instruments; review: engraving legibility | Score pages appearing as they are written, MIDI playback with the playing note lit |
| Hard | **QGIS** (maps) | Wraps a big desktop application headless; heavy toolchain; data in, cartography out | `qgis` 3.44 from conda-forge through `harness_micromamba` | Tool: geometry validity, CRS, layer and layout checks; checks: extent and layers the brief names; review: map legibility | Interactive map (layers, styling, feature inspect) growing layer by layer, plus the print layout |
| Graduation | **KiCad** | ERC/DRC, footprints, fabrication | — | — | Compared against Autonomous Circuit |

Each rung is done when the harness the Builder produced installs on a fresh machine, passes its own
evaluation on three proof prompts (easy, medium, hard for that domain), shows every stage in its
viewer, and has store examples made from those runs.

## What "not slop" means: the Builder's quality bar

Distilled from building the 18 harnesses on the shelf. The playbook (`AGENTS.md` and skills of
`store/agents/harness-builder`) turns each into steps and checks.

1. **Research.** Driving interface (CLI, headless, scripting API); file formats; what the tool's own
   community calls done; what verifies it (compilers, checkers, simulators); existing open-source web
   viewers; licences. Output: `research/brief.md`, with sources.
2. **Toolchain on a fresh machine.** Pinned versions, checksums, `store/tools/runtimes.sh` helpers
   (`harness_node`, `harness_venv`, `harness_micromamba`), a doctor that says what is missing in one
   line each, and the `env -i` fresh-machine run passing. Never the user's global installs.
3. **Skills.** The expert workflow as `SKILL.md` bundles with commands that were run; helper scripts
   where a raw API is error-prone; failure modes and their fixes written down.
4. **Viewer.** Stages from the domain (what a person would want to watch appear), a minimum
   interaction bar per artifact type, live updates from the workspace, dark and light, loopback only,
   no network fetches at runtime, reuse or upgrade of a shared viewer first.
5. **Evaluation.** The declared method (below), a verdict written as a feed at every stage, findings
   that say what to fix, and `ready` only when the declared method passes.
6. **Proof.** The Builder acts as the new harness's agent on three prompts, records every failure,
   fixes the harness, and repeats until the three pass and look good.
7. **Store.** Real examples from the proof runs (1600×1000 pictures, private data checked),
   `store.json`, credit and licences, `harness dsh check` passing.

## Evaluation contract

Four methods, declared by the harness and reported by the verdict:

| Method | Meaning | Examples |
|---|---|---|
| `tool` | The domain's own verifier passed | compile, tests, DRC, schema validation, simulation stability |
| `checks` | Measurable claims in the brief were checked | dimensions, counts, keys, extents |
| `review` | A fresh-context model review against a rubric | legibility of a score, clarity of a map, render quality |
| `none` | Nothing trustworthy verifies this domain | said plainly; the person is the judge |

Planned spec change (slice 3): the verdict gains `evaluation: [{ method, by, passed, detail? }]`, the
pane header and the store page show it ("Verified by LilyPond", "Reviewed by a model"), and `ready`
means every declared gate passed. A review is advisory unless the harness declares it a gate.

## Architecture

- **Workspace = the package being built.** The Builder's template lays out a package skeleton; the
  agent fills it. `harness dsh install <workspace> --link` makes it runnable while it is being built.
- **Builder toolchain** (`store/agents/harness-builder/toolchain/`): `scaffold` (package skeleton from
  the starter), `check` (`harness dsh check` plus the Builder's own bar), `fresh` (the `env -i` install
  run), `proof` (materialize a workspace for a proof prompt and capture the verdict and a snapshot of
  the viewer), `verdict` (the Builder's own feed).
- **Builder Studio** (its viewer): the stages of the build, the brief, a live embed of the new
  harness's viewer, the evaluation results, the proof runs with pictures, and the package checklist.
- **Store entry.** A "Build a harness" button in the Store sidebar opens New Harness with the Builder
  chosen and a first message field: "What tool should this harness wrap?" (slice 4).

## Slices

1. **Playbook**: `AGENTS.md` and skills for research, toolchain, skills authoring, viewer craft,
   evaluation, proof and store; the quality bar as checks.
2. **Builder package**: manifest, template, toolchain scripts, verdict, Builder Studio.
3. **Evaluation contract**: spec change, CLI verdict parsing, pane header and store page.
4. **Store sidebar button** in the desktop app.
5. **Rung 1, Vega-Lite**, built by the Builder; every miss goes back into the playbook.
6. **Rung 2, LilyPond**, then **rung 3, QGIS**, the same way.
