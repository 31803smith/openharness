# Harness package updates

Add explicit updates through `harness dsh update <id>` and the desktop Store. The daemon reports the
installed and available commits; catalog entries may also carry a package tree revision so publishing
an unrelated monorepo change does not offer every package an update.

Updates follow the installed repository and package path. Matching catalog entries supply the
published ref; other installations use their recorded ref. Linked development checkouts are left to
their owner. Shared viewers can be updated independently from their Store pages.

Fetch and validate the package before replacing anything. Keep the previous package while running
setup and doctor at the permanent installation path (virtual environments can embed that path).
Restore it on failure and write the new installed record only after success. Serialize mutations of
each package across CLI and daemon processes. Do not materialize or migrate workspaces during an
update: their files, instructions, session identity and stable skill links remain in place.

Verification: real local git repositories for whole-repo and subfolder updates, no-op updates,
rollback, linked installs, source identity, concurrent mutations and workspace preservation; wire and
CLI tests; desktop parsing and Store interaction tests; CLI typecheck/full suite and Flutter analysis
and relevant widget tests. Setup scripts' external side effects cannot be rolled back.
