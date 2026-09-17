---
name: prove-it
description: Prove the harness on three real prompts (easy, medium, hard for its domain) by running a fresh engine agent that knows only the harness's own AGENTS.md and skills, watching the viewer frame by frame, and fixing the harness until all three pass and look good. Use at the proof stage, and after any change to skills, viewer or evaluation.
---

# Prove it

You wrote the harness, so you cannot test it by imagining a user. A **fresh agent** that knows only
the harness's `AGENTS.md` and skills can. Every failure in a proof is a bug in the harness: fix the
harness, not the proof, and never hand-edit a proof's output to make it pass.

```bash
"$BUILDER" stage proof active --note "Proving on three prompts"
```

## The three prompts

From the brief's "what people make with it", one each:

- **easy**: one clear artifact, the core of the tool (a bar chart of five values; an eight-bar melody).
- **medium**: several features together, the way a real user asks (a dashboard of three linked charts;
  a lead sheet with chords and lyrics).
- **hard**: something a person would show off, pushing the tool's depth (an interactive,
  multi-layer, annotated result).

Write them as a user would: one or two sentences, concrete, no instructions about the harness itself.

## Run a proof

```bash
"$BUILDER" proof run easy --prompt "Make a bar chart of monthly rainfall in Seattle with the wettest month highlighted."
```

It materializes a workspace from the package exactly as Harness does (template, init, `AGENTS.md`, skills
linked for the engine), starts the harness's viewer on a free port (shown live in Builder Studio),
installs the package with `harness dsh install --link` when the CLI is present, then runs a fresh
**Claude Code** agent (`claude -p`, auto permission mode) in that workspace with the prompt. While it
runs, it snapshots the viewer every few seconds into `.builder/proofs/easy/frames/` and records the
verdict after each change. At the end it writes `.builder/proofs/easy/result.json` (the prompt, the
final verdict, the agent's last message, timings, the frame list) and `viewer.png`.

`"$BUILDER" proof run` takes minutes. Run the three proofs one at a time, reviewing each before
starting the next, so a fix learned from `easy` improves `medium`.

## Review a proof, as the person watching

Read `result.json`, the agent's log (`agent.log`), and **look at the frames in order** (read the PNGs):

1. **Did the pane move early?** The first frame with real content should come within a minute or two.
   A pane that stays empty until the end fails, whatever the result.
2. **Did every stage appear?** Match the frames to the brief's stages.
3. **Is the final result good?** Would the tool's own community be happy with it? Judge it against the
   brief's gallery examples, not against "it rendered".
4. **Is the viewer delightful at the end?** Try the interactions in the live viewer yourself with
   `"$BUILDER" snapshot` at a few states, or read the viewer's page to confirm the controls exist.
5. **Did the evaluation tell the truth?** `ready: true` on a visibly wrong result is an evaluation bug;
   `ready: false` on a good result is too.
6. **Did the agent struggle?** Retries, wrong commands, reading the toolchain source, asking what to do:
   each is a gap in `AGENTS.md` or a skill.

Write the review into `.builder/proofs/<id>/review.md`: pass or fail on each point, and the fixes.

## Fix, then prove again

Mark the stage you are fixing active (`skills`, `viewer`, `evaluation`), fix the harness, mark it done,
and rerun the same proof. Repeat until all three pass every point. Record each fix in
`.builder/decisions.md`: these are the lessons that make the next harness better.

```bash
"$BUILDER" proof pass easy --note "<one line: what it made>"     # or: proof fail easy --note "<why>"
```

## Done

All three proofs passed with a written review, and their final frames are good enough to put on the
Store.

```bash
"$BUILDER" stage proof done --note "easy, medium, hard passed; <N> fixes along the way"
```
