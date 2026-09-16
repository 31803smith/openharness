# Harness

Agents that build things, in one window. Code with Claude Code, Codex, Cursor and eleven more. PCBs
with Copper. 3D parts with Solid. Keynotes with Marp. Every agent runs in a persistent terminal on
any machine you own, and the domains beyond code get a viewer beside it that shows the work as it
is made.

<p align="center">
  <img src=".github/assets/screenshots/marp.png" width="960" alt="A Marp tab: the keynote in the viewer on the left, the Claude Code agent that wrote it on the right, ten slides and Ready in the header">
</p>

## One app, many harnesses

A harness is an agent plus a domain. For code, the agent is the whole harness: fourteen engines,
unwrapped. Harness reads the transcript each one already writes and installs the vendor's own hooks;
your credentials stay in your `~/.claude`, `~/.codex`, and so on.

<p align="center">
  <img src=".github/assets/engines/claude.png"      height="72" alt="Claude Code"  title="Claude Code">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/codex.png"       height="72" alt="Codex"        title="Codex">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/cursor.png"      height="72" alt="Cursor"       title="Cursor">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/opencode.png"    height="72" alt="OpenCode"     title="OpenCode">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/pi.png"          height="72" alt="Pi"           title="Pi">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/hermes.png"      height="72" alt="Hermes"       title="Hermes">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/commandcode.png" height="72" alt="Command Code" title="Command Code">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/devin.png"       height="72" alt="Devin"        title="Devin">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/muse.png"        height="72" alt="Muse Code"    title="Muse Code">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/amp.png"         height="72" alt="Amp"          title="Amp">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/kilo.png"        height="72" alt="Kilo"         title="Kilo">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/grok.png"        height="72" alt="Grok"         title="Grok">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/agy.png"         height="72" alt="Antigravity"  title="Antigravity">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/copilot.png"     height="72" alt="GitHub Copilot" title="GitHub Copilot">
</p>

For everything else, a harness brings the domain with it: its skills in the agent, its toolchain on
the machine, its viewer beside the terminal, and a header that says where the work is. Three ship
today, each on one of the agents above, and yours is a git repository away.

<p align="center">
  <img src=".github/assets/engines/copper.png" height="72" alt="Copper · PCB"       title="Copper · PCB, on Claude Code">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/solid.png"  height="72" alt="Solid · 3D design"  title="Solid · 3D design, on Codex">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/marp.png"   height="72" alt="Marp · Slides"      title="Marp · Slides, on Claude Code">
</p>

| Harness | You say | You get | You watch |
|---|---|---|---|
| **Claude Code, Codex, Cursor, …** · Code | "add OAuth to the API" | the change, in your repo | the agent's terminal |
| **Copper** · PCB | "a USB-C powered ESP32 sensor board" | a fab-ready board, ordered in a click | the board, its checks, the fab |
| **Solid** · 3D design | "an iPhone case with a lanyard loop" | a printable STEP part | the model: Build, Fit, Print, Review |
| **Marp** · Slides | "a launch keynote for 200 engineers" | a keynote with art and speaker notes | the slides filling in, then Present |
| **Yours** | | anything an agent can build in a folder | [build a harness](#extend-harness) |

<p align="center">
  <img src=".github/assets/screenshots/solid.png" width="960" alt="A Solid tab: the 3D part in the viewer, the Codex agent that made it beside it, Ready in the header">
</p>

## Every machine you own

Your laptop, the Mac mini at home, the box in the rack, in one window, side by side. Each machine
runs a small daemon that dials out; nothing to open, no SSH, no VPN. The relay in between forwards
ciphertext and holds no keys, and terminal traffic goes machine to machine over WebRTC when it can.

Sessions live on the machine, not in the window. Every agent is a tmux pane there. Close the laptop,
open it on the train: same pane, same scrollback. After a reboot the daemon brings each agent back
with the engine's own `--resume` and the same id. Start an agent on another machine by browsing its
folders from New Agent, or clone a repository there first. The same machines are reachable from a
browser at [harness.autonomous.ai](https://harness.autonomous.ai) after one pairing.

<p align="center">
  <img src=".github/assets/screenshots/new-agent.png" width="720" alt="New Agent: choose a harness, then where it runs — this machine, the iMac at home, the iMac at the office">
</p>

## A device for the desk

A round USB display with a microphone. Your agents are tiles in the order of the window's panes,
each with what it is doing and for how long. When an agent asks a question, it is on the face,
answerable with a tap. When a turn finishes, the recap, with one quiet tone. Double-tap and speak, and
Boss mode routes the task to the agent already on it. No WiFi, no credential: plugging it in is the
authorization, and the daemon on that computer serves it over the cable.

https://github.com/user-attachments/assets/97848065-61c6-40df-be66-a8247f69aa4c

## Install

**macOS 12+ (Apple Silicon and Intel), Linux (Ubuntu 22.04+).** Download the app from
[harness.autonomous.ai/desktop](https://harness.autonomous.ai/desktop). On first launch it checks for
tmux, installs a managed Node 20 and the `harness` daemon under `~/.harness`, signs you in with SSO,
and starts the daemon. This computer is your first machine.

**Add another machine** — a server, a Mac mini, a container — with the daemon alone. Node ≥ 20 and
tmux are the prerequisites; `sqlite3` is needed only for the engines that keep their conversations in
SQLite (OpenCode, Kilo, Hermes, Devin).

```bash
curl -fsSL https://harness.autonomous.ai/cli/install.sh | bash
harness login      # browser SSO, saves this computer's session
harness start      # connects; reconnects to the same machine on every later start
```

It appears in the app's machine list within a minute. There is no token to copy: a durable computer
id under `~/.harness` keeps later starts attached to the same machine record.

One thing to know from the start: **the daemon only knows about panes it created.** Sessions you start
from the app or the web are tmux sessions named `harness-*`, owned by the daemon. A `claude` you launch
by hand in your own tmux is not picked up.

## First five minutes

**⌘N** New Agent: a harness, a machine, a folder, Create. **⌘O** finds any agent, tab, project or
machine, and `>` runs a command. **⌘B** takes a task in plain words and routes it to the agent
already on it. **⌘R** and **⌘D** split, **⌘S** picks a layout, **⌘⏎** zooms a pane, **⇧⌘I** lists
the agents waiting on you. The full keymap, and how to remap it: [docs/keyboard.md](docs/keyboard.md).
The window in detail: [docs/app.md](docs/app.md).

## Extend Harness

Every layer has a contract, a starter and a check.

| Add | Start at | The bar |
|---|---|---|
| a **domain harness**: PCB, CAD, slides, yours | [`dsh/README.md`](dsh/README.md), [`dsh/starter-dsh/`](dsh/starter-dsh/) | `harness dsh check .` |
| an **agent** as a CLI engine | [`cli/src/engines/README.md`](cli/src/engines/README.md) | the recorded-session fixtures pass |
| an **agent** as an API provider | [`provider/README.md`](provider/README.md) | the conformance runner, zero failures |
| a **terminal multiplexer** | [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-multiplexer) | `npm run test:tmux-real` |
| a **palette** or terminal theme | [`docs/extending.md`](docs/extending.md#palettes-and-appearance) | `flutter test` |
| a **keymap** | `~/.config/harness/keybindings.jsonc`, no code | it reloads on save |
| **automation** over the daemon | [`docs/cli.md`](docs/cli.md#automation) | the loopback socket answers |

**A domain harness** is a git repository: a manifest, an `AGENTS.md`, skills, a workspace template,
a toolchain that installs itself, and for the pane a viewer server and a verdict file. Harness reads
the manifest and nothing else about its code. Copy the starter, `harness dsh check .`,
`harness dsh install . --link`, and your tile is in New Agent. One registry file in a pull request
lists it for everyone. [Marp](https://github.com/autonomous-ai/autonomous-marp) is the smallest
complete one and the place to start; [Copper](https://github.com/autonomous-ai/autonomous-circuit)
and [Solid](https://github.com/autonomous-ai/autonomous-workshop) are the big ones.

**An agent** is a CLI engine, a normalizer in this repo written from a recorded session of the real
binary, or an API provider, eight JSON-RPC methods on your own infrastructure. Both are first-class:
[docs/extending.md](docs/extending.md).

## Contribute

There are more ways in than a pull request to this repo, and most of them never touch its code.

| You could | Where | What it takes |
|---|---|---|
| **Build a harness** for your domain and list it | [`dsh/README.md`](dsh/README.md) → a file in [`dsh/registry/`](dsh/registry/) | an afternoon from the starter; `harness dsh check .` green |
| **Bring your agent** as an engine or a provider | [`cli/src/engines/README.md`](cli/src/engines/README.md) · [`provider/README.md`](provider/README.md) | a recorded session of the real binary, or an endpoint that passes the conformance runner |
| **Record a session** for a bug | an issue | an engine bug is fixed from a real transcript; attach one and it is half done |
| **A palette, a terminal theme, a keymap** | [`docs/extending.md`](docs/extending.md) | one Dart value, or one JSONC file |
| **Docs** | this file and [`docs/`](docs/) | what confused you in the first five minutes is the next fix |
| **A machine, a multiplexer, a platform** | [CONTRIBUTING.md](CONTRIBUTING.md) | open an issue first so the shape is agreed |

[CONTRIBUTING.md](CONTRIBUTING.md) has the workflow, [SECURITY.md](SECURITY.md) takes security
reports, and the licence is [MIT](LICENSE).

## Docs

- [docs/app.md](docs/app.md) — sessions, panes, layouts, terminal, attention, machines
- [docs/keyboard.md](docs/keyboard.md) — the full keymap and the keymap file
- [docs/engines.md](docs/engines.md) — the fourteen engines: how each is followed, resume, bypass, grids
- [docs/architecture.md](docs/architecture.md) — daemon, session model, transport and encryption, relay, providers, the device
- [docs/cli.md](docs/cli.md) — every `harness` command, the dashboard, the loopback socket
- [docs/extending.md](docs/extending.md) — agents, multiplexers, palettes, keys, automation
- [docs/development.md](docs/development.md) — repository layout, build, test, release
- [dsh/README.md](dsh/README.md) — build a domain harness; [dsh/spec/](dsh/spec/README.md) is the contract
- [cli/](cli/README.md), [desktop/](desktop/README.md), [backend/](backend/README.md), [provider/](provider/README.md) — per-package detail
