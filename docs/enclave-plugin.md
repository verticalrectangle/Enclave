# The `/enclave` plugin — design

Brings back the host-side power we removed (slash commands, per-session model /
thinking, edit→rewind) **the faithful way**: through omp's own extension system,
not by faking capabilities over the vanilla guest wire. Also the home for remote
push (the extension originates APNs when an ask is waiting).

## Principle

- **Client stays neutral.** The phone speaks only the standard collab wire. It
  *feature-detects* the plugin and shows extra controls only when present. No
  plugin → the app behaves exactly as it does today.
- **The extension is the server half of the omp adapter** — the mirror of
  `EngineBridge`. Every future tool integration follows the same shape: neutral
  client + per-tool host extension + a capability handshake.
- **Per-session, not global.** Control what's in front of you (this session's
  model, this session's rewind), never a fleet/config surface.

## Transport — `/enclave` is its own host (no omp patch)

`/enclave` is a standalone extension that **hosts a superset of the collab
protocol itself**, over the same relay + crypto. We own both ends (the extension
*and* the Enclave app), so we define the wire; omp core is never modified.

Why this is clean (confirmed against the extension API):
- **Stream the transcript:** `ctx.sessionManager` (read-only) gives the same
  snapshot + entry-append + subscribe primitives `CollabHost` uses. The plugin
  replicates the session to guests exactly like `/collab` does.
- **Reuse transport/crypto:** `ctx.pi` injects the whole `pi-coding-agent`
  module, so the plugin reuses omp's collab sealing / relay-client / link-format
  code (fallback: reimplement AES-256-GCM sealing — trivial, we already have it
  in Swift).
- **Superset frames:** the plugin's host emits the standard transcript
  `HostFrame`s **plus** its own capability/control frames on the same sealed
  channel — legal because *we* wrote the host and the relay forwards opaque
  bytes. omp's own collab-web ignores unknown frames; our app handles them.
- **Control never enters the prompt pipeline.** Commands arrive as control frames
  and are handled directly (`ctx.setModel`, `ctx.navigateTree`, …). Nothing to
  intercept — `before_agent_start` can't suppress a prompt anyway (its result only
  injects context), and this design never needs it to.

Client side: the app connects the same way it does today (same link/QR, same
`EngineBridge` transcript path); we add a `ControlChannel` for the new frames.

## The `enclave` extension (host)

- `registerCommand("enclave", …)` → `/enclave` starts the collab share (wraps
  `/collab`), enables the channel, and prints the QR.
- On guest join: emit a **capability handshake** — `{ models:[…], roles:[…],
  thinking:[…], commands:[…], current:{model,thinking}, version }`. The client
  parses this to know the plugin's there and to populate real pickers.
- Handle control requests (below) and reply with status.
- **Push originator:** guest sends `register-push {token}` over the channel; the
  extension stores it and calls APNs directly when an ask/approval appears (box is
  always-on, holds the `.p8`). Closes remote push with no separate bridge.

## Commands (phased)

| Phase | Command | omp API |
|---|---|---|
| 1 | `slash {name, args}` | run a registered/builtin slash command in-session; interactive ones surface back as `ui-request` → the app's existing **ask cards** |
| 1 | `set-model {model}` | `ctx.setModel(model)` (per-session) |
| 1 | `set-thinking {level}` | `ctx.setThinkingLevel(level)` |
| 2 | `rewind {toEntryId}` | session-tree navigation to an earlier node, then re-prompt |
| — | push `register-push {token}` | store token; APNs on asks |

Skip the old fiction entirely: paired-devices, host fingerprint.

## Client changes

- `ControlChannel` over the collab client (request/response/events).
- **Slash palette returns**, capability-gated: the `/` opener in the composer hint
  strip + the palette, populated from the handshake's `commands`. Tapping runs the
  command via the channel; interactive → ask card. Hidden entirely when no plugin.
- **Model / thinking** controls in Trust (read-only today) become live setters,
  gated on the handshake.
- Edit→rewind returns in the editor, gated on the plugin.

## Resolved (research done)

1. **Rewind** → `ctx.navigateTree(entryId, {summarize?})` (+ `ctx.branch(entryId)`).
   Guest sends `rewind {toEntryId}`; entry IDs are already the app's `UITurn` ids.
2. **Prompt suppression** → not needed. `before_agent_start` can read the prompt
   but its result only injects context (no block/cancel), and this design routes
   control on its own channel, never through the prompt path.
3. **omp patch** → none. The plugin hosts its own superset channel via
   `ctx.sessionManager` + `ctx.pi` + the control methods.

**One build-time check:** exactly which collab helpers `ctx.pi` re-exports (sealing
/ relay-client / `formatCollabLink`). If any are missing, reimplement that piece in
the extension (small; the crypto is standard AES-256-GCM).

## Build order

1. `enclave` extension skeleton: `registerCommand("enclave")`, and a host loop
   that (via `ctx.pi`) opens a relay room + seals frames and (via
   `ctx.sessionManager`) streams the transcript — i.e. reach `/collab` parity.
   Test on the Hetzner box: `omp` → `/enclave` → connect from the app.
2. Capability handshake frame (models / thinking / commands / current).
3. Control frames + handlers: `set-model`, `set-thinking`, `slash`; wire the app's
   `ControlChannel` + return the slash palette (capability-gated) and the live
   model/thinking controls in Trust.
4. `rewind` (`navigateTree`) + edit→rewind UI.
5. Push: `register-push` + APNs from the extension.
