# Engines

Harness never wraps an agent. It reads the transcript the agent already writes and installs the
vendor's own hooks or plugin to learn when a turn starts and ends. Your credentials stay in your
`~/.claude`, `~/.codex`, and so on.

| Engine | Binary | How Harness follows it | Resume | Permission bypass | Grid |
|---|---|---|---|---|---|
| Claude Code | `claude` | hooks in `~/.claude/settings.json` + JSONL transcript | `--resume` | `--dangerously-skip-permissions` | yes |
| Codex | `codex` | `hooks.json` per `CODEX_HOME` + JSONL rollouts | `resume` | `--dangerously-bypass-approvals-and-sandbox` | yes |
| Cursor | `cursor-agent` | `~/.cursor/hooks.json` + transcript | `--resume` | `--force` | — |
| OpenCode | `opencode` | plugin + SQLite | `--session` | `--auto` | yes |
| Pi | `pi` | extension + transcript | `--session` | — | yes |
| Hermes | `hermes` | hooks + SQLite | `--resume` | — | yes |
| Command Code | `cmd` | hooks + transcript | `--resume` | — | — |
| Devin | `devin` | hooks + SQLite | — | — | — |
| Muse Code | `muse` | transcript | `resume` | — | — |
| Amp | `amp` | plugin writes the transcript Harness tails | `threads continue` | — | — |
| Kilo | `kilo` | plugin + SQLite | `--session` | — | — |
| Grok Build | `grok` | hooks + `updates.jsonl` | `--resume` | — | yes |
| Antigravity | `agy` | hooks + transcript | `--conversation` | — | — |
| GitHub Copilot | `copilot` | hooks + transcript | `--resume` | — | yes |

A launcher that hands the pane to one of these is that engine: `ori claude` is a Claude Code agent,
and the daemon reads the gateway off the live process so recaps and routing go through it too.

**Grids.** An agent can be pointed at an [Autonomous Grid](https://www.autonomous.ai/grid) relay
instead of the engine's own login, at creation or later with **Retarget**, which respawns the same
pane with the grid's environment and `--resume`. The engines marked above support it; the key travels
in the tmux session environment, never in argv or a file. Needs tmux ≥ 3.2.
