# Remote harness viewers

Status: implemented on `codex/remote-viewers` · 2026-09-17

A harness on a linked machine opens its viewer beside its terminal in the desktop app. Both
machines need the forwarding-capable CLI. No public listener, inbound port, SSH tunnel, or relay
deployment is required. This uses the existing trusted machine link and preserves the owner's
interactive viewer access. Public watch links and collaborator permissions remain separate work.

## Connection

1. The remote daemon owns the viewer process and its allocated loopback port. It advertises
   `viewerForwarding: 1` inside the authenticated E2EE welcome.
2. The desktop's CLI rewrites viewer URLs in agent lists, creation/restart replies, and agent
   updates. Each remote agent gets a distinct local HTTP origin. Public HTTP(S) viewer URLs keep
   their existing behavior.
3. A short-lived bootstrap URL sets an HttpOnly, SameSite cookie and redirects to the viewer's
   original path, query and fragment. Root-relative assets and WebSocket URLs keep working.
4. HTTP requests, response metadata and streaming bytes travel as pairwise encrypted `viewer_*`
   frames on the existing WebSocket relay. Terminal WebRTC negotiation stays independent.
5. The remote endpoint resolves the agent through the viewer manager. It accepts only a currently
   running HTTP loopback viewer on the port the manager allocated. Requests cannot choose another
   host or port. HTTP redirects are returned to the browser, never followed by the daemon.

HTTP bodies stream in both directions, including POST, Range responses and EventSource. WebSocket
upgrades preserve subprotocols and carry their binary byte stream. Request Host, Origin and Referer,
same-origin response redirects, and viewer cookies are translated between the two origins. The
bootstrap cookie and unrelated local cookies never leave the desktop's computer.

## Bounds and cleanup

- 32 KiB data frames with a 128 KiB credit window per direction. A stalled consumer applies
  backpressure; files are not loaded into memory in full.
- At most 64 active streams per client, 256 per remote daemon, and 64 local viewer gateways per
  machine connection. Requests awaiting response headers or transfer credit time out after 30 seconds.
- Only authenticated web-role sessions or trusted local CLI clients can request a forward.
  Plaintext viewer replies and group-encrypted viewer replies are rejected by the desktop's relay.
- The gateway checks Host, Origin, Referer and fetch metadata, and requires its own bootstrap cookie.
  Viewer cookies use a distinct namespace for each gateway, including across loopback ports.
- Stopping/restarting a viewer, disconnecting/deselecting a machine, or revoking/evicting its E2EE
  session closes the associated forwarding resources. Detach does this immediately, even while the
  existing terminal relay connection lingers for reconnect. Artifact changes reuse the local origin.
- Older remote CLIs produce a viewer pane with update guidance. Local bind failures produce a
  recoverable viewer error while still returning the agent RPC.

## Compatibility and validation

Embedded viewers retain the desktop's macOS requirement. Mobile and direct-to-relay viewer builds
without a local CLI do not gain this forwarding path. A viewer should use relative URLs or
`location.origin` for assets and sockets; hard-coded remote loopback URLs inside JavaScript, HTML,
CSS or CSP are not rewritten. Forwarded viewers must use HTTP on their managed loopback port.

`cd cli && npm run test:remote-viewers` enforces **100% statements, branches, functions and lines on
each of the three new forwarding modules**. It includes network integration, malicious/malformed
requests, cancellation, resource limits and fault injection. It does not claim 100% coverage of the
entire CLI or desktop application.

The end-to-end test uses a desktop local WebSocket, the production relay pool, real E2EE identities,
the production remote daemon dispatcher, a viewer process launched by `DshViewerManager`, and an
opaque loopback backend fixture. It checks response streaming, ciphertext on the relay, restart,
and trust revocation. Set `HARNESS_VIEWER_BROWSER` to a Chromium executable to also run a fresh browser
profile through bootstrap cookies, root-relative assets, POST, SSE and WebSockets:

```sh
cd cli
HARNESS_VIEWER_BROWSER='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' npm run test:remote-viewers
```

Coverage reports are in `cli/coverage/remote-viewers/`. Desktop tests in `web_pane_test.dart` cover
update guidance, dismissal, recovery and the existing viewer layout. All fixtures use temporary
identities/workspaces and require no real account or model invocation.

Validation recorded on 2026-09-17:

- 68 feature tests passed with the isolated Chrome browser check enabled.
- Each forwarding module reached 100% statements, branches, functions and lines: 476 statements,
  305 branches, 86 functions and 337 executable lines in total.
- 192 surrounding daemon, local WebSocket, viewer-manager and E2EE regression tests passed.
- 23 desktop agent-model/viewer-pane tests passed; modified Dart files passed analysis.
- CLI type checking and build passed.

The backend in these tests is an opaque relay fixture, not the hosted production service. The
browser check exercises Chromium. Flutter widget tests verify viewer state and layout; they do
not instantiate native WKWebView.
