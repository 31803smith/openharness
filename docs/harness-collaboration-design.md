# Shared swarms in Harness

Harness should make a swarm a shared place to work with a small group of persistent agents. A teammate opens a link, understands the work, and contributes. **One shared swarm has one shared state:** everyone sees the same agent panes, arrangement, content, and changes.

The proposed product contract has five rules:

1. **Share a swarm.** One invitation gives someone access to the work gathered there.
2. **Watch or work.** Reviewers can read and comment. Collaborators can operate and contribute agents.
3. **Work in parallel.** Several people can operate different agents. Each agent has one person controlling input at a time.
4. **Edit the same swarm.** Adding, closing, moving, resizing, renaming, or maximizing a pane changes the shared arrangement for everyone.
5. **Leave useful context.** Shared notes, comments, and results remain available when teammates return.

This is a design for trusted engineering teams, informed by the repository and official documentation reviewed on September 13, 2026. The shared arrangement is the chosen direction. Multi-user swarms, browser invitations, and durable shared discussion still require implementation; they are not claims about the current app. Product documentation establishes the comparison platforms' behavior; the remaining recommendations should be validated with developers.

## Lessons from the five collaboration models

| Platform | Observed model | Recommendation for Harness |
| --- | --- | --- |
| **Figma** | A link opens a shared file. File permissions distinguish viewing, which includes commenting and following, from editing. Access permissions and product seats are separate. [Figma sharing](https://help.figma.com/hc/en-us/articles/1500007609322-Guide-to-sharing-and-permissions) | Make the swarm the object someone shares. Synchronize edits to its contents and arrangement, show who is present, and make the invitation's capabilities and cost understandable together. |
| **Google Docs** | Viewer, Commenter, and Editor are distinct roles. Suggestions allow a contribution to be considered before changing the document; version history identifies changes and supports restoration. [Sharing](https://support.google.com/drive/answer/2494822?hl=en), [suggestions](https://support.google.com/docs/answer/6033474?hl=en-8), [history](https://support.google.com/docs/answer/190843?hl=en) | Let someone contribute feedback without operating an agent. Attribute human actions. Preserve the distinction between a suggestion, an instruction, and an executed action. |
| **GitHub** | Pull requests gather discussion, commits, checks, and diffs around a proposed change. Repository roles distinguish contributing from administering access. [Pull requests](https://docs.github.com/en/pull-requests/reference/pull-requests), [repository roles](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization) | Give teammates evidence they can inspect independently. Keep routine contribution easy and membership administration explicit. Link to the team's existing code review process. |
| **Notion** | Guests can be invited to a specific page. Editing can be granted without permission to reshare it. Comments attach to a page or particular content and can be resolved and reopened. [Sharing](https://www.notion.com/help/sharing-and-permissions), [comments](https://www.notion.com/help/comments-mentions-and-reminders) | Make a swarm understandable to someone arriving later. Keep its purpose and discussion with the work. Inviting someone to one swarm should not require adding them to an entire company workspace. |
| **Slack** | Channels organize conversation by purpose. Public channels are discoverable within a workspace; private channels require membership. Threads contain focused discussion, with notifications normally following participation or mentions. [Channels](https://slack.com/help/articles/360017938993-What-is-a-channel), [threads](https://slack.com/help/articles/115000769927-Use-threads-to-organize-discussions) | Give a swarm a clear purpose and durable discussion. Direct attention to a relevant question or reply. Begin with explicit invitations; broader team discovery can follow later. |

The common pattern is a stable place, an understandable audience, a useful way to contribute, and enough retained context to return. Presence makes live work easier. The shared object and its history make collaboration useful when nobody else is there. That synthesis is a design judgment, not a claim that these features alone caused the platforms' commercial success.

Their complexity also offers lessons. Figma separates seats from permissions; Notion supports inherited permissions and respects the broadest applicable grant; GitHub has five standard repository roles. Those mechanisms serve large organizations, but Harness's initial invitation does not need to expose a comparable hierarchy. Start with one swarm audience and two contribution levels.

There is direct competitive overlap to acknowledge. Slack now documents **Slack Code**, which is rolling out gradually: temporary code channels let teammates prompt supported agents, pause a response, and discuss generated artifacts. Multiplayer agent work already extends beyond conventional chat. Harness's proposed differentiation is direct access to persistent sessions across real environments, with several engines and a clear human handoff. Whether teams value that enough to adopt another product needs testing. [Slack Code](https://slack.com/help/articles/54310833022355-Build-with-AI-as-a-team-using-Slack-Code)

## The unit of sharing

A swarm contains its name, an optional short purpose, agent panes in a shared arrangement, and discussion. A link opens that swarm in its current state. It does not require a new project, a task board, a lead agent, or an organization setup flow.

An agent remains a real session with its original machine, environment, and model account. Adding it to a swarm does not copy its process, migrate its files, merge its context with other agents, or make the agents coordinate automatically. This extends the existing product thesis and the current separation between a swarm arrangement and a running session. [R1](../../harness-new-ui/research/harness-browser-thesis.md), [R2](../desktop/lib/state/swarm.dart)

| Shared state | What everyone sees |
| --- | --- |
| Swarm name and purpose | The same title and description |
| Agent panes | The same agents in the swarm; additions and removals update everyone's swarm |
| Pane arrangement | The same order, sizes, positions, and maximized pane |
| Agent content | The same submitted instructions and available output |
| Comments, saved excerpts, and links | The same discussion, results, and resolved state |
| Membership and control | The same participants, roles, and current controller for each agent |

When Alice sends a prompt to Agent A, everyone in the swarm sees that submitted prompt and the same live execution in Agent A's pane. For example, Alice submits “Fix the login bug and run the tests”; Sam sees her instruction, the agent's reported work as it happens, and its results. Structured prompts identify Alice as the sender. The original host executes the accepted instruction once and distributes that session's output and activity to all participants. Joining or receiving those updates must never start another execution.

Adding an agent adds its pane to everyone's swarm immediately. Moving or resizing it updates everyone's arrangement. Closing it removes it from everyone's swarm, with Undo, while its underlying process continues. A new participant and a returning participant both receive the current shared state. There is no separate per-person pane list or hidden roster to manage.

Keyboard focus, text selection, scrolling, and unsent composer drafts remain local interaction state, as in a collaborative editor. Once input is sent to the session, its resulting terminal echo and activity are shared. Closing an application window or leaving the swarm also remains a local action. These do not create a separate copy of the swarm's content or arrangement.

After an agent is shared, interactions with that same session remain visible to its authorized observers wherever its contributor operates it, including from a private swarm.

For the first multiplayer release, give each live agent **one shared swarm**. It may still appear in several personal swarms as it does today. This deliberate initial limit keeps the controlling audience understandable and avoids one room's discussion silently affecting another room's live agent. An attempted second share should offer to open the existing shared swarm or create a separate agent. Broader sharing can be reconsidered when there is demonstrated demand and an understandable account of overlapping access.

## The invitation and Alice's first minute

The Share dialog asks for a person and one role:

| Role in Share | Short explanation |
| --- | --- |
| **Can work** | Use agents, edit the shared swarm, and comment. |
| **Can review** | Watch shared agents and comment. |

Default to **Can work** for a named teammate invitation in this trusted-team product. Keep the explanation visible before the owner sends it. The swarm creator is its owner and manages people, roles, ownership transfer, and archival; Owner is not another everyday invitation choice.

Start with **Only invited people**. Copying a normal swarm link does not grant access. An invited person can accept; another person can request access. Acceptance establishes a named identity, without a requirement to create a team, enter payment details, configure a model provider, or connect a computer.

The intended join experience works in a browser. Alice can inspect output, comment, and operate an already shared agent there. Opening in the native app is optional. Connecting her own computer is needed only when she wants to contribute an agent from it. This browser experience requires development beyond the current desktop onboarding and must be included in the estimate, rather than promised as an existing path.

A concrete first visit:

1. The owner shares **Release** with Alice as **Can work**.
2. Alice opens the invitation and signs in. She lands in Release, with its purpose, shared agents, and the latest shared note available. The note might say: “Retry fix is ready; please check the regression,” with a pull request link.
3. Alice inspects the test agent's pane in the same arrangement Sam sees. A small label says **Sam is controlling** if Sam is operating it. Watching sends no agent input.
4. She comments on the relevant test excerpt, takes control of an available agent, or requests Sam's control. Sam can continue on another agent while Alice works.
5. If she wants a separate implementation approach, she adds an agent from her own connected environment. Its pane appears in everyone's swarm without a new invitation. If she moves or resizes it, everyone sees that change.
6. Before leaving, she posts the result or next question in a comment. The next visitor can find that context alongside the agent and its output.

The swarm owner should not need to be present for an already invited teammate to join. Live interaction still requires the agent's host to be available. Shared notes and saved excerpts should remain readable independently of that host.

## What Alice can do

| Action | Can review | Can work |
| --- | --- | --- |
| Watch available output and read shared context | Yes | Yes |
| Comment, mention a teammate, and reply | Yes | Yes |
| Scroll, select text, or leave the swarm | Yes | Yes |
| Move, resize, or maximize a pane in the shared layout | No | Yes; the change applies to everyone |
| Send instructions, answer an agent's question, or use its terminal | No | Yes, while controlling that agent |
| Interrupt or end the running agent | No | Yes, while controlling it; ending a session is explicit |
| Add an existing agent she is entitled to share | No | Yes |
| Create an agent on her own connected machine | No | Yes |
| Close an agent pane | No | Yes; removed for everyone, and the process continues |
| Change the swarm name, purpose, or shared links | No | Yes |
| Invite or remove people, change roles, transfer ownership, archive the swarm | No | Owner only |

This intentionally removes per-person, per-agent role settings from the everyday experience. A contributor shares an agent with the swarm's audience: reviewers can observe it and collaborators can operate it. The contributor authorizes that scope when sharing the agent, including future members admitted by the swarm owner. A contributor can withdraw their own agent at any time.

Starting a fresh agent through Harness on somebody else's computer is outside the initial invitation. A contributor starts it there and shares it, or Alice uses her own connected machine. A future team runtime could make creation a team capability with an explicit payer, but it should not create another permissions panel in the first release.

**Operating an agent is a real delegation of its capabilities.** A collaborator who can use its shell or tools may read files, spend model credits, alter code, or end processes using that environment's existing privileges. Hiding a launch, delete, or billing button does not establish isolation from commands executed inside the session. Microsoft documents the same fundamental issue for Live Share's writable terminals, although its terminals allow simultaneous writers. Harness's single-controller rule is a coordination choice, not a security sandbox. [Live Share security](https://learn.microsoft.com/en-us/visualstudio/liveshare/reference/security)

The contributor retains authority over the host and can stop sharing or stop the runtime. The swarm owner controls membership. Those responsibilities should appear where they matter, such as the Share dialog and agent details, without requiring people to configure a second role system.

## Input and handoffs

Most parallel work should happen on different agents. When people work with the same agent, use a visible, exclusive right to send input. The agent can continue running between human interactions.

| Agent input state | What Alice sees | What an action does |
| --- | --- | --- |
| Nobody is controlling | **Take control** | Acquires control if it is still available; then enables input. |
| Sam is controlling | **Sam is controlling · Request control** | Sends Sam a handoff request; Alice remains able to watch and comment. |
| Alice is controlling | **You're controlling · Release** | Lets Alice type, paste, answer, or interrupt. Release ends her input control. |
| Connection is lost | **Disconnected** with retained output | Disables input. Drafts remain personal until a fresh connection and deliberate send. |

Opening, focusing, joining, following, or reconnecting must never displace another controller. Requests do not forcibly seize control. A controller can hand over or release; the host owner has an explicit recovery action. If a controller disappears, its host-enforced lease expires, after which another authorized collaborator can claim control. A timeout is never permission to replay queued instructions.

Control is attached to the actual agent runtime across every swarm and client. A role downgrade or revocation invalidates that person's input authority. Every agent-execution route must obey the same rule, including terminal input, uploads, question responses, interrupts, and runtime actions. Shared layout edits require the swarm's edit permission; they do not require taking over an agent's input. Permission checks only in the visible terminal widget would be insufficient.

Store one canonical terminal size per shared pane. Resizing that pane is a shared layout edit, and the host applies its resulting terminal dimensions once. An accepted shared resize affects the person currently typing as well as observers. Merely joining from a smaller display or resizing an application window must not produce competing terminal resize requests. Each client renders the same logical layout within its available display; scrolling retained output and selecting text remain local.

Record who held control and who performed explicit Harness actions. For structured prompts, record the sender with the submitted instruction. For raw terminal input, the reliable evidence is the authenticated controller and accepted input sequence; do not invent semantic task authorship or change Git commit identity behind the developer's back.

Figma's engineering account describes conflict resolution and multiplayer undo over document state. That is useful background for shared swarm state, but arbitrary agent instructions can cause external effects that cannot be merged or undone as document edits. Harness should serialize control of those effects and use ordinary versioned updates for the shared arrangement. It does not need collaborative character editing of prompt drafts to validate this product. [Figma multiplayer engineering](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/)

Apply layout changes to stable pane identities. Concurrent changes to different panes should both survive; conflicting changes to the same property follow the authoritative accepted order. A stale move or resize cannot recreate a closed pane. Undo reverses an attributable arrangement edit without rewinding everyone else's work. Reconnection loads the latest shared state instead of restoring an old per-person layout over it.

## Closing, removing, and stopping

These actions need distinct names and behavior:

| Action | Effect |
| --- | --- |
| **Close pane** — the pane's × action | Removes the pane and its agent from the shared swarm for everyone. Its process remains on the host. |
| **Close swarm tab** | Leaves the swarm in this person's app. Membership and the shared arrangement remain. |
| **Stop sharing** — available to the agent contributor | Withdraws that agent's grant to the swarm. Other members cannot undo the contributor's decision. |
| **End session** — explicit runtime action | Ends the agent process; requires control and confirmation. Saved discussion remains. |

A normal pane close should offer Undo while the original contributor's grant remains valid. Confirm a close that would displace another active controller, and name that person. Undo cannot restore withdrawn access, revive a terminated process, or reverse commands already run. The pane close control should say **Remove from swarm for everyone** in its accessible label or tooltip; reviewers cannot invoke it. There is no separate **Hide for me** action.

Removing an agent or stopping its live sharing leaves comments and excerpts already posted to the swarm in its shared record. Make that distinction visible in the action's explanation.

Removing a person revokes their swarm access, including open streams and future encrypted content. Their previously shared comments remain attributed. Agents they personally contributed should be withdrawn as part of removal, leaving the original processes intact; the membership dialog must show that consequence. Team-owned runtimes can provide continuity beyond any one person's membership in a later phase.

Archiving a swarm preserves its discussion and saved excerpts for authorized members, and ends its live agent grants. It does not terminate agents. Reopening an archive does not silently restore withdrawn grants; contributors must share those agents again. Ownership transfer changes swarm administration, not the ownership of contributed computers or model accounts. The owner must transfer or archive before leaving.

## Context that survives the meeting

Begin with an optional one-sentence purpose and a small comments surface available on demand. A comment can refer to the swarm, a specific agent, a selected output excerpt, or a link such as a pull request. Mentions and replies make it useful both during a session and the next morning.

An output comment must retain an immutable excerpt with its agent identity and time. A terminal screen coordinate is an unreliable anchor because the screen is overwritten and rewrapped. If more source history remains available, the comment can also lead back to it. Clearly label a saved excerpt versus live output.

On return, offer the latest shared note, unread mentions and replies, and unresolved discussion. Agent states should report verified facts such as a pending question or unavailable host. An agent saying it finished does not establish that its change passed review. Automatic summaries and a comprehensive replay of all activity can wait until the basic context is useful and dependable.

Keep human discussion separate from agent input. A comment is not automatically sent to an agent. A collaborator who wants to use a comment as an instruction explicitly sends it while controlling that agent. Resolving a thread marks the discussion resolved; it neither approves a tool action nor merges code.

Use GitHub links for detailed review, checks, and merge decisions. Harness membership does not itself issue repository permissions. An operated agent still acts using its environment's credentials, which may be more powerful than Alice's personal GitHub account; the UI must not suggest otherwise. The team's repository rules and credential setup remain relevant.

Notifications should begin with mentions, replies to participated threads, and direct handoff requests. Other agent activity stays available in the swarm and existing attention/search surfaces. Do not add a second company chat, a mandatory activity dashboard, or notifications for every generated line.

## Sharing an existing private agent

Sharing a live agent is different from sharing a screenshot of it. Before the contributor publishes it, show the destination swarm, its current audience, the agent's host, and what output will become available. Explain that collaborators can use the agent's existing capabilities and model account.

Do not offer a misleading guarantee that sharing “from now on” hides earlier context. The current terminal screen, retained output, model conversation, files, and future agent responses can expose earlier work. For a clean collaboration boundary, offer **Start a new shared agent** with deliberately selected context. A saved excerpt is the smaller option when only feedback is needed.

The runtime's original account continues to fund model usage. If the payer cannot be verified, say so rather than guessing. Granting a collaborator access does not copy model API keys into their app or create an independent model subscription, but commands executed in the shared environment still have that environment's privileges.

## What the current repository supports

The current `Swarm` model already separates membership from process ownership and reuses a session across views. Its serialized state includes membership, focus, zoom, and layout. Multiplayer should synchronize agent membership and the durable arrangement, including pane order, dimensions, and maximized state, as one authoritative swarm document. Keep only transient interaction state such as keyboard focus and scrolling local. Do not introduce separate participant layouts or hidden pane memberships. [R2](../desktop/lib/state/swarm.dart)

The terminal stream manager currently closes an incumbent stream when a later client opens the same terminal, then assigns the controller. This supports the current single-user arrangement but is not a many-observer collaboration protocol. The desktop terminal state also assumes a controlling connection. The next foundation is independent read subscriptions plus explicit, host-enforced input control. [R3](../cli/src/lib/terminalStreamManager.ts#L276), [R4](../desktop/lib/terminal/terminal_session.dart)

Machine listing is currently scoped to a user, and fetching a machine's owner data is restricted to its owner or an administrator. A swarm invitation must introduce a scoped collaborator path; it must not return the machine owner's API key or reuse an unrestricted machine link. Harness's listing and metadata APIs should expose only the agents and details granted to that collaborator. This API boundary does not restrict what a writable session can discover through its own tools. [R5](../backend/src/services/MachineService.ts#L490)

The desktop uses the local CLI for normal authentication and machine transport. Relayed terminal control is pairwise end-to-end encrypted. Browser participation and encrypted shared history require a deliberate identity and key-distribution design, including invitation acceptance while the owner is absent, host enforcement, and revocation. Do not weaken the existing relay confidentiality to implement comments or summaries. [R6](../desktop/CLAUDE.md#L88), [R7](../cli/src/lib/e2ee/core.ts#L379)

The app's current browsing history is bounded, session-local navigation history; it does not establish a durable team record. Shared metadata, comments, and selected excerpts need their own persistence and retention contract. While a host is offline, the browser should show saved shared context and clearly stale output, rather than imply that an agent is live or has migrated elsewhere. [R8](harness-v2-progress.md)

The implementation can remain conceptually small: one shared swarm document, memberships, scoped agent grants, persistent comments/excerpts, and transient control leases. Authorization and encryption still need careful implementation. Revocation governs future access; it cannot remove information a former participant has already received or copied. Changing read keys alone also cannot enforce a reviewer's lack of write permission: the host must verify the authenticated sender and current grant on every action.

## A complete first pilot

Build one end-to-end journey: an invited Alice can join in a browser, see the same swarm as Sam, understand a shared agent, leave a useful comment, edit the arrangement, operate an agent through an explicit handoff, and return later to the current shared work. The native app preserves its fast navigation while adopting the shared arrangement for shared swarms.

The pilot needs invitation and revocation, the two roles, quiet presence, observer streams, input handoff, contribution of an agent from an already connected host, synchronized pane edits with Undo, and durable comments with selected excerpts. Implement the stream and authorization foundation first, then exercise the full journey. A desktop-only internal experiment can validate control sooner, but it does not validate the intended low-friction browser invitation.

Leave shared cloud compute, creation on other people's hosts, cross-swarm live sharing, public discovery, co-editing drafts, automatic agent coordination, audio/video, and custom permission roles for later. Those are independent product bets and are unnecessary to learn whether developers want to work this way.

Try the complete experience with a few real engineering pairs on real tasks. The central product test is whether Alice can make a useful contribution without the owner explaining the interface or reconstructing the context in Slack. Observe her understanding of where commands execute, who pays, what closing does, and whether a comment will reach an agent. These are proposed tests, not measured outcomes.

Before expanding the pilot, verify the cases where apparently simple collaboration can fail:

| Scenario | Required behavior |
| --- | --- |
| Alice joins while Sam types | Sam's control and terminal geometry remain unchanged. |
| Alice submits a prompt to Agent A | Everyone sees her submitted prompt and the same agent output and reported actions; the host accepts a single execution. |
| Another participant joins while Agent A is working | They observe the existing execution; joining never resubmits its prompt. |
| Two people claim control together | Only one receives a valid input lease. |
| Two participants operate different agents | Their input remains independent; shared arrangement edits still synchronize. |
| Alice adds, moves, resizes, renames, or maximizes a pane | Everyone receives the same change and resulting layout. |
| Two people edit different panes at once | Both accepted changes survive. |
| A stale layout update arrives after a pane was closed | The pane stays removed; only a valid explicit Undo or add can restore it. |
| An old connection reconnects after handoff | It resumes observing; stale input cannot reach the runtime. |
| A reviewer attempts input, upload, or a shared layout edit directly | The authoritative handler rejects it, regardless of what the UI displays. |
| A controlling person's role is downgraded or revoked | Future input is rejected across all routes and clients. |
| The same agent is open in multiple personal swarms | All views agree on the real controller. |
| Alice closes an agent pane | It disappears from everyone's swarm; the agent process continues. |
| Alice undoes a valid pane close | The pane returns to the shared arrangement for everyone. |
| Alice closes her swarm tab or application window | The shared arrangement, membership, and agent execution continue. |
| Alice returns after others changed the swarm | She receives the current shared arrangement, including additions and removals. |
| A contributor withdraws an agent | Its live grant ends; ordinary Undo cannot restore it. |
| The owner is absent or an agent host is offline | Invitations and saved context behave as promised; live availability is honest. |
| A comment's source terminal has scrolled away | Its saved excerpt and attribution remain understandable. |
| An input acknowledgement is lost | No blind retry or duplicate execution; show uncertainty when delivery cannot be established. |

A successful pilot should demonstrate independent contribution, understandable permissions, dependable handoffs, and useful return visits. Shared presence alone would not validate the product.

## Commercial implication

Keep review and invitation acceptance free of a payment step. Charge the sponsoring team for people who regularly work in shared swarms, with one seat covering that team's swarms. Show the owner any seat cost before activating a paid collaborator; do not silently convert a guest or viewer into a billable seat. Treat any introductory free collaboration allowance and the exact price as experiments. Model usage remains a separate, clearly identified expense until Harness actually supplies the compute.

The recurring value to test is that teammates can understand, contribute to, and resume agent work with less coordination overhead. That is a stronger basis for a team subscription than charging for each invitation or each agent visible on screen.

## Sources

Official help pages are living documents, accessed September 13, 2026; publication dates are not asserted where the publisher does not provide one. The 2019 Figma engineering article is used for its documented design reasoning, not as a claim about its entire current implementation. The comparison is a product-design study, not an exhaustive enterprise permissions or pricing audit.

1. Figma. [Guide to sharing and permissions](https://help.figma.com/hc/en-us/articles/1500007609322-Guide-to-sharing-and-permissions). Sharing scope, viewing/editing, permission inheritance, and seats.
2. Google. [Share files from Google Drive](https://support.google.com/drive/answer/2494822?hl=en). Roles and restricted/link access.
3. Google. [Suggest edits in Google Docs](https://support.google.com/docs/answer/6033474?hl=en-8). Suggestions and review before applying changes.
4. Google. [Find what's changed in a file](https://support.google.com/docs/answer/190843?hl=en). Attribution and version history.
5. GitHub. [Pull requests](https://docs.github.com/en/pull-requests/reference/pull-requests). Review context and independent development models.
6. GitHub. [Repository roles for an organization](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization). Contribution and administration privileges.
7. Notion. [Sharing & permissions](https://www.notion.com/help/sharing-and-permissions). Page guests, resharing, inheritance, and overlapping grants.
8. Notion. [Comments, mentions & reactions](https://www.notion.com/help/comments-mentions-and-reminders). Durable discussion anchored to content.
9. Slack. [What is a channel?](https://slack.com/help/articles/360017938993-What-is-a-channel). Purpose, discovery, membership, and discussion.
10. Slack. [Use threads to organize discussions](https://slack.com/help/articles/115000769927-Use-threads-to-organize-discussions). Thread participation and notification behavior.
11. Slack. [Build with AI as a team using Slack Code](https://slack.com/help/articles/54310833022355-Build-with-AI-as-a-team-using-Slack-Code). Gradual rollout of team agent channels and artifact collaboration.
12. Microsoft. [Security — Live Share](https://learn.microsoft.com/en-us/visualstudio/liveshare/reference/security), section “Sharing a terminal.” Writable terminal capabilities and host responsibility.
13. Evan Wallace, Figma. [How Figma's multiplayer technology works](https://www.figma.com/blog/how-figmas-multiplayer-technology-works/), October 16, 2019. Document synchronization and undo.

Repository evidence reflects the working files inspected on September 13, 2026:

- **R1:** Companion checkout, [Harness browser thesis](../../harness-new-ui/research/harness-browser-thesis.md). Persistent agents, arbitrary personal swarms, real environments, and explicit coordination. The relative link assumes the companion checkout is a sibling of this repository.
- **R2:** [Swarm state](../desktop/lib/state/swarm.dart). Membership, view state, and session reuse.
- **R3:** [Terminal stream manager](../cli/src/lib/terminalStreamManager.ts#L276). Open-time takeover and control ownership.
- **R4:** [Desktop terminal session](../desktop/lib/terminal/terminal_session.dart). Terminal connection and input state.
- **R5:** [Machine service](../backend/src/services/MachineService.ts#L490). Owner-scoped machine access.
- **R6:** [Desktop architecture](../desktop/CLAUDE.md#L88). CLI-owned authentication and transport.
- **R7:** [E2EE core](../cli/src/lib/e2ee/core.ts#L379). Encrypted terminal control routes.
- **R8:** [V2 development handoff](harness-v2-progress.md). Current navigation, session-local history, and verification limits.
