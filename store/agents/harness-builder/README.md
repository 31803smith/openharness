# Harness Builder

A domain-specific harness for building domain-specific harnesses. Name a tool in the chat pane
("Build a harness for LilyPond") and watch Builder Studio in the viewer pane while the agent
researches the tool, pins its toolchain, writes the expert skills, crafts a live viewer, decides how
the output is judged, proves the harness on three real prompts, and readies it for the Store.

The harness it makes lives in `package/` of the workspace and follows the same contract as every
package in `store/agents/` (see `store/spec/README.md`). The Builder holds it to a quality bar that
comes from building the first harnesses by hand: a viewer that moves while the agent works, skills
made of commands that were actually run, an evaluation that never claims more than it checks, an
install that works on a fresh machine, and proofs a person has watched frame by frame.

- `harness.json`: the manifest Harness reads (spec 1). Runs on Codex; the playbook and skills are
  engine-neutral, and `builder proof run --engine claude|codex` proves a harness on either.
- `AGENTS.md`: the playbook, the seven stages and the quality bar.
- `skills/`: `research-a-tool`, `pin-a-toolchain`, `write-expert-skills`, `craft-the-viewer`,
  `design-the-evaluation`, `prove-it`, `ship-to-the-store`.
- `template/`: a fresh build workspace (`.builder/build.json`).
- `toolchain/`: the `builder` CLI (stages, scaffold, check, fresh-machine install, proofs,
  snapshots, showcase) and Builder Studio, the viewer: the stage track, the live viewer of the
  harness under proof, filmstrips of each proof, the brief, the checks, the package tree and the
  decisions.
- `reference/`: fetched at setup, a pinned sparse copy of this repository's spec, starter, shared
  viewers and the best harnesses, for the agent to read.

```sh
harness dsh check .                  # conformance
harness dsh install "$PWD" --link    # this checkout as the installed harness
cd toolchain && npm test             # the build record, scaffold, quality bar, materialize, proofs
```

## Credit and stewardship

Harness Builder is Autonomous's, MIT (`LICENSE`). Its toolchain installs
[marked](https://github.com/markedjs/marked) (MIT, Christopher Jeffrey and the marked contributors)
to render the brief and decisions, and [playwright-core](https://github.com/microsoft/playwright)
(Apache-2.0, Microsoft) with its headless Chromium to snapshot viewers; neither is changed or
vendored here. The harnesses it builds credit the tools they wrap in their own READMEs.
