---
name: dimos
description: Create and inspect robotics projects in the DimOS Harness workspace, including its local starter and optional upstream integration.
---

# Mission control

Read `studio.json` to understand the current controls; `"$STUDIO_TOOLCHAIN/../studio.config.json"`
describes their ranges. Run `"$STUDIO_TOOLCHAIN/run.sh" simulate` to make a new result.
Successful artifacts and their measurements are in `out/runs/<id>/`; `out/latest.json` names the
current result. A failed run preserves the last success and records the error in the verdict.

The starter performs A* route planning and real MuJoCo dynamics in an original two-dimensional office rover model. It is not a Unitree robot or physical execution. DimOS is fetched at a pinned source commit; its full daemon and perception stack are an optional, larger installation.

Use `"$STUDIO_TOOLCHAIN/../README.md"` for the integration contract and commands. Read the relevant
files under `$STUDIO_UPSTREAM` before using an upstream API. Keep controls within their documented
ranges, preserve the data needed to reproduce a comparison, and distinguish preview results from
native service or hardware output. The viewer supports history and artifact downloads; tell the
user which run contains the result, and what was actually measured.
