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

import { QrCode, renderQrHalfBlocks } from "./qrcode";
import { readFileSync, statSync } from "node:fs";
import { extname, resolve } from "node:path";

const COLLAB_PROTO = 3;
const ROOM_ID_BYTES = 16;
const WRITE_TOKEN_BYTES = 16;
const IV = 12;
const RELAY: string = (globalThis as any).process?.env?.ENCLAVE_RELAY || "wss://wickrunner.com:8443";

// ── base64url / crypto / envelope (mirror of omp's collab codec) ──────────────

const enc = new TextEncoder();
const dec = new TextDecoder();

// Slash commands not surfaced to the app: /enclave (already paired) plus anything
// that takes over the terminal UI, which the phone can't render.
const MOBILE_HIDE = new Set(["enclave", "collab", "vim", "theme", "keybindings", "quit", "exit", "help"]);
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

// One share per omp process. Re-running /enclave re-shows the QR for the existing
// share instead of opening a second relay socket + duplicate handlers (which crashed).
let current: { link: string } | null = null;

// The activation api carries the runtime-bound ACTIONS (sendUserMessage, abort,
// setModel, on, …). The per-invocation ctx (command/hook) carries the session
// data (sessionManager, models, navigateTree) but NOT the actions. So we route
// actions through `api` and session data through `ctx`.
let api: any;

// Return a bound caller for `name`, preferring ctx then the activation api.
// IMPORTANT: the returned closure invokes the method AS a member (obj.name(...))
// so `this` stays bound — extracting the fn and calling it standalone crashes
// omp with "undefined is not an object (evaluating 'this.extension')".
function bound(ctx: any, name: string): ((...a: any[]) => any) | undefined {
  if (typeof ctx?.[name] === "function") return (...a: any[]) => ctx[name](...a);
  if (typeof api?.[name] === "function") return (...a: any[]) => api[name](...a);
  return undefined;
}

/** Print the join QR + link as a normal transcript entry (not a modal overlay,
 *  which mangled the surrounding TUI). Rendered by the "enclave-share" renderer
 *  registered in activate(). */
function showQr(ctx: any, link: string): void {
  try {
    const qr = renderQrHalfBlocks(QrCode.encodeText(link, "M"));
    const text = ["", "enclave: sharing this session — scan to pair", "", ...qr, "", link, ""].join("\n");
    // A real transcript entry that reflows with the log (display:true is the render
    // path); falls back to a raw write only if sendMessage is unavailable.
    if (typeof api?.sendMessage === "function") {
      api.sendMessage({ customType: "enclave-share", content: text, display: true, attribution: "system" });
    } else {
      log(ctx, text);
    }
    try { (globalThis as any).process?.stderr?.write?.(`enclave: sharing ${link}\n`); } catch {}
  } catch { /* headless / no TUI */ }
}

export default function activate(ctx: any): void {
  api = ctx;   // runtime-bound actions live here
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
  if (current) { showQr(ctx, current.link); return current.link; }  // already sharing → re-show
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

  current = { link };
  showQr(ctx, link);   // prints the QR + link straight to the transcript
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
      case "prompt": {
        // A guest prompt always starts a fresh turn (the app's send button is Stop
        // mid-turn, so it never means "steer"). Steering on a stale isStreaming was
        // swallowing every message after the first — so never pass deliverAs.
        const imgs = (Array.isArray(frame.images) ? frame.images : [])
          .filter((im: any) => im?.type === "image" && im.data && im.mimeType)
          .map((im: any) => ({ type: "image", data: im.data, mimeType: im.mimeType }));
        const content = imgs.length ? [{ type: "text", text: frame.text ?? "" }, ...imgs] : frame.text;
        bound(ctx, "sendUserMessage")?.(content);
        return;
      }
      case "abort":
        bound(ctx, "abort")?.();
        return;
      case "enclave-cmd": {
        const r = await handleControl(ctx, frame.method, frame.params);
        await send({ t: "enclave-result", reqId: frame.reqId, ...r }, peer);
        // A rewind drops entries below the target; re-send the transcript so guests
        // reflect the rewound state (welcome resets the app's entries, snapshot reloads).
        if (frame.method === "rewind" && r.ok && ctx.sessionManager) {
          const snap = ctx.sessionManager.snapshotForReplication();
          snapHeader = snap.header;
          await send({ t: "welcome", proto: COLLAB_PROTO, header: snap.header, state: stateFrame(), agents: [], entryCount: snap.entries.length });
          await send({ t: "snapshot-chunk", entries: snap.entries, final: true });
        }
        return;
      }
    }
  }

  // Live stream to guests: new entries + agent events + state transitions.
  if (ctx.sessionManager) ctx.sessionManager.onEntryAppended = (entry: any) => { void send({ t: "entry", entry }); };
  const on = bound(ctx, "on");
  const fwd = (type: string) => (e: any) => { void send({ t: "event", event: { type, ...e } }); };
  for (const ev of ["message_start", "message_update", "message_end", "tool_execution_start", "tool_execution_update", "tool_execution_end"]) {
    on?.(ev, fwd(ev));
  }
  on?.("agent_start", () => { void send({ t: "event", event: { type: "agent_start" } }); void send({ t: "state", state: stateFrame() }); });
  on?.("agent_end", () => { void send({ t: "event", event: { type: "agent_end" } }); void send({ t: "state", state: stateFrame() }); });

  ws.onclose = () => { current = null; };

  return link;
}

function log(ctx: any, msg: string): void {
  try { ctx.ui?.write?.(msg); } catch {}
  try { (globalThis as any).process?.stderr?.write?.(msg + "\n"); } catch {}
}

// ── capability handshake ──────────────────────────────────────────────────────

function buildCaps(ctx: any) {
  const models = ctx.models ?? api?.models;
  const getCommands = bound(ctx, "getCommands");
  const getThinking = bound(ctx, "getThinkingLevel");
  const current = models?.current?.();
  const list = models?.list?.() ?? [];
  const seesImages = (m: any) => Array.isArray(m?.input) && m.input.includes("image");
  // An image is actually understandable if the current model sees pixels natively,
  // OR the inspect_image tool is on (getAllTools only lists it when enabled) so omp
  // can delegate to a vision model. visionModelAvailable = the fallback *could* be
  // enabled (a vision model exists) → the app greys the paperclip with a how-to.
  const nativeVision = seesImages(current);
  const inspectImage = (api?.runtime?.getAllTools?.() ?? []).includes("inspect_image");
  const visionModelAvailable = list.some(seesImages);
  const vision = nativeVision || inspectImage;
  return {
    t: "enclave-caps",
    version: 1,
    vision,                            // images are actually understandable now
    nativeVision,                      // current model sees images directly
    inspectImage,                      // the inspect_image fallback tool is enabled
    visionModelAvailable,              // a vision model exists (fallback could be turned on)
    thinking: ["minimal", "low", "medium", "high", "xhigh"],
    models: list.map((m: any) => ({ id: m.id, name: m.name ?? m.id, vision: seesImages(m) })),
    // Slash commands the guest can run — drop /enclave (you're already paired) and
    // anything that only makes sense in the terminal (a TUI takeover the app can't show).
    commands: (getCommands?.() ?? [])
      .filter((c: any) => c.name && !MOBILE_HIDE.has(c.name))
      .map((c: any) => ({ name: c.name, summary: c.description ?? "" })),
    current: { model: current?.id, thinking: getThinking?.() },
  };
}

// ── control dispatch ──────────────────────────────────────────────────────────

async function handleControl(ctx: any, method: string, params: any): Promise<{ ok: boolean; message?: string; data?: string; mimeType?: string }> {
  try {
    switch (method) {
      case "set-model": {
        const models = ctx.models ?? api?.models;
        const model = models?.resolve?.(params.model);
        if (!model) return { ok: false, message: `unknown model ${params.model}` };
        const ok = await bound(ctx, "setModel")?.(model);
        return { ok, message: ok ? `model → ${params.model}` : "no API key for that model" };
      }
      case "set-thinking":
        await bound(ctx, "setThinkingLevel")?.(params.level);
        return { ok: true, message: `thinking → ${params.level}` };
      case "rewind": {
        const r = await bound(ctx, "navigateTree")?.(params.toEntryId);
        return { ok: !r?.cancelled, message: r?.cancelled ? "rewind cancelled" : "rewound" };
      }
      case "slash": {
        if (MOBILE_HIDE.has(params.name)) return { ok: false, message: `/${params.name} isn't available from the app` };
        const cmd = (bound(ctx, "getCommands")?.() ?? []).find((c: any) => c.name === params.name);
        if (!cmd) return { ok: false, message: `no such command /${params.name}` };
        // Command handlers are (args, ctx) — omp built-in handlers crash without the
        // context, so pass the live command context through.
        await cmd.handler?.(params.args ?? "", ctx);
        return { ok: true, message: `ran /${params.name}` };
      }
      case "register-push":
        return { ok: true }; // TODO(push): persist token; APNs on asks
      case "fetch-image": {
        // Read a host image file and return its bytes so the guest can render it.
        // Non-mutating: allowed for read-only guests too. Only an /enclave host
        // runs this plugin, so this is the scope boundary for the feature.
        const cwd = ctx.cwd ?? ctx.sessionManager?.getCwd?.() ?? ".";
        const abs = resolve(cwd, String(params.path ?? ""));
        const st = statSync(abs);                       // throws → caught → {ok:false}
        const MAX = 20 * 1024 * 1024;                    // mirror inspect_image's cap
        if (st.size > MAX) return { ok: false, message: "image too large (>20MB)" };
        const data = readFileSync(abs);
        const ext = extname(abs).toLowerCase();
        const mimeMap: Record<string, string> = {
          ".png": "image/png",
          ".jpg": "image/jpeg",
          ".jpeg": "image/jpeg",
          ".gif": "image/gif",
          ".webp": "image/webp",
        };
        const mime = typeof params.mimeType === "string" && params.mimeType
          ? params.mimeType
          : (mimeMap[ext] ?? "image/png");
        return { ok: true, data: Buffer.from(data).toString("base64"), mimeType: mime };
      }
      default:
        return { ok: false, message: `unknown method ${method}` };
    }
  } catch (err) {
    return { ok: false, message: String(err) };
  }
}
