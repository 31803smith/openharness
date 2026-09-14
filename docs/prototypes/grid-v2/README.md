# Harness × Grid study

Run and review this prototype locally. Do not publish it to Sites.

This iteration starts with one interaction: change a model from an agent terminal's header. Three panes give each agent its own selection. The header follows the app's project, branch and machine layout, with a compact model button added.

The header button shows the model and version, such as **Opus 5**. Inference providers appear in the dropdown rows. A fixed **+ Add models** action opens four ways to expand access.

## Try it

1. Click the model in any pane's header.
2. Search by model name, type, or inference provider, then pick a row: **model · type · inference provider**. The checkmark identifies the current choice.
3. That pane's header updates and the menu closes. Its terminal history and draft stay in place.
4. Send a sample message to see the new model/provider on its reply. Other panes keep their choices.
5. Click **+ Add models**, including when your search has no results. Try **Connect a subscription**, **Add an API**, **Connect local models**, or **Join shared models**. Sample form details are filled in.
6. Finish a connection to return to the same picker with a confirmation and all models from that source. Select one when ready. Adding access preserves every agent's selected model, task, history and unsent draft.

The menu is one flat, scrollable list with a fixed search bar and column headings. Search is case-insensitive and can combine terms, such as `deepseek local`. Clearing search shows all models again. For example, DeepSeek V3 appears as API from DeepSeek and Local from Autonomous.ai GPUs. The three types are **Subscription**, **API**, and **Local**; Local includes self-hosted models on personal, team, or community machines, with the provider column identifying the host.

Keyboard users can open the picker with Enter, type immediately to search, move through results with the arrow keys, select with Enter, and dismiss with Escape. Reopening the picker clears the previous search.

The demo starts with Anthropic and OpenAI subscriptions and this Mac connected (four available models). The subscription path can add a sample Google account; the API path offers DeepSeek, Anthropic, OpenAI, and a custom endpoint; local setup accepts a named model server; shared setup covers a team invitation and a public community. Local and shared server details are editable, with sample catalogs returned. Connecting an existing source does not duplicate models. Use **Reset** to restore the initial access and three agent choices.

All models, providers, machines, files and replies are illustrative. Changes are in memory and reset on reload. Setup uses sample keys, emails and URLs. Keys and emails never enter the connection catalog or WebMCP state. No real authentication, requests, billing, terminal sessions or Grid connections occur. Real provider authentication, model discovery, adapter switching and context transfer still require separate validation.

## Run locally

```sh
cd docs/prototypes/grid-v2
npm install
npm run dev -- --port 5194
```

Open the Local URL printed by the server, normally http://localhost:5194.

## Edit and check

- `app/page.tsx`: panes and per-agent state.
- `app/agent-pane.tsx`: terminal and header model control.
- `app/model-picker.tsx`: searchable model/type/provider rows.
- `app/add-models.tsx`: the four simulated setup paths.
- `app/model-access.ts`: sample discovery, connected sources and duplicate handling.
- `app/demo.ts`: example catalog and simulated state transitions.
- `app/globals.css`: workspace layout.

```sh
npx tsc --noEmit
npm run lint
npm run build
```

Lint covers the prototype and its configuration. The untouched scaffold component catalog has upstream lint findings and remains included in the full TypeScript check.

The optional WebMCP tools in `app/use-grid-tools.ts` are `get_grid_study` and `set_agent_model`. They feature-detect `document.modelContext`. No supported execution context is available here, so their live contract is unverified; the normal clickable interface remains available.
