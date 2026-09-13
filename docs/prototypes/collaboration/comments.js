// Comments belong to saved transcript passages, not terminal screen coordinates.
// This prototype uses DOM ranges; a real terminal would supply its selected text.
function createPaneComments({ views, viewPerson, canWork, personName, getAgent, announce, render }) {
  const panels = new Map();
  const popup = document.querySelector("#selection-comment");
  let selection = null;
  let nextThread = 1;

  function node(tag, className, text) {
    const result = document.createElement(tag);
    if (className) result.className = className;
    if (text !== undefined) result.textContent = text;
    return result;
  }
  function action(label, handler, title) {
    const result = node("button", "", label);
    result.type = "button";
    if (title) result.setAttribute("aria-label", title);
    result.addEventListener("click", handler);
    return result;
  }
  function uiFor(view, agent) {
    const key = view.root.dataset.client + ":" + viewPerson(view) + ":" + agent.id;
    if (!panels.has(key)) panels.set(key, {
      open: agent.threads.length > 0, active: agent.threads[0]?.id,
      anchor: null, text: "", replies: new Map()
    });
    return panels.get(key);
  }
  function speaker(agent, entry) {
    return entry.kind === "user" ? personName(entry.sender) + "’s prompt" : agent.engine + " output";
  }
  function thread(anchors, author, text) {
    return { id: "thread-" + nextThread++, anchors,
      quote: anchors.map(anchor => anchor.text).join("\n"),
      comments: [{ author, text, time: Date.now() }] };
  }
  function seed(agent, entry, author, text) {
    agent.threads.push(thread([{ entryId: entry.id, start: 0, end: entry.text.length,
      text: entry.text, speaker: speaker(agent, entry) }], author, text));
    agent.commentVersion++;
  }
  function open(view, agent, id) {
    const ui = uiFor(view, agent);
    ui.open = true;
    ui.active = id;
    render();
    const pane = view.panes.get(agent.id);
    pane?.querySelector('[data-thread="' + id + '"]')?.scrollIntoView({ block: "nearest" });
  }
  function toggle(view, agent) {
    const ui = uiFor(view, agent);
    ui.open = !ui.open;
    render();
  }
  function buildPanel() {
    return node("aside", "comments-panel");
  }

  function markPassages(pane, agent) {
    // Only touch transcript text when a new annotation is added, so live output
    // and replies do not disturb text selection, scroll position, or a draft.
    if (pane.annotationVersion !== agent.commentVersion) {
      for (const entry of agent.log) {
        const body = pane.querySelector('[data-entry="' + entry.id + '"] .entry-text');
        if (!body) continue;
        const anchors = agent.threads.flatMap(item => item.anchors
          .filter(anchor => anchor.entryId === entry.id)
          .map(anchor => ({ ...anchor, threadId: item.id })));
        const cuts = [...new Set([0, entry.text.length, ...anchors.flatMap(a => [a.start, a.end])])].sort((a, b) => a - b);
        const fragments = [];
        for (let i = 1; i < cuts.length; i++) {
          const start = cuts[i - 1], end = cuts[i];
          const text = entry.text.slice(start, end);
          const ids = anchors.filter(a => a.start < end && a.end > start).map(a => a.threadId);
          if (!ids.length) fragments.push(document.createTextNode(text));
          else {
            const mark = node("mark", "comment-anchor", text);
            mark.dataset.threads = [...new Set(ids)].join(" ");
            // Keep annotated text natively selectable. The pane's Comments
            // button provides keyboard access to these same threads.
            mark.title = "Open comments on this passage";
            fragments.push(mark);
          }
        }
        body.replaceChildren(...fragments);
      }
      pane.annotationVersion = agent.commentVersion;
    }
  }

  function quoteBlock(anchors) {
    const group = node("div", "comment-context");
    group.append(node("div", "quote-source", anchors.length === 1 ? anchors[0].speaker : "Selected passages"),
      node("blockquote", "comment-quote", anchors.map(anchor => anchor.text).join("\n")));
    return group;
  }
  function composer(label, value, save, submit) {
    const form = node("form", "comment-form");
    const input = node("textarea");
    input.placeholder = label;
    input.setAttribute("aria-label", label);
    input.rows = 2;
    input.maxLength = 4000;
    input.value = value;
    const send = node("button", "", label === "Add a comment" ? "Comment" : "Reply");
    send.type = "submit";
    send.disabled = !value.trim();
    input.addEventListener("input", () => { save(input.value); send.disabled = !input.value.trim(); });
    form.addEventListener("submit", event => {
      event.preventDefault();
      if (input.value.trim()) submit(input.value.trim());
    });
    form.append(input, send);
    return form;
  }

  function renderPane(view, pane, agent) {
    const ui = uiFor(view, agent);
    const writable = canWork(viewPerson(view));
    const panel = pane.querySelector(".comments-panel");
    const toggle = pane.querySelector('[data-action="comments"]');
    toggle.textContent = "Comments" + (agent.threads.length ? " " + agent.threads.length : "");
    toggle.setAttribute("aria-label", "Comments on " + agent.name + ": " + agent.threads.length);
    toggle.setAttribute("aria-expanded", String(ui.open));
    panel.hidden = !ui.open;
    panel.setAttribute("aria-label", "Comments on " + agent.name);
    pane.classList.toggle("has-comments", ui.open);
    markPassages(pane, agent);
    for (const mark of pane.querySelectorAll(".comment-anchor")) {
      mark.classList.toggle("active-anchor", ui.open && mark.dataset.threads.split(" ").includes(ui.active));
    }
    if (!pane.commentEventsBound) {
      pane.commentEventsBound = true;
      function visit(event) {
        const mark = event.target.closest(".comment-anchor");
        if (!mark || !window.getSelection()?.isCollapsed) return;
        open(view, agent, mark.dataset.threads.split(" ")[0]);
      }
      pane.addEventListener("click", visit);
    }
    const signature = JSON.stringify([viewPerson(view), ui.open, ui.active, ui.anchor, writable,
      agent.threads.map(item => [item.id, item.comments.length])]);
    if (panel.signature === signature) return;
    panel.signature = signature;
    const focused = panel.contains(document.activeElement) && document.activeElement.tagName === "TEXTAREA"
      ? { key: document.activeElement.dataset.draft, start: document.activeElement.selectionStart, end: document.activeElement.selectionEnd } : null;
    const oldScroll = panel.querySelector(".thread-list")?.scrollTop || 0;
    panel.replaceChildren();
    const header = node("div", "comments-heading");
    header.append(node("strong", "", "Comments"), action("×", () => { ui.open = false; render(); }, "Close comments"));
    panel.append(header);
    const list = node("div", "thread-list");
    if (ui.anchor && writable) {
      const draft = node("div", "thread-card new-comment");
      draft.append(quoteBlock(ui.anchor));
      const form = composer("Add a comment", ui.text, text => { ui.text = text; }, text => {
        if (!canWork(viewPerson(view))) return;
        const item = thread(ui.anchor, viewPerson(view), text);
        agent.threads.push(item);
        agent.commentVersion++;
        ui.anchor = null;
        ui.text = "";
        ui.active = item.id;
        announce(personName(viewPerson(view)) + " commented on " + agent.name + ".");
        render();
      });
      form.querySelector("textarea").dataset.draft = "new";
      form.append(action("Cancel", () => { ui.anchor = null; ui.text = ""; render(); }));
      draft.append(form);
      list.append(draft);
    }
    for (const item of agent.threads) {
      const card = node("article", "thread-card" + (ui.active === item.id ? " active-thread" : ""));
      card.dataset.thread = item.id;
      card.append(quoteBlock(item.anchors));
      card.addEventListener("click", event => {
        if (ui.active !== item.id && !event.target.closest("button, textarea")) open(view, agent, item.id);
      });
      for (const comment of item.comments) {
        const entry = node("div", "comment-entry");
        const metadata = node("div", "comment-meta");
        metadata.append(node("strong", "", personName(comment.author)),
          node("time", "", new Date(comment.time).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })));
        entry.append(metadata, node("p", "", comment.text));
        card.append(entry);
      }
      if (writable && ui.active === item.id) {
        const form = composer("Reply to thread", ui.replies.get(item.id) || "", text => ui.replies.set(item.id, text), text => {
          if (!canWork(viewPerson(view))) return;
          item.comments.push({ author: viewPerson(view), text, time: Date.now() });
          ui.replies.delete(item.id);
          announce(personName(viewPerson(view)) + " replied on " + agent.name + ".");
          render();
        });
        form.querySelector("textarea").dataset.draft = item.id;
        card.append(form);
      } else if (writable) card.append(action("Reply", () => open(view, agent, item.id)));
      list.append(card);
    }
    if (!agent.threads.length && !ui.anchor) list.append(node("p", "comments-empty",
      writable ? "Highlight text in a prompt or agent output, then click Comment." : "No comments yet."));
    panel.append(list, node("p", "comments-note", "Shared with teammates. Comments aren’t sent to the agent."));
    list.scrollTop = oldScroll;
    if (focused) {
      const input = panel.querySelector('[data-draft="' + focused.key + '"]');
      input?.focus({ preventScroll: true });
      input?.setSelectionRange(focused.start, focused.end);
    }
  }

  function readSelection() {
    const selected = window.getSelection();
    selection = null;
    popup.hidden = true;
    if (!selected?.rangeCount || selected.isCollapsed) return;
    const range = selected.getRangeAt(0);
    const parent = value => value.nodeType === Node.ELEMENT_NODE ? value : value.parentElement;
    const transcript = parent(range.startContainer)?.closest(".transcript");
    if (!transcript || parent(range.endContainer)?.closest(".transcript") !== transcript) return;
    const view = views.find(candidate => candidate.root.contains(transcript));
    if (!view || !canWork(viewPerson(view))) return;
    const agent = getAgent(transcript.closest("[data-agent]").dataset.agent);
    const anchors = [];
    for (const body of transcript.querySelectorAll(".entry-text")) {
      if (!range.intersectsNode(body)) continue;
      const part = document.createRange();
      part.selectNodeContents(body);
      if (body.contains(range.startContainer)) part.setStart(range.startContainer, range.startOffset);
      if (body.contains(range.endContainer)) part.setEnd(range.endContainer, range.endOffset);
      const text = part.toString();
      if (!text.trim()) continue;
      const prefix = document.createRange();
      prefix.selectNodeContents(body);
      prefix.setEnd(part.startContainer, part.startOffset);
      const start = prefix.toString().length;
      const entry = agent.log.find(item => item.id === body.closest("[data-entry]").dataset.entry);
      anchors.push({ entryId: entry.id, start, end: start + text.length, text, speaker: speaker(agent, entry) });
    }
    if (!anchors.length) return;
    selection = { view, agent, anchors };
    const rects = range.getClientRects();
    const rect = rects[rects.length - 1] || range.getBoundingClientRect();
    popup.style.left = Math.max(8, Math.min(rect.right - 40, window.innerWidth - 110)) + "px";
    popup.style.top = Math.max(8, Math.min(rect.bottom + 6, window.innerHeight - 42)) + "px";
    popup.hidden = false;
  }
  function startComment() {
    if (!selection || !canWork(viewPerson(selection.view))) return;
    const { view, agent, anchors } = selection;
    const ui = uiFor(view, agent);
    ui.open = true;
    ui.anchor = anchors;
    ui.active = null;
    // Keep an unfinished comment if the writer changes their selected passage.
    selection = null;
    popup.hidden = true;
    window.getSelection()?.removeAllRanges();
    render();
    const panel = view.panes.get(agent.id)?.querySelector(".comments-panel");
    panel?.querySelector(".new-comment textarea")?.focus();
  }
  popup.addEventListener("mousedown", event => event.preventDefault());
  popup.addEventListener("click", startComment);
  document.addEventListener("selectionchange", readSelection);
  document.addEventListener("pointerup", readSelection);
  document.addEventListener("keydown", event => {
    if ((event.metaKey || event.ctrlKey) && event.altKey && event.key.toLowerCase() === "m" && selection) {
      event.preventDefault();
      startComment();
    }
  });
  window.addEventListener("scroll", () => { popup.hidden = true; }, true);
  window.addEventListener("resize", () => { popup.hidden = true; });

  return { seed, toggle, buildPanel, renderPane, reset() {
    panels.clear();
    selection = null;
    nextThread = 1;
    popup.hidden = true;
    window.getSelection()?.removeAllRanges();
  } };
}
