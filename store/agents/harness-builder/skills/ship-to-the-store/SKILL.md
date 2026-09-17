---
name: ship-to-the-store
description: Package the proved harness for the Harness Store — store.json with examples made from the proof runs, credit and licences, a README, no private data — and pass builder check. Use at the store stage.
---

# Ship to the Store

```bash
"$BUILDER" stage store active --note "Packaging for the Store"
```

## Examples from the proofs

The Store page leads with prompt → output examples. Make them from the passed proofs, never from a
mock-up:

```bash
"$BUILDER" showcase easy medium hard
```

That writes a 1600×1000 JPEG of each proof's final frame to `.builder/showcase/<id>.jpg` (under
350 KB) and an `examples` list into `store.json` with each proof's prompt and a caption you then
edit: one line naming what came out and one fact that makes it concrete ("Seattle rainfall ·
12 months · wettest month highlighted"). The image URLs are filled in when the package is published.

Look at each picture. It shows the viewer's final state: no error overlay, no half-rendered frame, no
empty pane. If a proof's final frame is not Store-worthy, the proof did not pass: go back.

## `store.json`

```json
{ "homepage": "https://…", "upstream": "https://github.com/…", "license": "MIT",
  "evaluation": [{ "method": "tool", "by": "…" }],
  "examples": [{ "prompt": "…", "image": "…", "caption": "…" }] }
```

`evaluation` is what the evaluation stage declared (the `design-the-evaluation` skill): the methods
the proofs' verdicts actually reported, worded to finish "Verified by …", "Checked against …",
"Reviewed against …". Never a method the harness does not run.

## Credit and licences

- The folder and the harness `name` are the upstream project's own name; `author` in `harness.json` is
  the upstream author or organization, as the project credits itself.
- `LICENSE` for the harness itself (MIT unless the upstream licence requires otherwise).
- The upstream licence beside anything of theirs the package vendors (`LICENSE-<project>`), and a
  `THIRD_PARTY_NOTICES.md` listing every vendored component with its licence and version.
- `README.md`: what the harness does in two sentences, how to install
  (`harness dsh install <id>` / `harness dsh install "$PWD" --link`), how its evaluation works, and a
  **Credit and stewardship** section: whose project it wraps, that the wrapper was written on the
  project's behalf, and that the maintainers are welcome to own it.

## No private data, anywhere

No home paths (`/Users/<name>`, `/home/<name>`), usernames, hostnames, email addresses, tokens or API
keys in any file, and none visible in any picture (check the proof frames: terminal text, file paths in
viewer chrome). `"$BUILDER" check` scans text files; you check the pictures by looking at them.

## Done

```bash
"$BUILDER" check
```

No errors, warnings read and either fixed or explained in `.builder/decisions.md`.

```bash
"$BUILDER" stage store done --note "<id> ready: <N> examples"
```
