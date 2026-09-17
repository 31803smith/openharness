---
name: pin-a-toolchain
description: Make a harness's toolchain install on a brand-new machine — pinned, checksummed, inside the package, through runtimes.sh — with a doctor that says what is missing, proved by builder fresh. Use at the toolchain stage and whenever setup, doctor or init changes.
---

# Pin a toolchain

The machine is a new Mac: Apple's Python 3.9, no Homebrew, no Node on PATH, no compiler, and a person
who pressed Get and will not open a terminal. A harness that answers "brew install" has failed.

```bash
"$BUILDER" stage toolchain active --note "Pinning <tool> <version>"
```

## Rules

- **Everything inside `package/`**: a `.venv`, a `node_modules`, a `vendor/` tarball, a
  conda environment. Never `pip install --user`, `npm -g`, `brew`, `sudo`, or the user's shell profile.
- **Interpreters come from `toolchain/runtimes.sh`** (copy it verbatim from
  `$BUILDER_REFERENCE/store/tools/runtimes.sh`; do not edit the copy):
  - `harness_node 20 || exit 1` for Node with npm (the machine's, else Harness's own).
  - `harness_venv "$PWD/.venv" 3.12 || exit 1` then `harness_pip "$PWD/.venv" pkg==1.2.3` for Python.
  - `harness_micromamba` / `harness_conda_env "$PWD/.conda" qgis=3.44.14` for native libraries PyPI
    has no wheel for.
- **Pin exact versions** in a `VERSIONS` file (sourced by setup), a lockfile (`package-lock.json`,
  `requirements.lock`), or both. Direct downloads carry a SHA-256 checked before use; a mismatch fails.
- **Setup is idempotent**: a second run is fast and changes nothing. A failed download leaves the
  previous working install in place (download to a temp name, then move).
- **Every failure is one line starting `miss `** that says what is missing and what to do, and the
  script exits non-zero. Never a stack trace as the only message.
- **Pay first-run costs in setup**: import heavy modules once, download fonts, warm caches, so the
  first prompt is not a five-minute wait.
- **Runtime has no network** unless the domain needs it (map tiles, a package index); say so in the
  brief and handle offline gracefully.

## The scripts

- `toolchain/setup.sh`: runs once at install, cwd = the package. Starts with
  `set -euo pipefail`, `cd "$(dirname "$0")/.."`, `. toolchain/runtimes.sh`.
- `toolchain/doctor.sh`: exit 0 when the harness can run. One line per check: `ok   <what> <version>`
  or `miss <what> — run toolchain/setup.sh`. Checks what the agent and viewer actually use (import the
  module, run `--version`), not that a directory exists.
- `toolchain/init-workspace.sh`: runs in a new workspace after the template copy, with
  `HARNESS_DSH_DIR` set. Seeds the first verdict (every phase `pending`, the first `active`) so the pane
  header has a state before the first prompt. Fast, no network.
- Agent-facing commands (`toolchain/render`, `toolchain/check`…): small executable wrappers that find
  their interpreter inside the package, so the agent never types a bare `python` or `node`. Point the
  agent at them through `agent.env` in `harness.json` (`"LILY_TOOLCHAIN": "${dsh}/toolchain"`).

## Prove it on a fresh machine

```bash
"$BUILDER" fresh
```

It copies the package to a temporary directory and runs setup, doctor and init under `env -i` with a
new HOME and `PATH=/usr/bin:/bin:/usr/sbin:/sbin`: the new-Mac case. Read `.builder/fresh.json` and
fix every failure in the package, then run it again. Passing on your own machine proves nothing; this
does. Stubs and symlinks: never write a stub over a symlinked command (it writes through the link).

## Done

`"$BUILDER" fresh` passes, and doctor prints only `ok` lines.

```bash
"$BUILDER" stage toolchain done --note "<tool> <version> via <mechanism>; fresh install <N>s"
```
