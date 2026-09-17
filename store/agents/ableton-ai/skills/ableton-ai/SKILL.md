---
name: ableton-ai
description: Create and inspect music projects in the Ableton AI Harness workspace, including its local starter and optional upstream integration.
---

# Loop room

Read `studio.json` to understand the current controls; `"$STUDIO_TOOLCHAIN/../studio.config.json"`
describes their ranges. Run `"$STUDIO_TOOLCHAIN/run.sh" render` to make a new result.
Successful artifacts and their measurements are in `out/runs/<id>/`; `out/latest.json` names the
current result. A failed run preserves the last success and records the error in the verdict.

The starter is a local synthesized MIDI sequencer. It writes a standard MIDI file and WAV preview without Ableton. The optional Live action reads a running Ableton AI bridge; it does not overwrite tracks or start transport.

Use `"$STUDIO_TOOLCHAIN/../README.md"` for the integration contract and commands. Read the relevant
files under `$STUDIO_UPSTREAM` before using an upstream API. Keep controls within their documented
ranges, preserve the data needed to reproduce a comparison, and distinguish preview results from
native service or hardware output. The viewer supports history and artifact downloads; tell the
user which run contains the result, and what was actually measured.
