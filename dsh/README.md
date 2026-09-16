# Domain-specific harnesses

A **domain-specific harness (DSH)** turns Harness into a product for one domain: PCB design,
3D CAD, short drama, robot training. It is a git repo that Harness installs on a machine. Users see
it as one more engine tile in Create Harness — pick **Circuit**, choose a folder, prompt — and get
the domain's skills in the agent, its toolchain on the machine, its viewer in a pane next to the
terminal, and its verdict in the pane header.

Harness never imports a DSH's code. It reads one manifest, copies files into the workspace, runs
the commands the manifest declares, and watches one JSON file. That is the whole coupling, and it
is what lets hundreds of DSHs exist without any of them touching this repo.

## Anatomy

```
harness.json      manifest: id, name, base engine, workspace, agent, toolchain, viewer, verdict
AGENTS.md         appended to the agent's instructions in every workspace
skills/           SKILL.md bundles, linked into the workspace
template/         copied into an empty workspace
toolchain/        setup.sh (once, at install) · doctor.sh (exit 0 = ready) · viewer.sh (optional)
viewer/           optional: whatever viewer.sh serves
```

## Tiers

| Tier | Ships | Harness shows |
|---|---|---|
| 0 | manifest, AGENTS.md, skills | the tile, the terminal |
| 1 | + scripts that write `.harness/verdict.json` | + a ready chip and findings in the pane header |
| 2 | + a viewer server | + a web pane next to the terminal |

[`starter-dsh/`](starter-dsh/) is tier 0 and the copy-me template. Circuit and Workshop are tier 2.

## The contract

[`spec/README.md`](spec/README.md) is the whole contract: the manifest, the verdict file, what
Harness does at create time, and what it sets in the engine's environment. The JSON Schemas in
[`spec/schema/`](spec/schema/) are normative. The spec is frozen; changes are appended to
[`spec/CHANGES.md`](spec/CHANGES.md).

## Installing

```bash
harness dsh install autonomous/copper                                    # by registry id
harness dsh install https://github.com/autonomous-ai/autonomous-circuit   # by git URL
harness dsh install /path/to/checkout --link                              # symlink, for development
harness dsh list
harness dsh doctor autonomous/copper
harness dsh check /path/to/checkout                                       # conformance, before publishing
```

The desktop app offers the same install from the Create Harness dialog: a DSH the machine does not
have yet shows "Harness will install Circuit on this machine before starting".

## Publishing

Add one file under [`registry/<owner>/<name>.json`](registry/) with the repo URL and pinned ref. CI
clones it and runs the conformance check; green merges. First-party entries carry `verified: true`;
everything else shows its git URL and an unverified note on install.
