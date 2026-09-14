# Shared swarm collaboration prototype

Open `index.html` in a browser. No build, package installation, server, or account is required.

For a local web preview, run this from the repository root and open <http://127.0.0.1:8766/>:

```sh
python3 -m http.server 8766 --bind 127.0.0.1 --directory docs/prototypes/collaboration
```

This is a disposable concept prototype. All changes stay in this directory; the Harness app is not connected or modified.

## Try it

1. **Agent A** starts with a sample comment from Alice on your prompt. Reply from your view and watch the reply appear in Alice’s view.
2. Highlight any portion of a prompt or agent output, for example **“All 3 auth tests passed”** in Agent B. Click the floating **Comment** button, type feedback, and post it. The shortcut is **Ctrl+Alt+M** or **Cmd+Option+M** after selecting text.
3. In the other view, click the new yellow highlight or the pane’s **Comments** button. Reply to the same thread. The author and reply appear in both views.
4. Select another passage to start a separate thread. Selections can span multiple entries in the same pane. Each thread keeps its exact quoted text; adding output, moving a pane, or closing and restoring it preserves the discussion.
5. Close a comment panel and click a yellow passage to reopen its thread. Reading a thread and writing a draft are local; posted comments and highlights are shared.
6. Send prompts to **any agent from either view**, including while it is working. Prompts and scripted activity appear in both views. Comments never send a prompt or trigger a simulated run.
7. Move, resize, maximize, rename, add, or close an agent pane. Both views receive the same change. **Undo removal** restores the same agent, output, and comments.
8. Open **Share** in your view. Change Alice to **Can view**: she can read comments and output but cannot post, prompt, or change the swarm. Invite another person to try joining with either permission.
9. Use **Reset demo** to start again.

## Scope

- One shared swarm with three agents and two visible participant views.
- Shared pane membership, order, size, maximized state, names, prompts, and output.
- Independent unsent drafts, text selection, keyboard focus, scrolling, and comment reading.
- Anyone with work access can message any agent or stop it. There are no control handoffs.
- Swarm-wide **Can work** and **Can view** permissions.
- Comments anchored to exact text selections, shared yellow highlights, quoted passages, author attribution, and replies. No general pane chat, notifications, or resolve workflow in this iteration.
- A pane close removes it for everyone and keeps its simulated runtime alive.

Both views render one in-memory state. This is not a networked multiplayer implementation, a terminal emulator, or a connection to real agents. Output is scripted, identities and invitations are simulated, and refreshing the page resets everything. A permission switch demonstrates the interaction; it is not a security boundary.

The fake agent processes sample responses in sequence solely to keep the demo interactive. A real integration would reuse the agent’s existing input behavior. Comments use stable transcript entry IDs and text offsets plus a saved quote. They demonstrate the interaction without attempting to map a real terminal’s cells, scrollback, or redraws.

The **Share** dialog does not send email or create a real invitation link. Real authentication, persistence, encryption, machine grants, billing, file effects, and disconnection recovery are outside this prototype.

## Files

- `index.html`: the two client shells and small dialogs.
- `styles.css`: basic layout and controls.
- `app.js`: shared state, interactions, and scripted agent runs.
- `comments.js`: text selection, passage highlights, and shared comment threads.

Keep this implementation simple while changing the collaboration concepts. It is not intended to be moved directly into production.
