# Changes to the DSH contract

Append-only. Each entry: Change / Why / Backward compatible / Mechanism.

## 2026-09-14 — spec 1

Initial contract. Lifted from the `.board.json` (Circuit) and `.episode.json` (TV) sidecars and the Vibe viewer's `serve:ensure` handoff.

## 2026-09-15 — phases in the verdict
- **Change:** `verdict.phases` (optional, ≤ 12): `[{ id, name, state, artifact? }]` with
  `state ∈ done | active | pending | failed`. The daemon forwards it on `AgentFrame.verdict.phases`;
  the desktop draws a phase strip in the viewer pane's header beside the verdict chip.
- **Why:** the pane is progressive — a Workshop run is research, concept, 3D, verify, and the user
  watching the viewer needs to know which of those is happening. The verdict already moves; this
  is the one line that says where.
- **Backward compatible:** yes — absent means no strip; every existing verdict is unchanged.
