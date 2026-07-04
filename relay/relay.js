// enclave relay — a self-hosted stand-in for wss://my.omp.sh.
//
// A blind, sealed message broker: it forwards opaque AES-GCM envelopes between
// the omp host and the phone guests in a room. It never decrypts anything — it
// only knows rooms, peer ids, and envelopes. Speaks the exact collab relay
// contract the Swift client (EngineBridge.swift) and omp expect:
//
//   GET /r/<roomId>?role=host|guest   → WebSocket upgrade
//   host binary frame: [4B uint32 BE peerId][sealed] — peer 0 broadcasts to all
//     guests, peer N targets that guest; forwarded unchanged.
//   guest binary frame: first 4 bytes rewritten to the sender's peer id, then
//     forwarded to the host.
//   TEXT to host: {"t":"peer-joined"|"peer-left","peer":N}
//   host leaves: TEXT {"t":"room-closed"} to every guest, then close 4001.
//
// Bound to localhost; Caddy terminates TLS and reverse-proxies wss → here.

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.RELAY_PORT || 8787);
const MAX_GUESTS = Number(process.env.RELAY_MAX_GUESTS || 16);
const ROOM_RE = /^\/r\/([A-Za-z0-9_-]{10,64})$/;

/** roomId -> { host, guests: Map<peerId, ws>, nextPeerId } */
const rooms = new Map();

const server = http.createServer((_req, res) => {
  res.writeHead(426, { "content-type": "text/plain" });
  res.end("websocket upgrade required");
});
const wss = new WebSocketServer({ noServer: true, maxPayload: 8 * 1024 * 1024 });

server.on("upgrade", (req, socket, head) => {
  let url;
  try { url = new URL(req.url, "http://x"); } catch { return socket.destroy(); }
  const match = ROOM_RE.exec(url.pathname);
  const role = url.searchParams.get("role");
  if (!match || (role !== "host" && role !== "guest")) return socket.destroy();
  wss.handleUpgrade(req, socket, head, (ws) => onConnect(ws, match[1], role));
});

function close(ws, code, reason) { try { ws.close(code, reason); } catch {} }
function toBuf(data) { return Buffer.isBuffer(data) ? data : Buffer.from(data); }

function onConnect(ws, roomId, role) {
  if (role === "host") {
    if (rooms.has(roomId)) return close(ws, 4009, "a host is already connected for this room");
    const room = { host: ws, guests: new Map(), nextPeerId: 1 };
    rooms.set(roomId, room);
    ws.on("message", (data, isBinary) => {
      if (!isBinary) return;
      const buf = toBuf(data);
      if (buf.length < 4) return;
      const peerId = buf.readUInt32BE(0);
      if (peerId === 0) { for (const g of room.guests.values()) g.send(buf); }
      else { const g = room.guests.get(peerId); if (g) g.send(buf); }
    });
    ws.on("close", () => {
      rooms.delete(roomId);
      for (const g of room.guests.values()) {
        try { g.send(JSON.stringify({ t: "room-closed" })); } catch {}
        close(g, 4001, "room closed");
      }
    });
  } else {
    const room = rooms.get(roomId);
    if (!room) return close(ws, 4004, "no such room");
    if (room.guests.size >= MAX_GUESTS) return close(ws, 4029, "room is full");
    const peerId = room.nextPeerId++;
    room.guests.set(peerId, ws);
    try { room.host.send(JSON.stringify({ t: "peer-joined", peer: peerId })); } catch {}
    ws.on("message", (data, isBinary) => {
      if (!isBinary) return;
      const buf = toBuf(data);
      if (buf.length < 4) return;
      buf.writeUInt32BE(peerId, 0); // relay rewrites the sender's peer id
      try { room.host.send(buf); } catch {}
    });
    ws.on("close", () => {
      room.guests.delete(peerId);
      try { room.host.send(JSON.stringify({ t: "peer-left", peer: peerId })); } catch {}
    });
  }
}

server.listen(PORT, "127.0.0.1", () => console.log(`enclave relay listening on 127.0.0.1:${PORT}`));
