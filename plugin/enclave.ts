/**
 * enclave — an omp extension: `/collab`, but with a control channel for the
 * Enclave iOS app (per-session model / thinking / slash / rewind) and, later,
 * push. It hosts a *superset* of the collab protocol itself, so omp core is
 * never touched.
 *
 * Self-contained on purpose: the installed omp is a compiled binary, so this
 * imports nothing from omp internals. The seal/link/envelope below are the same
 * scheme as omp's collab codec (verified against packages/collab-web/src/lib),
 * and the runtime (bun) provides crypto.subtle + WebSocket. The transcript comes
 * from ctx.sessionManager; control uses confirmed ctx methods.
 *
 *   Load for dev:   omp -e /home/alexis/dev/Enclave/plugin/enclave.ts
 *   Then in omp:    /enclave           (prints the link the app joins)
 *   Relay:          $ENCLAVE_RELAY (default wss://wickrunner.com:8443)
 *
 * Protocol (matches Sources/EngineBridge.swift + the mock host):
 *   host→guest  welcome / snapshot-chunk / entry / state / event / enclave-caps / enclave-result
 *   guest→host  hello / prompt / abort / enclave-cmd
 */

const COLLAB_PROTO = 3;
const ROOM_ID_BYTES = 16;
const WRITE_TOKEN_BYTES = 16;
const IV = 12;
const RELAY: string = (globalThis as any).process?.env?.ENCLAVE_RELAY || "wss://wickrunner.com:8443";

// ── base64url / crypto / envelope (mirror of omp's collab codec) ──────────────

const enc = new TextEncoder();
const dec = new TextDecoder();
function rand(n: number): Uint8Array { const a = new Uint8Array(n); crypto.getRandomValues(a); return a; }
function b64url(bytes: Uint8Array): string {
  let s = ""; for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
function importKey(raw: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}
async function seal(key: CryptoKey, frame: unknown): Promise<Uint8Array> {
  const iv = rand(IV);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, enc.encode(JSON.stringify(frame))));
  const out = new Uint8Array(IV + ct.byteLength); out.set(iv, 0); out.set(ct, IV); return out;
}
async function open(key: CryptoKey, data: Uint8Array): Promise<any> {
  const pt = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-GCM", iv: data.subarray(0, IV) }, key, data.subarray(IV)));
  return JSON.parse(dec.decode(pt));
}
function packEnvelope(peerId: number, sealed: Uint8Array): Uint8Array {
  const out = new Uint8Array(4 + sealed.byteLength); new DataView(out.buffer).setUint32(0, peerId, false); out.set(sealed, 4); return out;
}
function unpackEnvelope(data: Uint8Array): { peerId: number; payload: Uint8Array } | null {
  if (data.byteLength < 4) return null;
  return { peerId: new DataView(data.buffer, data.byteOffset, 4).getUint32(0, false), payload: data.subarray(4) };
}
function formatLink(roomId: string, key: Uint8Array, token: Uint8Array): string {
  const secret = new Uint8Array(key.byteLength + token.byteLength); secret.set(key, 0); secret.set(token, key.byteLength);
  const host = RELAY.replace(/^wss?:\/\//, "");
  return `${RELAY.startsWith("ws://") ? "ws://" : "wss://"}${host}/r/${roomId}.${b64url(secret)}`;
}

// ── the extension ─────────────────────────────────────────────────────────────

export default function activate(ctx: any): void {
  // The command handler's ctx (ExtensionCommandContext) is the rich one — it has
  // sessionManager / models / navigateTree, which the activation api does not
  // (no session exists yet at activate time).
  ctx.registerCommand?.("enclave", {
    description: "Share this session to the Enclave app (collab + control channel)",
    handler: (_args: string, cmdCtx: any) => startShare(cmdCtx),
  });
  // Headless testing seam: share once a session exists.
  if ((globalThis as any).process?.env?.ENCLAVE_SHARE === "1") {
    ctx.on?.("session_start", (_e: any, hookCtx: any) => startShare(hookCtx ?? ctx));
  }
}

async function startShare(ctx: any): Promise<string> {
  const roomId = b64url(rand(ROOM_ID_BYTES));
  const rawKey = rand(32);
  const writeToken = rand(WRITE_TOKEN_BYTES);
  const key = await importKey(rawKey);
  const link = formatLink(roomId, rawKey, writeToken);

  const peers = new Map<number, string>();
  const ws = new WebSocket(`${RELAY}/r/${roomId}?role=host`);
  (ws as any).binaryType = "arraybuffer";

  const send = async (frame: unknown, peer = 0) => {
    try { ws.send(packEnvelope(peer, await seal(key, frame))); } catch (e) { /* socket closed */ }
  };
  const stateFrame = () => ({
    isStreaming: !!ctx.isStreaming,
    queuedMessageCount: 0,
    sessionName: snapHeader?.title,
    cwd: snapHeader?.cwd ?? ctx.cwd,
    model: ctx.models?.current?.(),
    thinkingLevel: ctx.getThinkingLevel?.(),
    contextUsage: ctx.getContextUsage?.(),
    participants: [{ name: ctx.hostName ?? "host", role: "host" }, ...[...peers.values()].map(name => ({ name, role: "guest" }))],
  });
  let snapHeader: any;

  ws.onopen = () => log(ctx, `\n  enclave: sharing this session\n  ${link}\n`);
  ws.onmessage = async (ev: any) => {
    if (typeof ev.data === "string") {                    // relay control
      const c = JSON.parse(ev.data);
      if (c.t === "peer-left") peers.delete(c.peer);
      return;
    }
    const env = unpackEnvelope(new Uint8Array(ev.data));
    if (!env) return;
    let frame: any; try { frame = await open(key, env.payload); } catch { return; }
    await onGuestFrame(frame, env.peerId);
  };

  async function onGuestFrame(frame: any, peer: number): Promise<void> {
    switch (frame.t) {
      case "hello": {
        peers.set(peer, (frame.name || `guest-${peer}`).slice(0, 64));
        const snap = ctx.sessionManager.snapshotForReplication();
        snapHeader = snap.header;
        await send({ t: "welcome", proto: COLLAB_PROTO, header: snap.header, state: stateFrame(), agents: [], entryCount: snap.entries.length }, peer);
        await send({ t: "snapshot-chunk", entries: snap.entries, final: true }, peer);
        await send(buildCaps(ctx), peer);
        await send({ t: "state", state: stateFrame() }, peer);
        return;
      }
      case "prompt":
        // Guest drives a turn. Steer if a turn is in flight, else start one.
        ctx.sendUserMessage?.(frame.text, ctx.isStreaming ? { deliverAs: "steer" } : undefined);
        return;
      case "abort":
        ctx.abort?.();
        return;
      case "enclave-cmd": {
        const r = await handleControl(ctx, frame.method, frame.params);
        await send({ t: "enclave-result", reqId: frame.reqId, ...r }, peer);
        return;
      }
    }
  }

  // Live stream to guests: new entries + agent events + state transitions.
  if (ctx.sessionManager) ctx.sessionManager.onEntryAppended = (entry: any) => { void send({ t: "entry", entry }); };
  const fwd = (type: string) => (e: any) => { void send({ t: "event", event: { type, ...e } }); };
  for (const ev of ["message_start", "message_update", "message_end", "tool_execution_start", "tool_execution_update", "tool_execution_end"]) {
    ctx.on?.(ev, fwd(ev));
  }
  ctx.on?.("agent_start", () => { void send({ t: "event", event: { type: "agent_start" } }); void send({ t: "state", state: stateFrame() }); });
  ctx.on?.("agent_end", () => { void send({ t: "event", event: { type: "agent_end" } }); void send({ t: "state", state: stateFrame() }); });

  return link;
}

function log(ctx: any, msg: string): void {
  try { ctx.ui?.write?.(msg); } catch {}
  try { (globalThis as any).process?.stderr?.write?.(msg + "\n"); } catch {}
}

// ── capability handshake ──────────────────────────────────────────────────────

function buildCaps(ctx: any) {
  const current = ctx.models?.current?.();
  const list = ctx.models?.list?.() ?? [];
  const seesImages = (m: any) => Array.isArray(m?.input) && m.input.includes("image");
  // Offer image attach whenever this omp can handle an image at all: the current
  // model sees images directly, OR any available model does — in which case omp's
  // vision-role fallback (modelRoles.vision / describeAttachedImagesForTextModel)
  // routes the image through that model and injects a description. So the paperclip
  // stays available on a text model like DeepSeek, and images go to the vision model.
  const vision = seesImages(current) || list.some(seesImages);
  return {
    t: "enclave-caps",
    version: 1,
    vision,
    thinking: ["minimal", "low", "medium", "high", "xhigh"],
    models: (ctx.models?.list?.() ?? []).map((m: any) => ({ id: m.id, name: m.name ?? m.id })),
    commands: (ctx.getCommands?.() ?? []).map((c: any) => ({ name: c.name, summary: c.description ?? "" })),
    current: { model: current?.id, thinking: ctx.getThinkingLevel?.() },
  };
}

// ── control dispatch ──────────────────────────────────────────────────────────

async function handleControl(ctx: any, method: string, params: any): Promise<{ ok: boolean; message?: string }> {
  try {
    switch (method) {
      case "set-model": {
        const model = ctx.models?.resolve?.(params.model);
        if (!model) return { ok: false, message: `unknown model ${params.model}` };
        const ok = await ctx.setModel(model);
        return { ok, message: ok ? `model → ${params.model}` : "no API key for that model" };
      }
      case "set-thinking":
        await ctx.setThinkingLevel(params.level);
        return { ok: true, message: `thinking → ${params.level}` };
      case "rewind": {
        const r = await ctx.navigateTree(params.toEntryId);
        return { ok: !r?.cancelled, message: r?.cancelled ? "rewind cancelled" : "rewound" };
      }
      case "slash": {
        const cmd = (ctx.getCommands?.() ?? []).find((c: any) => c.name === params.name);
        if (!cmd) return { ok: false, message: `no such command /${params.name}` };
        await cmd.handler?.(params.args ?? "");
        return { ok: true, message: `ran /${params.name}` };
      }
      case "register-push":
        return { ok: true }; // TODO(push): persist token; APNs on asks
      default:
        return { ok: false, message: `unknown method ${method}` };
    }
  } catch (err) {
    return { ok: false, message: String(err) };
  }
}
