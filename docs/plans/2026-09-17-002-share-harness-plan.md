# Share a harness

Status: implementation in `codex/share-harness`.

## Experience

The agent pane offers **Share harness**. Its owner enters one or more email addresses and grants
**Can view** access. The dialog lists recipients, expiry, and active observers and supports removal.
Invitations are account-bound and appear in the recipient's app, including after first sign-in.

Machines has **Your machines** and **Shared with you** sections. Shared machines carry an owner label
and a distinct icon. Their submenus contain only harnesses shared with the signed-in recipient.
Opening one shows a live terminal and viewer with a persistent **View only** indicator. Disconnects
preserve the pane and recover automatically. Revocation immediately ends access.

## Boundaries

- Authorization belongs to a recipient and a specific agent on a machine. New agents never inherit it.
- An observer cannot acquire a terminal control lease, resize the owner's terminal, send input,
  answer questions or approvals, read arbitrary files, enumerate the machine, or mutate its viewer.
- Observer traffic uses a separate, account-authenticated relay and per-connection encryption.
  Observers never receive a machine's group key or its full-trust pairing credentials.
- The owner daemon keeps its own durable grant allow-list. Backend metadata alone cannot grant access.
- Live viewer images are rendered on the owner's machine. The observer gets pixels, never a proxy
  to a local viewer's APIs. Renderers use a separate browser profile without the owner's credentials.
- Publishing results and collaborative input are separate future work.

## Verification

Cover invite normalization and validation, owner/recipient authorization, duplicate and pending
invitations, discovery filtering, simultaneous observers, encryption and replay rejection, denied
input/resize/file access, immediate revocation, expiry, reconnect, offline state, terminal fidelity,
viewer updates, and existing owner controls. Measure coverage of the new feature modules and report
the actual numbers. Exercise real sockets and a disposable tmux session as well as desktop widgets;
keep test identities, daemons and runtime data isolated from the user's running sessions.
