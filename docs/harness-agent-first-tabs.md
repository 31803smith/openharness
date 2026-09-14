# Agent-first entry

Users start with an agent and group agents when useful. A tab holds one or
several agents without a separate swarm creation flow.

## New Agent

The plus button and Cmd-T open **New Agent**, a new tab that lets the user
choose existing work or create a fresh agent. First launch uses this same page.

The welcome page has exactly two sections:

- **Find an agent**: a focused search field for agents, machines, and projects.
- **Create a new agent**: a **Create Agent** button opening the existing local-first
  machine, engine, and working-folder flow.

Machine and project directories and recent-agent lists are removed from the
welcome page. Machines and projects remain grouped search results. Search shows
one full-width result list, without terminal output or group previews.

There is no Navigate action, compass button, or Cmd-P directory. Command search
remains on Shift-Cmd-P and stays in command mode when its query is cleared.
Typing `>` in the agent search also finds commands.

Selecting an existing agent opens it in the new tab and reuses its runtime.
**Add Agent** and split right/down choose or create agents within the current tab.
Actions that directly start a fresh agent are labeled **Create Agent**.

## Tabs and menus

One agent shows its engine mark; multiple agents use the group mark. Returning
to one restores the engine mark. Tab names remain editable. Former default names
`New swarm` and `New tab` restore as `New Agent`.

The macOS menus are **Harness, Agent, Edit, View, History, Models, Window, Help**.
Agent contains New Agent, Add Agent, Create Agent, split and pane controls,
Rename Tab, Close Agent Pane, Close Tab, Link Machine, and Add Project.

Cmd-T opens New Agent, Cmd-N opens Add Agent, Shift-Cmd-N opens Create Agent,
Cmd-W closes the tab, and Shift-Cmd-W closes the focused pane. Closing views
keeps agent runtimes alive. The stored layout format and internal command IDs
remain compatible; product language uses agents, tabs, and groups.
