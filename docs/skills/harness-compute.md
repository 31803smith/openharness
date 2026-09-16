# HOW TO OPERATE HARNESS COMPUTE

Harness Compute is models running on the user's own machines, under their Harness account,
reachable by any coding agent Harness drives. This file is the same for every agent — Claude
Code, Codex, Cursor, opencode — because they all read the same state through the same `grid`
commands.

The user does exactly one thing by hand: `harness login`, browser and SSO. That already signs
them into Harness Compute — there is no second sign-in, no second credential, nothing else to set
up first. Everything below, you do for them in conversation. Don't ask them to run something you
can run yourself, and don't ask them for a base URL, an API key, or a model list — nothing here
needs any of them.

Once a model is running, Harness itself puts it in every agent's **model picker** — the dropdown
at the top of an agent's pane, and the Models menu in the window. Picking it there switches that
agent to the model. You never edit an agent's config, never add a provider, never hand over a URL
or a key: the picker is the whole hand-off.

Two things the user asks for:

    1. Start a local model on this machine, so it shows up in the model picker
    2. Show what Harness Compute is doing right now

Read the section for what was asked. Don't do the other unprompted.


## Ground rules — apply everywhere, in every agent

**Talk the way Harness talks.** Short, declarative sentences. State what's true and what happens
next — don't hedge, don't soften a "no" into a maybe, don't open with "I'd be happy to" or close
with an exclamation point. Say the concrete consequence instead of a vague reassurance: not "this
should be more efficient" but name what it actually saves or costs. Second person, never third —
you're talking to the user, not describing them to someone else. When something isn't set up, say
so plainly and stop, the same way you'd report a failed build — that's not a lesser answer than
success, it's the accurate one.

**Never say the plumbing's name — and never hand the user a command either.** The commands below
shell out to a CLI called `grid` — that part cannot change, it's the real binary. But the user
never hears that word from you, and never gets a command to type or a flag to remember: not in
chat, not in a file you write for them, not in a report, not as "you can stop it with X" or
"pass --Y if you want Z." Call the whole feature **Harness Compute**, every time. Every action
this file describes is something you do when the user tells you what they want in plain words —
never something you tell them to do themselves in a terminal. If a command's own output prints
its internal name (it will), summarize what it means instead of repeating the raw line back.

**Which grid: derive it, then pass it everywhere. Never the user, never the active one.** This
computer's `grid` CLI is usually signed into several grids — a team's, a community one — and
whichever `grid use` last selected is *not* the user's. The user's own grid is the one Harness
minted at sign-in, and it is recognisable without asking anyone: its name is the user's email
local-part (lowercased, runs of non-alphanumerics → `-`, trimmed) followed by `-` and 8 hex, and
its type is `permissioned-public`. Find it once, at the start of any section:

    python3 - <<'EOF'
    import json, os, re, subprocess
    email = next(l.split('=',1)[1].strip().strip('"') for l in open(os.path.expanduser('~/.grid/credentials.toml')) if l.startswith('email'))
    slug = re.sub(r'[^a-z0-9]+', '-', email.split('@')[0].lower()).strip('-') or 'user'
    grids = json.loads(subprocess.run(['grid','ls','--json'], capture_output=True, text=True).stdout)
    print(*[g['grid'] for g in grids if g['type'] == 'permissioned-public' and re.fullmatch(rf'{re.escape(slug)}-[0-9a-f]{{8}}', g['grid'])])
    EOF

Exactly one name is the answer. Give it to **every** `grid` command as its grid argument — the
positional `[grid]` on `models`, `info`, `join`, `leave`, `stats`, `usage`, `engines`; `--grid`
on `chat`. Never rely on the active grid, never run `grid use`, never ask the user which grid —
they don't know, and there is nothing for them to choose. The name stays out of what you say:
it's an argument you pass, not a thing you mention.

No name (or more than one) means it isn't provisioned: stop and say, in plain words, "Harness
Compute isn't set up on your account yet — sign in to Harness again and it will be." Don't invent
a name or create one; a guessed name can collide with someone else's on the same shared service.

**If a command fails because the user isn't signed in**, stop and tell them to run
`harness login`. That's the only command in this whole feature that's ever theirs to run by hand.

**Ask through a tool, not through prose.** Every point in this file that says "ask" means: use
whatever structured, interactive way your own agent has of putting a question to the user — real
selectable options, a real blocking prompt — not a sentence ending in a question mark inside a
normal reply. A written question in prose is not a stop: nothing forces the turn to end there,
and the user gets a paragraph to parse instead of choices to pick. An interactive prompt is what
actually blocks until an answer comes back, and it's what turns "coding, chat, vision, or
fastest" or "go ahead?" into something the user picks rather than types out by hand. Use it for
the intent question, the model shortlist, and every yes/go-ahead confirmation before a slow step
— never substitute freeform text for any of these. If your agent has no such mechanism, the
fallback is to end your entire turn on the question and nothing else — never on a question
followed by the command that answers it.


## 1. Start a local model on this machine

Goal: this computer serves a model that becomes available to Harness Compute, so it appears in
every agent's model picker and the user can switch to it there. Five steps, in order.

**Steps 3 and 4 are a real stop, not a narrated one.** Each downloads or compiles something
multi-gigabyte-to-multi-minute on the user's machine. Ask a direct question ("this will build
llama.cpp from source, which takes a while on this hardware — go ahead?" / "this pulls 19.2 GB —
go ahead?") and end your turn there. Do not start the command in the same turn as the question,
and do not treat "here's what I'm about to do" as itself the ask — it isn't, and saying it while
the command is already running is not asking. Wait for an actual reply before running `grid
engine install` or `grid pull`. The one exception is `grid engine install` when `grid engine
status` already shows the engine installed — that's a no-op, not a step, so it never needs
confirmation.

**Step 1 — two questions, through a tool, before naming any model.** Skip either one the user
already answered in the same breath.

    "What's it for?"
      - Coding
      - Chat and writing
      - Reading images
      - Just something fast

    "How much context do you want?"
      - 32K
      - 64K
      - 128K
      - As much as fits

Suggest a default on the second based on the first — coding wants 128K (an agent burns context as
a session grows), chat is fine at 32K. Both answers are what step 4 filters on.

**Step 2 — know this machine's hardware before recommending anything.**

    grid device-info

Read `Usable ... for models` (or `usable_bytes` under `--json`) — that's the real ceiling for
what this machine can load, already adjusted for the OS/GPU's own reserve on Apple Silicon. Do
this **before** step 4's catalog, not after: a recommendation needs both halves — what step 1
asked, and what this machine can actually run. Never guess or assume a machine's specs — always
read this command's output.

**Step 3 — the engine, once per machine.** Skip straight to step 4 if `grid engine status` already
shows it installed — no question needed for a no-op. Otherwise, ask first, **through a tool**, in
its own turn:

    grid engine install llama.cpp --from-source

`--from-source` builds it (Metal on macOS, CUDA on Linux NVIDIA) and takes a while; without the
flag it downloads a prebuilt release, which is faster. Present both as the question's options,
recommend `--from-source` as the default, and stop — the command runs only after the answer comes
back, never in the message that asks.

**Step 4 — the weights.**

    grid catalog --json                             # sized for THIS machine; the table isn't
    grid pull unsloth/Qwen3.8-27B-GGUF:Qwen3.8-27B-UD-Q4_K_XL.gguf

The JSON has what the pick is made from: `runnable`, `task`, `params_b`, and a `fit` block
computed for this machine — `fit.version` (the quant that fits), `fit.size`, `fit.ctx` (the
context it can serve with), `fit.est_tok_s`. Keep entries that are `runnable`, whose `fit.ctx`
covers the context asked in step 1, and that suit the purpose (`task` for images; `fit.est_tok_s`
for "fast"). Offer 2–3, through a tool, each with size, context and speed. Pull `fit.version`'s
`pull_spec` unless the user named a quant. The download runs in the next turn, after the answer.

**Step 5 — join.**

    grid join <grid> --serve Qwen3.8-27B-UD-Q4_K_XL.gguf \
      --advertise-as Qwen3.8-27B \
      --name this-machines-display-name \
      --max-concurrency 2 \
      --ctx-size 128000

What each flag means, because two of them are easy to confuse:

  - `--serve` is the **file** step 4 saved, exactly as saved.
  - `--advertise-as` is the **model name the user sees in the picker**. Without it, the raw
    filename shows up instead, which nobody wants to read.
  - `--name` is **this machine's** display name. A different thing from `--advertise-as`: one
    names the model, the other names the computer.
  - `--max-concurrency` is how many requests this box takes at once. Keep it low (2) on a shared
    machine; higher on a dedicated GPU box.
  - `--ctx-size` is the context the user asked for in step 1 ("as much as fits" = that file's
    `fit.ctx`), never above its `fit.max_ctx`. Always pass it: left off, the engine takes a 16K
    default, and an agent's own prompt is bigger than that.

Ask before picking values not given — steps 1 and 2 already established intent and hardware, so
there's no excuse to guess here.

This returns as soon as the model is up; it keeps serving in the background. **Prove it answers
before saying it's ready** — the join's exit code and `grid stats` only show it is listed:

    grid chat --grid <grid> -m Qwen3.8-27B "say ok"

The `-m` is the `--advertise-as` name. A reply means the whole path works. No reply, or an error
about context size, means it is not ready — fix it (see "When something fails") before telling
the user anything succeeded.

Once the chat check passes, say it's ready and where to find it — the `--advertise-as` name is
what the picker shows: "Qwen3.8-27B is running on this machine. Pick it from the model dropdown
at the top of any agent's pane, or from the Models menu, and that agent switches to it." That's
the end of this section. Don't offer to wire it into this agent, edit its config, or add a
provider — Harness has already done the connecting, and the picker is the only step left.

**To stop it, don't name the command — offer to do it.** Say something like "tell me when you
want it stopped and I'll turn it off," never "stop it with `grid leave`." The user asking you to
stop it is itself the trigger: run `grid leave <grid>` yourself right then (`--all` if this box
is serving more than one model), and confirm in plain words that it's stopped. The command is
something you run, never something you hand the user to type.


## 2. Show what's running

Read-only, safe to run any time. `<grid>` is the name derived in the ground rules.

    grid stats <grid> --verbose     # uptime, memory, and a card per machine
    grid usage <grid> --by member   # who used it
    grid usage <grid> --by model    # which models did the work
    grid usage <grid> --by engine   # which machines did the work

`grid stats` without `--verbose` is just the summary block. Every one takes `--json` for
computing on the output rather than displaying it.

Two things to get right when summarizing:

  - **A `0` and a `—` are different answers.** `0` means measured and idle; `—` means nothing
    measured it at all. Don't collapse them, and don't report a `—` as zero.
  - **`input` excludes cached tokens.** `input`, `cached` and `output` are three non-overlapping
    figures that add up to the total. Don't add input and cached together.

Pick the split that answers what was actually asked, rather than dumping all four commands.


## When something fails

Say what failed and stop — don't paper over it or retry blindly. Translate every message: never
repeat a raw line that names the underlying CLI.

  - **"Not signed in"** → the user's to fix: `harness login`.
  - **"isn't up"** → Harness Compute is stopped for this account. Say so; ask before restarting
    it.
  - **404 on a model** → wrong id, or nothing is currently serving it. `grid stats <grid> --verbose`
    shows what each machine actually has loaded.
  - **`exceeds the available context size`** (an agent may show it as a garbled "expected array
    `choices`") → the model was served with too small a window, usually `--ctx-size` left off.
    Stop it and join again with the context the user asked for. The model is fine; only its
    window was too small.
  - **The user says it isn't in the picker** → it is only there while it is being served. Run
    `grid stats <grid> --verbose`; if this machine no longer lists it, start it again (section 1,
    step 5 — the weights are still on disk, nothing to pull). If it is listed, tell them to open
    the picker again; it refreshes on open.


---

*Maintainer note (not shown to the end user, ever): this is the whole skill, for every agent, for
the feature described in `docs/plans/2026-09-14-004-harness-grid-plan.md`. It deliberately drops the
generic `grid` product's multi-network `grid use`/`grid start <name>`/member-management surface
(present in `autonomous-grid/docs/opencode.txt`, sections D/E) because Harness auto-provisions
one private network per account at `harness login` and never exposes selection or naming to the
user (Change 2/2b of that plan). If that backend auto-provisioning (Change 7) isn't live yet on
the account this runs against, no grid matches the name rule — this file tells the agent to
stop and say so rather than inventing a network name, since names
are globally unique and a guessed one can collide with another user's account.

There is deliberately no "add a custom provider" section any more. The Harness app lists what the
account's grid is serving in every pane's model picker and the window's Models menu
(`grid_models_list`), and picking one retargets that agent itself (`agent_retarget` — for
opencode, by writing the model into its session and respawning). So the agent that started the
model has nothing to wire up: no base URL, no key, no config edit. Reintroducing that section
would put two paths to the same model in front of the user, and only one of them survives a
sign-in that rotates the key.*
