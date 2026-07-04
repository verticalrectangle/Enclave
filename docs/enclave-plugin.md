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

## Transport

The collab guest frame set is fixed (`hello/prompt/abort/ui-response/agent-cmd/
fetch-transcript`); the host `switch` drops anything else and extensions can't
see collab. So there is **no clean seam on stock omp** — a clean channel is an
omp-core change. Two implementations, one client interface:

- **Clean (`ext` frame):** add `{ t:"ext", ns, method, params, reqId }` guest→host
  and `{ t:"ext-result", reqId, … }` / `{ t:"ext-event", ns, data }` host→guest,
  routed to extensions via a new `ctx.collab.onRequest(ns, handler)` /
  `emit(ns, event)` API. ~5 files (pi-wire union, guest.ts, host.ts, extension
  context, collab-web mirror). Backward-compatible: the host's `default:` already
  ignores unknown frames and both guests tolerate unknown host frames. **Strong
  upstream-PR candidate; we own the box so we can run it patched without waiting.**
- **Sentinel (stock omp, zero fork):** encode a command in a `prompt` with a
  sentinel prefix; the extension's `before_agent_start` hook detects it, **blocks
  it from the LLM**, runs the op, and replies via a `custom_message`. Works today.

**Client `ControlChannel` is transport-agnostic** (request / response / subscribe).
Sentinel and `ext` are just two backends; the UI never changes. Ship sentinel if
impatient, swap to `ext` when merged — no churn.

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

## Open items (confirm before code)

1. Exact extension-facing **rewind / session-tree** method (or trigger a builtin
   `/rewind`-style slash command).
2. Confirm `before_agent_start` can **suppress** the sentinel prompt (not just
   observe) for the stock-omp path.
3. Decide **upstream PR vs. run-patched-on-our-box** for the `ext` frame.

## Build order

1. Client `ControlChannel` + capability-detect scaffolding (no behavior yet).
2. `enclave` extension: `/enclave` + handshake + `slash`/`set-model`/`set-thinking`
   over the **sentinel** transport. Test on the Hetzner box (omp + extension →
   `/enclave` → connect from the app).
3. Wire the slash palette + Trust model/thinking to the channel.
4. Add `rewind`.
5. (parallel) `ext` frame + `ctx.collab` — upstream PR; swap the transport.
6. Push: `register-push` + APNs from the extension.
