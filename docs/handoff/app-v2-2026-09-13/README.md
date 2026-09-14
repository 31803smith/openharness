# Saved app-v2 drafts

These files preserve work paused during the user's design discussion. They are
**not active application source**. Read [the current handoff](../../harness-v2-handoff.md)
before reusing them: the final decision requires distinct Navigate and Add UIs.

The drafts were saved from a worktree based on `ac443eb`. Both patches separately
pass `git apply --check` at the `26a372e` code checkpoint. They overlap in
`desktop/lib/screens/swarm_screen.dart`; this is not a verified combined patch.
The `.dart.txt` suffix keeps archived source out of compilation and test discovery.

## Picker draft

- `picker-wip.patch`: tracked source/test changes, with affected paths listed in
  `picker-files.txt`.
- `swarm_add_agent_test.dart.txt`: additional test source, intended for
  `desktop/test/swarm_add_agent_test.dart` when the relevant implementation is ready.

Contains bottom-right Add FAB and removal of top-right New agent; existing/new
agent routing for FAB and splits; inline Add semantics; preserved target/split
context; duplicate/group membership handling; always-on preview and eye-toggle
removal; a bounded output excerpt; darker shared modal veil; menu order changes;
native keyboard and widget regressions. It formerly kept global Navigate and
local Add in the same picker component, which the latest user instruction
explicitly supersedes. Its preview cleanup and footer/layout still need visual
refinement, and custom configs containing `picker.preview` need a deliberate
compatibility decision when removing that action.

Earlier validation before parking: 57 focused Flutter tests; 51 decoder and
343 AppKit checks. This is evidence for that draft only, not a completed visual
review or acceptance of the current two-UI design.

## Onboarding draft

- `onboarding-wip.patch`: changes to SwarmScreen and SwarmWelcome.
- `first_workspace_welcome.dart.txt`: proposed new widget, intended for
  `desktop/lib/widgets/first_workspace_welcome.dart`.

Contains a first-use welcome with ready agents, folder-first creation, separate
GitHub cloning, and progressively revealed machine/project browsing. It broadens
first-use detection beyond a single empty-machine case. It was saved before
validation and must be adapted to the approved shared Add interface. Do not
describe it as shipped or proven to improve onboarding.

Inspect/reuse selected changes rather than automatically applying both files:

```sh
# From repository root; checks only, without modifying source.
git apply --check docs/handoff/app-v2-2026-09-13/picker-wip.patch
git apply --check docs/handoff/app-v2-2026-09-13/onboarding-wip.patch
```

The original `/private/tmp/harness-*-wip*` copies are no longer required to
continue on another computer. Logs and screenshots mentioned in historical
progress notes remain local evidence, not portable build dependencies.
