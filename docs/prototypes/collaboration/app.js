// A single in-memory swarm, rendered through two simulated clients.
// Agent output is scripted. This file makes no network or runtime calls.
(() => {
  "use strict";
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const views = $$(".client").map(root => ({ root, body: $(".workspace", root), panes: new Map() }));
  const drafts = new Map();
  const timers = new Set();
  let state;
  let nextAgent;
  let rightPerson;
  let runSequence = 0;
  const comments = createPaneComments({ views, viewPerson, canWork, personName, announce, render,
    getAgent: id => state.agents[id] });

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }
  function button(label, action, title) {
    const node = element("button", "", label);
    node.type = "button";
    node.dataset.action = action;
    if (title) { node.title = title; node.setAttribute("aria-label", title); }
    return node;
  }
  function member(id) { return state.members.find(person => person.id === id); }
  function personName(id) { return id === "owner" ? "Owner" : member(id)?.name || "Someone"; }
  function canWork(id) {
    const person = member(id);
    return person?.joined && person.role !== "viewer";
  }
  function viewPerson(view) { return view.root.dataset.client === "left" ? "owner" : rightPerson; }
  function draftKey(personId, agentId) { return personId + ":" + agentId; }
  function announce(message) { state.notice = message; $("#announcement").textContent = message; }
  function append(agent, kind, text, sender) {
    agent.log.push({ id: agent.id + "-line-" + agent.log.length, kind, text, sender });
  }
  function createAgent(id, name, engine, machine) {
    const agent = { id, name, engine, machine, size: "small", status: "idle", run: 0,
      log: [], threads: [], commentVersion: 0, demoInputs: [] };
    append(agent, "system", "Session ready · sample-app");
    return agent;
  }
  function schedule(fn, delay) {
    const timer = setTimeout(() => { timers.delete(timer); fn(); }, delay);
    timers.add(timer);
  }

  function reset() {
    for (const timer of timers) clearTimeout(timer);
    timers.clear();
    drafts.clear();
    nextAgent = 4;
    rightPerson = "alice";
    comments.reset();
    $("#announcement").textContent = "";
    state = {
      name: "Release", maximized: null, notice: "", removed: [],
      members: [
        { id: "owner", name: "You", role: "owner", joined: true },
        { id: "alice", name: "Alice", role: "editor", joined: true }
      ],
      order: ["a", "b", "c"],
      agents: {
        a: createAgent("a", "Agent A · implementation", "Codex", "Your Mac mini"),
        b: createAgent("b", "Agent B · tests", "Claude", "Alice’s laptop"),
        c: createAgent("c", "Agent C · review", "Codex", "Your build machine")
      }
    };
    append(state.agents.a, "user", "Rewrite the authentication module.", "owner");
    append(state.agents.a, "agent", "The expired-token check needs a regression test. Ready for the next instruction.");
    append(state.agents.b, "user", "Run the auth tests.", "alice");
    append(state.agents.b, "result", "All 3 auth tests passed. The login flow is ready for review.");
    append(state.agents.c, "agent", "Ready to review the next change.");
    comments.seed(state.agents.a, state.agents.a.log[1], "alice", "Could we narrow this to the token refresh bug?");
    for (const dialog of $$("dialog")) if (dialog.open) dialog.close();
    for (const view of views) { view.panes.clear(); view.body.replaceChildren(); buildWorkspace(view); }
    render();
  }

  function buildWorkspace(view) {
    const header = element("div", "swarm-header");
    const title = element("input", "swarm-title");
    title.setAttribute("aria-label", "Swarm name");
    title.maxLength = 50;
    title.addEventListener("blur", () => {
      const value = title.value.trim();
      if (canWork(viewPerson(view)) && value && value !== state.name) {
        state.name = value;
        announce(personName(viewPerson(view)) + " renamed the swarm.");
      }
      title.value = state.name;
      render();
    });
    title.addEventListener("keydown", event => { if (event.key === "Enter") title.blur(); });
    const tools = element("div", "swarm-tools");
    tools.append(button("Show all agents", "restore"), button("+ Agent", "add"), button("Share", "share"));
    header.append(title, tools);
    const presence = element("div", "presence");
    const notice = element("div", "notice");
    notice.append(element("span", "notice-text"), button("Undo removal", "undo"));
    const grid = element("div", "agent-grid");
    const empty = element("div", "empty", "No agents in this swarm.");
    const join = element("div", "join-screen");
    join.append(element("h2", "", "You’re invited"), element("p", "invitation"), button("Join swarm", "join"));
    view.body.append(header, presence, notice, grid, empty, join);
    if (!view.actionsBound) {
      view.actionsBound = true;
      view.body.addEventListener("click", event => {
        const control = event.target.closest("button[data-action]");
        if (!control || control.disabled) return;
        const agentId = control.closest("[data-agent]")?.dataset.agent;
        act(control.dataset.action, viewPerson(view), agentId);
      });
    }
  }

  function buildPane(view, agent) {
    const pane = element("section", "agent");
    pane.dataset.agent = agent.id;
    const header = element("div", "agent-header");
    const heading = element("div", "agent-heading");
    const name = element("input", "agent-name");
    name.maxLength = 55;
    name.addEventListener("blur", () => {
      const value = name.value.trim();
      if (canWork(viewPerson(view)) && state.order.includes(agent.id) && value && value !== agent.name) {
        agent.name = value;
        announce(personName(viewPerson(view)) + " renamed an agent.");
      }
      name.value = agent.name;
      render();
    });
    name.addEventListener("keydown", event => { if (event.key === "Enter") name.blur(); });
    heading.append(name, element("div", "agent-meta"));
    const tools = element("div", "pane-tools");
    tools.append(
      button("↑", "up", "Move pane up for everyone"),
      button("↓", "down", "Move pane down for everyone"),
      button("↕", "size", "Expand or shrink pane for everyone"),
      button("□", "maximize", "Maximize pane for everyone"),
      button("×", "remove", "Remove pane for everyone; keep agent running")
    );
    header.append(heading, tools);
    const control = element("div", "control-bar");
    const actions = element("div", "control-actions");
    actions.append(button("Stop", "interrupt"));
    const commentToggle = button("Comments", "comments", "Open comments");
    commentToggle.addEventListener("click", event => { event.stopPropagation(); comments.toggle(view, agent); });
    actions.append(commentToggle);
    control.append(element("span", "control-label"), actions);
    const transcript = element("div", "transcript");
    transcript.setAttribute("role", "log");
    transcript.setAttribute("aria-live", "off");
    const form = element("form", "prompt-form");
    const input = element("textarea");
    input.rows = 2;
    const send = element("button", "send", "Send");
    send.type = "submit";
    form.append(input, send);
    input.addEventListener("input", () => {
      drafts.set(draftKey(viewPerson(view), agent.id), input.value);
      updateSend();
    });
    function updateSend() {
      send.disabled = !input.value.trim() || !canWork(viewPerson(view));
    }
    function submit(event) {
      event.preventDefault();
      if (sendPrompt(viewPerson(view), agent.id, input.value)) {
        input.value = "";
        drafts.delete(draftKey(viewPerson(view), agent.id));
        updateSend();
      }
    }
    form.addEventListener("submit", submit);
    input.addEventListener("keydown", event => {
      if (event.key === "Enter" && !event.shiftKey && !event.isComposing) submit(event);
    });
    const main = element("div", "agent-main");
    main.append(transcript, form);
    const conversation = element("div", "pane-conversation");
    conversation.append(main, comments.buildPanel(view, agent));
    pane.append(header, control, conversation);
    pane.refreshSend = updateSend;
    pane.renderedEntries = 0;
    return pane;
  }

  function renderPane(view, pane, agent, index) {
    const personId = viewPerson(view);
    const writable = canWork(personId);
    pane.classList.toggle("large", agent.size === "large");
    pane.classList.toggle("maximized", state.maximized === agent.id);
    pane.hidden = Boolean(state.maximized && state.maximized !== agent.id);
    pane.setAttribute("aria-label", agent.name);
    const name = $(".agent-name", pane);
    if (document.activeElement !== name) name.value = agent.name;
    name.disabled = !writable;
    name.setAttribute("aria-label", "Name of " + agent.name);
    $(".agent-meta", pane).textContent = agent.engine + " · " + agent.machine;
    $(".pane-tools", pane).hidden = !writable;
    $('[data-action="up"]', pane).disabled = index === 0;
    $('[data-action="down"]', pane).disabled = index === state.order.length - 1;
    $('[data-action="size"]', pane).title = agent.size === "large" ? "Shrink pane for everyone" : "Expand pane for everyone";
    $('[data-action="maximize"]', pane).textContent = state.maximized === agent.id ? "▣" : "□";
    $(".control-label", pane).textContent = agent.status === "working" ? "Working" : "Ready";
    $('[data-action="interrupt"]', pane).hidden = !writable || agent.status !== "working";
    const log = $(".transcript", pane);
    log.setAttribute("aria-label", agent.name + " shared output");
    const atBottom = log.scrollHeight - log.clientHeight - log.scrollTop < 28;
    const selection = window.getSelection();
    const selectingText = selection && !selection.isCollapsed && log.contains(selection.anchorNode);
    for (let i = pane.renderedEntries; i < agent.log.length; i++) {
      const entry = agent.log[i];
      const line = element("div", "entry entry-" + entry.kind);
      line.dataset.entry = entry.id;
      if (entry.kind === "user") {
        line.append(element("span", "sender", personName(entry.sender) + " › "));
      }
      line.append(element("span", "entry-text", entry.text));
      log.append(line);
    }
    if (!selectingText && pane.renderedEntries !== agent.log.length && (atBottom || pane.renderedEntries === 0)) log.scrollTop = log.scrollHeight;
    pane.renderedEntries = agent.log.length;
    const input = $(".prompt-form textarea", pane);
    if (input.dataset.person !== personId) {
      input.value = drafts.get(draftKey(personId, agent.id)) || "";
      input.dataset.person = personId;
    }
    input.disabled = !writable;
    input.placeholder = writable ? "Message this agent…" : "View only";
    input.setAttribute("aria-label", "Prompt " + agent.name);
    $(".send", pane).title = "Send prompt · Shift+Enter for a new line";
    pane.refreshSend();
    comments.renderPane(view, pane, agent);
  }

  function render() {
    const select = $("#teammate-select");
    const people = state.members.filter(person => person.id !== "owner");
    if (select.options.length !== people.length) {
      select.replaceChildren(...people.map(person => {
        const option = element("option", "", person.name);
        option.value = person.id;
        return option;
      }));
    }
    select.value = rightPerson;
    for (const view of views) {
      const person = member(viewPerson(view));
      const body = view.body;
      const joined = person?.joined;
      const writable = canWork(person.id);
      const title = $(".swarm-title", body);
      if (document.activeElement !== title) title.value = state.name;
      title.disabled = !writable;
      $('[data-action="share"]', body).hidden = person.role !== "owner";
      $('[data-action="add"]', body).hidden = !writable;
      $('[data-action="restore"]', body).hidden = !state.maximized || !writable;
      $(".presence", body).textContent = state.members.filter(p => p.joined).map(p => personName(p.id)).join(" · ") + "   /   " + (person.role === "owner" ? "Owner" : person.role === "editor" ? "Can work" : "Can view");
      const notice = $(".notice", body);
      notice.hidden = !state.notice || !joined;
      $(".notice-text", notice).textContent = state.notice;
      $('[data-action="undo"]', notice).hidden = !state.removed.length || !writable;
      const grid = $(".agent-grid", body);
      grid.hidden = !joined;
      $(".empty", body).hidden = !joined || state.order.length > 0;
      $(".join-screen", body).hidden = Boolean(joined);
      $(".invitation", body).textContent = "You were invited to " + state.name + " with " + (person.role === "viewer" ? "view" : "work") + " access.";
      for (const [id, pane] of view.panes) {
        if (!state.order.includes(id)) { pane.remove(); view.panes.delete(id); }
      }
      state.order.forEach((id, index) => {
        let pane = view.panes.get(id);
        if (!pane) { pane = buildPane(view, state.agents[id]); view.panes.set(id, pane); }
        if (grid.children[index] !== pane) grid.insertBefore(pane, grid.children[index] || null);
        renderPane(view, pane, state.agents[id], index);
      });
    }
  }

  function sendPrompt(personId, id, rawText) {
    const agent = state.agents[id];
    const text = rawText.trim();
    if (!text || !state.order.includes(id) || !canWork(personId)) return false;
    append(agent, "user", text, personId);
    announce(personName(personId) + " sent a prompt to " + agent.name + ".");
    agent.demoInputs.push(text);
    if (agent.status !== "working") simulateNextTurn(agent);
    render();
    return true;
  }

  // A tiny fake engine so the prototype responds. Real agents own their existing input behavior.
  // The shared composer always sends; it has no controller or collaboration queue UI.
  function simulateNextTurn(agent) {
    const text = agent.demoInputs.shift();
    if (!text) return;
    agent.status = "working";
    agent.run = ++runSequence;
    const run = agent.run;
    const test = /test|regression|verify/i.test(text);
    const steps = test
      ? ["Checking the test setup…", "$ pnpm test -- auth", "Demo result: 3 tests passed. Ready for review."]
      : ["Inspecting the relevant files…", "Preparing a change and checking the result…", "Demo result: work prepared. Ready for your next instruction."];
    steps.forEach((line, i) => schedule(() => {
      if (agent.run !== run || agent.status !== "working") return;
      append(agent, i === steps.length - 1 ? "result" : "agent", line);
      if (i === steps.length - 1) {
        agent.status = "idle";
        simulateNextTurn(agent);
      }
      render();
    }, [450, 1450, 3000][i]));
  }

  function removePane(personId, id) {
    if (!canWork(personId) || !state.order.includes(id)) return;
    const agent = state.agents[id];
    const index = state.order.indexOf(id);
    state.removed.push({ id, index });
    state.order.splice(index, 1);
    if (state.maximized === id) state.maximized = null;
    announce(personName(personId) + " removed " + agent.name + " for everyone. The agent keeps running.");
    render();
  }

  function act(action, personId, id) {
    const agent = state.agents[id];
    if (action === "join") {
      member(personId).joined = true;
      announce(personName(personId) + " joined " + state.name + ".");
      render();
      return;
    }
    if (action === "share") {
      if (member(personId)?.role !== "owner") return;
      renderMembers();
      $("#invite-error").textContent = "";
      $("#share-dialog").showModal();
      return;
    }
    if (!canWork(personId)) return;
    if (id && !state.order.includes(id)) return;
    if (action === "add") {
      const newId = "agent-" + nextAgent++;
      const name = "Agent " + (nextAgent - 1);
      state.agents[newId] = createAgent(newId, name, "Codex", personName(personId) + "’s machine");
      state.order.push(newId);
      state.maximized = null;
      announce(personName(personId) + " added " + name + " for everyone.");
    } else if (action === "restore") state.maximized = null;
    else if (action === "undo") {
      const removed = state.removed.pop();
      if (!removed || state.order.includes(removed.id)) return;
      state.order.splice(Math.min(removed.index, state.order.length), 0, removed.id);
      announce(personName(personId) + " restored " + state.agents[removed.id].name + " for everyone.");
    } else if (action === "remove") {
      removePane(personId, id);
      return;
    } else if (action === "up" || action === "down") {
      const index = state.order.indexOf(id);
      const next = index + (action === "up" ? -1 : 1);
      if (next < 0 || next >= state.order.length) return;
      [state.order[index], state.order[next]] = [state.order[next], state.order[index]];
      announce(personName(personId) + " moved " + agent.name + " " + action + " for everyone.");
    } else if (action === "size") {
      agent.size = agent.size === "large" ? "small" : "large";
      announce(personName(personId) + " resized " + agent.name + " for everyone.");
    } else if (action === "maximize") {
      state.maximized = state.maximized === id ? null : id;
      announce(state.maximized ? personName(personId) + " maximized " + agent.name + " for everyone." : "All agents are visible again.");
    } else if (action === "interrupt" && agent.status === "working") {
      agent.run = ++runSequence;
      agent.status = "idle";
      agent.demoInputs = [];
      append(agent, "system", personName(personId) + " stopped the agent.");
      announce(personName(personId) + " stopped " + agent.name + ".");
    }
    render();
  }

  function renderMembers() {
    const list = $("#member-list");
    list.replaceChildren();
    for (const person of state.members) {
      const row = element("div", "member");
      row.append(element("span", "member-name", person.name + (person.joined ? "" : " · invited")));
      if (person.role === "owner") row.append(element("span", "member-role", "Owner"));
      else {
        const select = element("select");
        select.setAttribute("aria-label", person.name + " permission");
        for (const [value, label] of [["editor", "Can work"], ["viewer", "Can view"]]) {
          const option = element("option", "", label); option.value = value; select.append(option);
        }
        select.value = person.role;
        select.addEventListener("change", () => {
          person.role = select.value;
          announce(person.name + " now has " + (person.role === "viewer" ? "view" : "work") + " access.");
          render();
        });
        row.append(select);
      }
      list.append(row);
    }
  }
  $("#invite-form").addEventListener("submit", event => {
    event.preventDefault();
    const name = $("#invite-name").value.trim();
    if (!name) return;
    if (state.members.some(person => person.name.toLowerCase() === name.toLowerCase())) {
      $("#invite-error").textContent = "That person is already in this demo.";
      return;
    }
    const person = { id: "person-" + state.members.length, name, role: $("#invite-role").value, joined: false };
    state.members.push(person);
    rightPerson = person.id;
    $("#invite-name").value = "";
    $("#share-dialog").close();
    announce("Owner invited " + name + " to " + state.name + ".");
    render();
  });
  $$("[data-close-dialog]").forEach(control => control.addEventListener("click", () => control.closest("dialog").close()));
  $("#teammate-select").addEventListener("change", event => { rightPerson = event.target.value; render(); });
  $("#reset-demo").addEventListener("click", reset);
  reset();
})();
