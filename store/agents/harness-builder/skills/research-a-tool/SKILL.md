---
name: research-a-tool
description: Research a tool before building its harness — how it runs headless, what done means to its users, what verifies the work, which web viewers exist, licences — and write .builder/brief.md. Use at the research stage, and again whenever a later stage hits something the brief did not answer.
---

# Research a tool

A harness written from memory of a tool is slop. Before writing anything but the scaffold, find out
how the tool really works *today*, at the version you will pin, from primary sources.

```bash
"$BUILDER" stage research active --note "Reading <Tool>'s docs and source"
```

## Sources, in this order

1. The tool's own documentation for the current release (the CLI reference, the scripting API).
2. Its source repository: the README, `--help` of the real binary, examples, the test suite (tests show
   the API as it is used, not as it is documented), the changelog for breaking changes.
3. Its package listings: PyPI / npm / conda-forge / GitHub releases for versions, platforms and
   checksums. Check `https://api.anaconda.org/package/conda-forge/<name>` and `https://pypi.org/pypi/<name>/json`.
4. What its community makes with it: galleries, showcases, forums. This is where "good" is defined.
5. Existing open-source web viewers or renderers for its formats.

Install nothing globally while researching. When you need to try the binary, use a scratch directory
under `.builder/scratch/`, and prefer the exact pin you will ship.

## The brief: `.builder/brief.md`

Answer every question, with a source link or the command you ran for each fact. Write "unknown" and
what you tried rather than guessing.

1. **Identity.** The upstream name exactly as its project writes it, the author or organization for
   the tile, homepage, repository, licence (SPDX), and the harness id (`<owner>/<folder>`, folder = the
   upstream name in lower case). Category in a word or two ("Charts", "Sheet music", "Maps").
2. **What people make with it.** Five concrete things, from its gallery or community, that would make
   someone say "I want that". These seed the proof prompts.
3. **How it is driven without a GUI.** CLI commands, a scripting API, a file format an agent can
   write directly. Which of them is the most reliable for an agent, and why.
4. **Inputs and outputs.** The source files the agent writes, the artifacts the tool produces (with
   formats), and which artifact a person wants to look at and touch.
5. **The stages of the work** as an expert does it, from nothing to done: each stage names what exists
   at its end that a viewer could show. Four to eight stages. This becomes the viewer's progression and
   the verdict's phases.
6. **Toolchain.** The exact version to pin; how to get it on macOS arm64, macOS x86_64 and Linux x86_64
   without Homebrew or root (a PyPI wheel, conda-forge through micromamba, an official release tarball
   with a checksum, an npm package); its size; what it needs at runtime (a browser? fonts? a GPU?).
7. **Verification.** Everything that can say whether the output is right: compilers, validators,
   linters, checkers, simulators, schema validation, round trips. What each catches and misses. What
   in a typical request is measurable (sizes, counts, keys, extents). What only a human or a model
   reviewer could judge.
8. **Viewer options.** Existing web renderers for the artifact (with licence and size), which of the
   Store's shared viewers (`$BUILDER_REFERENCE/store/viewers/`) already handle it or could be upgraded
   to, and what a delightful interaction with this artifact is.
9. **Risks.** Slow first runs, network access at runtime, platform gaps, licence constraints, known
   crashes in headless mode.
10. **Decision.** The target in one paragraph: engine, how the agent drives the tool, the viewer
    (reuse, upgrade or new), the evaluation method, and the three proof prompts (easy, medium, hard).

Keep it tight: facts and decisions, not prose. It is read by you in every later stage and shown in
Builder Studio.

## Done

Every question answered, the decision written, and the id, name, category and engine written into
`harness.json`. Then:

```bash
"$BUILDER" stage research done --note "<one line: how the tool is driven, viewer, evaluation>"
```
