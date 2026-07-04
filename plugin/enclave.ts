/**
 * enclave — an omp extension: `/collab`, but with a control channel for the
 * Enclave iOS app (per-session model / thinking / slash / rewind), and the
 * origin point for push notifications.
 *
 * It hosts a *superset* of the collab protocol: identical transcript frames
 * (so the app connects exactly like a normal guest) plus `enclave-caps` /
 * `enclave-cmd` / `enclave-result` control frames on the same sealed channel.
 * omp core is never touched.
 *
 * Status: control + capabilities below use confirmed `ctx` APIs. The transport
 * (relay socket + AES-256-GCM seal + transcript replication) is marked TODO —
 * it reuses the same wire the Swift client already implements
 * (EngineBridge.swift) and CollabHost's replication approach; wire it against
 * omp on the box, then this is complete.
 *
 * Protocol (matches Sources/EngineBridge.swift + the mock host):
 *   host→guest  enclave-caps    { version, vision, thinking[], models[], commands[], current }
 *   guest→host  enclave-cmd     { reqId, method, params }
 *   host→guest  enclave-result  { reqId, ok, message? }
 * methods: set-model {model} · set-thinking {level} · slash {name,args} ·
 *          rewind {toEntryId} · register-push {token}
 */

import type { ExtensionContext } from "@oh-my-pi/pi-coding-agent"; // adjust to the real path on the box

export default function activate(ctx: ExtensionContext): void {
  ctx.registerCommand("enclave", {
    description: "Share this session to the Enclave app (collab + control channel)",
    handler: async () => {
      // TODO(transport): open the relay room + print the QR. Reuse omp's collab
      // link/seal, or the same [4B peerId][12B IV][ct+tag] AES-256-GCM framing
      // the Swift client uses. Stream the transcript via ctx.sessionManager
      // (snapshot for replication + subscribe to appended entries), exactly as
      // CollabHost does. On each new guest, send the capability handshake:
      sendToGuest(buildCaps(ctx));
    },
  });
}

// ── capability handshake ─────────────────────────────────────────────────────

function buildCaps(ctx: ExtensionContext) {
  const current = ctx.models.current();
  // Vision = the model accepts image input (omp: model.input.includes("image")).
  const vision = !!current && Array.isArray((current as any).input) && (current as any).input.includes("image");

  return {
    t: "enclave-caps",
    version: 1,
    vision,
    thinking: ["minimal", "low", "medium", "high", "xhigh"],
    models: ctx.models.list().map(m => ({ id: (m as any).id, name: (m as any).name ?? (m as any).id })),
    commands: ctx.getCommands().map(c => ({ name: (c as any).name, summary: (c as any).description ?? "" })),
    current: { model: (current as any)?.id, thinking: ctx.getThinkingLevel?.() },
  };
}

// ── control dispatch ─────────────────────────────────────────────────────────

async function handleControl(ctx: ExtensionContext, method: string, params: any): Promise<{ ok: boolean; message?: string }> {
  try {
    switch (method) {
      case "set-model": {
        const model = ctx.models.resolve(params.model);
        if (!model) return { ok: false, message: `unknown model ${params.model}` };
        const ok = await ctx.setModel(model);
        return { ok, message: ok ? `model → ${params.model}` : "no API key for that model" };
      }
      case "set-thinking":
        await ctx.setThinkingLevel(params.level);
        return { ok: true, message: `thinking → ${params.level}` };
      case "rewind": {
        const { cancelled } = await ctx.navigateTree(params.toEntryId);
        return { ok: !cancelled, message: cancelled ? "rewind cancelled" : "rewound" };
      }
      case "slash": {
        // Map the common ones to direct ctx primitives; fall back to the
        // registered command's handler for the rest. Interactive commands
        // that call ctx.ui.ask(...) surface to the app as normal ui-requests.
        const cmd = ctx.getCommands().find(c => (c as any).name === params.name);
        if (!cmd) return { ok: false, message: `no such command /${params.name}` };
        await (cmd as any).handler?.(params.args ?? "");
        return { ok: true, message: `ran /${params.name}` };
      }
      case "register-push":
        // TODO(push): persist params.token; when a ui-request/ask appears, send
        // an APNs push to it (box holds the .p8). See docs/enclave-plugin.md.
        return { ok: true };
      default:
        return { ok: false, message: `unknown method ${method}` };
    }
  } catch (err) {
    return { ok: false, message: String(err) };
  }
}

// ── transport stubs (wire on the box) ────────────────────────────────────────

// Replace with the real sealed relay send once the room is stood up.
function sendToGuest(_frame: unknown): void {
  // TODO(transport): seal(frame) → [4B peerId][12B IV][ct+tag] → relay socket.
}

// When a guest control frame arrives (after unsealing), route it:
//   const result = await handleControl(ctx, frame.method, frame.params);
//   sendToGuest({ t: "enclave-result", reqId: frame.reqId, ...result });
export { handleControl };
