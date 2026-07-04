//  EngineBridge.swift
//  The live oh-my-pi collab guest client. This is the ONLY file that talks the
//  wire protocol: it parses a `/collab` link, opens the relay WebSocket, seals
//  and opens AES-256-GCM frames, applies host frames in arrival order, and
//  projects the omp transcript onto the app's `[UITurn]` shape so every existing
//  view renders live data unchanged.
//
//  Protocol mirror of @oh-my-pi/collab-web (src/lib/{client,socket,codec,link}.ts)
//  and the shared wire types in @oh-my-pi/pi-wire. COLLAB_PROTO = 3.
//
//    let client = GuestClient(link: "ws://localhost:7466/r/<id>.<key>", name: "iPhone")
//    client.connect()          // → client.turns streams; feed EditorView via SessionVM
//    client.sendPrompt("…")    // steer / prompt the host agent
//    client.sendAbort()        // stop the current turn

import Foundation
import CryptoKit
import Combine

// ═══════════════════════════════════════════════════════════════════════════
// Wire constants (pi-wire/src/index.ts)
// ═══════════════════════════════════════════════════════════════════════════

private enum Wire {
    static let proto = 3
    static let envelopeHeader = 4         // [4B uint32 BE peerId]
    static let roomKeyBytes = 32
    static let writeTokenBytes = 16
    static let defaultRelay = "wss://my.omp.sh"
}

// ═══════════════════════════════════════════════════════════════════════════
// base64url
// ═══════════════════════════════════════════════════════════════════════════

enum Base64URL {
    static func decode(_ text: String) -> Data? {
        var s = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Collab link → { wsURL, key, writeToken }
// ═══════════════════════════════════════════════════════════════════════════

enum LinkParse {
    case ok(CollabLink)
    case err(String)
}

struct CollabLink {
    let wsURL: URL          // wss://host[:port]/r/<roomId>
    let key: SymmetricKey
    let writeToken: Data?

    /// Accepts the compact bare form (`<roomId>.<key>` → default relay), a
    /// scheme-less `host/r/<roomId>.<key>` (→ wss), or a full ws/wss URL.
    static func parse(_ raw: String) -> LinkParse {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%23", with: "#", options: .caseInsensitive)
        if text.isEmpty { return .err("Paste a collab link.") }

        // Bare `<roomId>.<key>` or legacy `<roomId>#<key>` → default relay.
        if let m = text.range(of: #"^([A-Za-z0-9_-]{10,64})[#.]([A-Za-z0-9_-]+)$"#, options: .regularExpression) {
            _ = m
            let parts = text.split(whereSeparator: { $0 == "#" || $0 == "." })
            if parts.count == 2 { text = "\(Wire.defaultRelay)/r/\(parts[0]).\(parts[1])" }
        } else if !text.contains("://") {
            text = "wss://\(text)"       // scheme-less host/r/… → wss
        }

        guard let url = URLComponents(string: text), let scheme = url.scheme, let host = url.host else {
            return .err("That doesn't look like a collab link.")
        }
        // A browser web link — what omp's QR encodes — carries the collab link in
        // the URL fragment: `https://my.omp.sh/#<roomId>.<key>`. Unwrap and parse it.
        if scheme == "http" || scheme == "https", let frag = url.fragment, !frag.isEmpty {
            return parse(frag)
        }
        let wsScheme: String
        switch scheme {
        case "wss", "https": wsScheme = "wss"
        case "ws", "http":
            let local = host == "localhost" || host == "127.0.0.1" || host == "::1"
            if !local { return .err("Plain ws:// is only allowed for localhost — use wss://.") }
            wsScheme = "ws"
        default: return .err("Unsupported scheme: \(scheme)")
        }

        // Path `/r/<roomId>.<key>` or legacy `/r/<roomId>` with key in the fragment.
        guard let match = url.path.range(of: #"^/r/([A-Za-z0-9_-]{10,64})(\.[A-Za-z0-9_-]+)?$"#, options: .regularExpression) else {
            return .err("Link must contain a /r/<roomId> path.")
        }
        _ = match
        let pathBody = String(url.path.dropFirst(3))  // after "/r/"
        let roomId: String
        var fragment: String?
        if let dot = pathBody.firstIndex(of: ".") {
            roomId = String(pathBody[..<dot])
            fragment = String(pathBody[pathBody.index(after: dot)...])
        } else {
            roomId = pathBody
            fragment = url.fragment
        }
        guard let frag = fragment, !frag.isEmpty, let secret = Base64URL.decode(frag) else {
            return .err("Link is missing the key part.")
        }
        guard secret.count == Wire.roomKeyBytes || secret.count == Wire.roomKeyBytes + Wire.writeTokenBytes else {
            return .err("Key must be 32 (view) or 48 (full) bytes.")
        }
        let keyData = secret.prefix(Wire.roomKeyBytes)
        let writeToken = secret.count > Wire.roomKeyBytes ? Data(secret.suffix(Wire.writeTokenBytes)) : nil
        let portPart = url.port.map { ":\($0)" } ?? ""
        guard let ws = URL(string: "\(wsScheme)://\(host)\(portPart)/r/\(roomId)") else {
            return .err("Could not build the relay URL.")
        }
        return .ok(CollabLink(wsURL: ws, key: SymmetricKey(data: keyData), writeToken: writeToken))
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// AES-256-GCM sealing. WebCrypto's `[12B IV][ciphertext+tag]` layout is exactly
// CryptoKit's `SealedBox.combined` (nonce ∥ ciphertext ∥ tag).
// ═══════════════════════════════════════════════════════════════════════════

private enum Seal {
    static func open(_ key: SymmetricKey, _ data: Data) -> [String: Any]? {
        guard data.count > 12,
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key),
              let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any]
        else { return nil }
        return obj
    }
    static func seal(_ key: SymmetricKey, _ frame: [String: Any]) -> Data? {
        guard let plain = try? JSONSerialization.data(withJSONObject: frame),
              let box = try? AES.GCM.seal(plain, using: key)
        else { return nil }
        return box.combined     // 12B nonce + ciphertext + 16B tag
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// WebSocket transport: `?role=guest`, binary sealed envelopes, text control.
// ═══════════════════════════════════════════════════════════════════════════

private final class CollabSocket: NSObject, URLSessionWebSocketDelegate {
    var onOpen: (() -> Void)?
    var onFrame: (([String: Any]) -> Void)?
    var onControl: (([String: Any]) -> Void)?
    var onClose: ((String) -> Void)?

    private let wsURL: URL
    private let key: SymmetricKey
    private var task: URLSessionWebSocketTask?
    private var closed = false

    init(wsURL: URL, key: SymmetricKey) { self.wsURL = wsURL; self.key = key }

    func connect() {
        closed = false
        var comps = URLComponents(url: wsURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "role", value: "guest")]
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: comps.url!)
        self.task = task
        task.resume()
        receive()
    }

    func close() {
        closed = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// Seal a guest frame and send it as `[4B peerId=0][sealed]`.
    func send(_ frame: [String: Any]) {
        guard let sealed = Seal.seal(key, frame) else { return }
        var env = Data(count: Wire.envelopeHeader)   // peerId 0, big-endian
        env.append(sealed)
        task?.send(.data(env)) { _ in }
    }

    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol proto: String?) {
        onOpen?()
    }
    func urlSession(_ s: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith code: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        fail("connection closed (\(code.rawValue))")
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self, !self.closed else { return }
            switch result {
            case .failure(let err):
                self.fail(err.localizedDescription)
                return
            case .success(let message):
                switch message {
                case .data(let data):
                    if data.count > Wire.envelopeHeader {
                        let payload = data.subdata(in: Wire.envelopeHeader..<data.count)
                        if let frame = Seal.open(self.key, payload) { self.onFrame?(frame) }
                        else { self.fail("bad key or corrupted frame") }
                    }
                case .string(let text):
                    if let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                        self.onControl?(obj)
                    }
                @unknown default: break
                }
                self.receive()
            }
        }
    }

    private func fail(_ reason: String) {
        if closed { return }
        closed = true
        onClose?(reason)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// GuestClient — session replica + transcript projection + commands.
// ═══════════════════════════════════════════════════════════════════════════

@MainActor
final class GuestClient: ObservableObject {
    // Published surface the UI observes.
    @Published private(set) var turns: [UITurn] = []
    @Published private(set) var phase: String = "connecting"   // connecting/waiting/live/ended
    @Published private(set) var working = false
    @Published private(set) var title = "omp session"
    @Published private(set) var cwd = "~"
    @Published private(set) var modelName = "—"
    @Published private(set) var tokensLabel = "—"
    @Published private(set) var costLabel = "—"
    @Published private(set) var endedReason: String?
    @Published private(set) var readOnly = false

    // Trust / Activity surfaces.
    @Published private(set) var sessionId = ""
    @Published private(set) var relay = "—"
    @Published private(set) var thinkingLevel = "—"
    @Published private(set) var contextPercent: Double?
    @Published private(set) var queued = 0
    @Published private(set) var participants: [ParticipantInfo] = []
    @Published private(set) var agents: [AgentInfo] = []
    @Published private(set) var progress: [SubagentProgress] = []

    // /enclave enhanced capabilities — all false/empty over plain /collab.
    @Published private(set) var enhanced = false        // an /enclave host is present
    @Published private(set) var canSendImages = false   // images attachable (native or via fallback)
    @Published private(set) var nativeVision = false    // current model sees images directly
    @Published private(set) var commands: [EnclaveCommand] = []
    @Published private(set) var models: [ModelOption] = []
    @Published private(set) var thinkingLevels: [String] = []

    /// Fired after every applied frame (SessionVM bridges this to its own publish).
    var onChange: (() -> Void)?

    private let socket: CollabSocket
    private let name: String
    private let writeToken: Data?
    private var reqSeq = 0
    private var pendingTranscripts: [Int: CheckedContinuation<(text: String, newSize: Int)?, Never>] = [:]
    private var pendingControl: [Int: CheckedContinuation<String?, Never>] = [:]
    private var progressMap: [String: SubagentProgress] = [:]

    // Replica state.
    private var entries: [[String: Any]] = []
    private var stream: [String: Any]?          // streaming assistant ghost
    private var streamDone = false
    private var activeTools: [(id: String, tool: [String: Any])] = []
    private var uiRequest: [String: Any]?
    @Published private(set) var welcomed = false   // a host actually answered (got a welcome)

    init?(link: String, name: String) {
        switch CollabLink.parse(link) {
        case .err: return nil
        case .ok(let parsed):
            self.name = name
            self.writeToken = parsed.writeToken
            self.readOnly = parsed.writeToken == nil
            self.relay = (parsed.wsURL.host ?? "—") + (parsed.wsURL.port.map { ":\($0)" } ?? "")
            self.socket = CollabSocket(wsURL: parsed.wsURL, key: parsed.key)
        }
        socket.onOpen = { [weak self] in Task { @MainActor in self?.handleOpen() } }
        socket.onFrame = { [weak self] f in Task { @MainActor in self?.applyFrame(f) } }
        socket.onControl = { [weak self] c in Task { @MainActor in
            if c["t"] as? String == "room-closed" { self?.end("room closed") }
        } }
        socket.onClose = { [weak self] r in Task { @MainActor in self?.end(r) } }
    }

    /// `nil` when the pasted link doesn't parse — surface the reason to the user.
    static func validate(_ link: String) -> String? {
        if case .err(let reason) = CollabLink.parse(link) { return reason }
        return nil
    }

    func connect() { socket.connect() }
    func close() { socket.close() }

    // ── commands ─────────────────────────────────────────────────────────────

    func sendPrompt(_ text: String, images: [(mime: String, base64: String)] = []) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty || !images.isEmpty else { return }
        var frame: [String: Any] = ["t": "prompt", "text": clean]
        if !images.isEmpty {
            frame["images"] = images.map { ["type": "image", "mimeType": $0.mime, "data": $0.base64] }
        }
        socket.send(frame)
    }
    func sendAbort() { socket.send(["t": "abort"]) }
    func answer(reqId: Int, value: String) {
        socket.send(["t": "ui-response", "reqId": reqId, "value": value])
        if (uiRequest?["reqId"] as? Int) == reqId { uiRequest = nil; rebuild() }
    }

    // ── /enclave control channel (no-ops unless the plugin is present) ────────

    /// Send a control command and await its result. Returns nil on success, or an
    /// error message. (Frames are simply ignored by a plain /collab host.)
    @discardableResult
    func sendControl(_ method: String, _ params: [String: Any] = [:]) async -> String? {
        guard enhanced else { return "this session isn't running /enclave" }
        reqSeq += 1
        let reqId = reqSeq
        return await withCheckedContinuation { cont in
            pendingControl[reqId] = cont
            socket.send(["t": "enclave-cmd", "reqId": reqId, "method": method, "params": params])
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if let c = self?.pendingControl.removeValue(forKey: reqId) { c.resume(returning: "timed out") }
            }
        }
    }

    @discardableResult func setModel(_ id: String) async -> String? { await sendControl("set-model", ["model": id]) }
    @discardableResult func setThinking(_ level: String) async -> String? { await sendControl("set-thinking", ["level": level]) }
    @discardableResult func runSlash(_ name: String, args: String = "") async -> String? { await sendControl("slash", ["name": name, "args": args]) }
    @discardableResult func rewind(to entryId: String) async -> String? { await sendControl("rewind", ["toEntryId": entryId]) }

    /// Chat with / kill / revive a subagent (agent-cmd guest frame).
    func sendAgentCmd(_ cmd: String, agentId: String, text: String? = nil) {
        var frame: [String: Any] = ["t": "agent-cmd", "cmd": cmd, "agentId": agentId]
        if let text { frame["text"] = text }
        socket.send(frame)
    }

    /// Incremental subagent-transcript read (fetch-transcript). Returns decoded
    /// JSONL from `fromByte` + the next offset base, or nil on timeout/failure.
    func fetchTranscript(agentId: String, fromByte: Int) async -> (text: String, newSize: Int)? {
        reqSeq += 1
        let reqId = reqSeq
        return await withCheckedContinuation { cont in
            pendingTranscripts[reqId] = cont
            socket.send(["t": "fetch-transcript", "reqId": reqId, "agentId": agentId, "fromByte": fromByte])
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let c = self?.pendingTranscripts.removeValue(forKey: reqId) { c.resume(returning: nil) }
            }
        }
    }

    // ── frame handling (mirrors client.ts #applyFrame) ────────────────────────

    private func handleOpen() {
        var hello: [String: Any] = ["t": "hello", "proto": Wire.proto, "name": name]
        if let token = writeToken { hello["writeToken"] = Base64URL.encode(token) }
        socket.send(hello)
        phase = welcomed ? "reconnecting" : "waiting"
    }

    private func applyFrame(_ f: [String: Any]) {
        guard let t = f["t"] as? String else { return }
        switch t {
        case "welcome":
            welcomed = true
            entries = []
            stream = nil; streamDone = false; activeTools = []; uiRequest = nil
            progressMap = [:]; progress = []
            enhanced = false; canSendImages = false; nativeVision = false; commands = []
            endedReason = nil
            if let header = f["header"] as? [String: Any] {
                title = header["title"] as? String ?? header["id"] as? String ?? title
                sessionId = header["id"] as? String ?? sessionId
            }
            applyState(f["state"] as? [String: Any])
            applyAgents(f["agents"] as? [[String: Any]])
            readOnly = f["readOnly"] as? Bool ?? readOnly
            phase = (f["entryCount"] as? Int ?? 0) == 0 ? "live" : "waiting"
        case "snapshot-chunk":
            if let list = f["entries"] as? [[String: Any]] { entries.append(contentsOf: list) }
            if f["final"] as? Bool == true { phase = "live" }
        case "entry":
            if let e = f["entry"] as? [String: Any] {
                entries.append(e)
                if streamDone, isAssistantMessage(e) { stream = nil; streamDone = false }
            }
        case "event":
            applyEvent(f["event"] as? [String: Any])
        case "state":
            applyState(f["state"] as? [String: Any])
        case "agents":
            applyAgents(f["agents"] as? [[String: Any]])
        case "bus":
            applyBus(channel: f["channel"] as? String, data: f["data"] as? [String: Any])
        case "transcript":
            if let reqId = f["reqId"] as? Int, let cont = pendingTranscripts.removeValue(forKey: reqId) {
                if f["error"] != nil { cont.resume(returning: nil) }
                else { cont.resume(returning: (f["text"] as? String ?? "", f["newSize"] as? Int ?? fromByteFallback)) }
            }
        case "enclave-caps":            // the /enclave host announcing its powers
            enhanced = true
            canSendImages = f["vision"] as? Bool ?? false
            nativeVision = f["nativeVision"] as? Bool ?? true   // absent → assume native (no hint)
            commands = (f["commands"] as? [[String: Any]] ?? []).map {
                EnclaveCommand(name: $0["name"] as? String ?? "", summary: $0["summary"] as? String ?? $0["description"] as? String ?? "")
            }
            models = (f["models"] as? [[String: Any]] ?? []).map {
                ModelOption(modelId: $0["id"] as? String ?? "", name: $0["name"] as? String ?? ($0["id"] as? String ?? ""))
            }
            if let levels = f["thinking"] as? [String] { thinkingLevels = levels }
            if let cur = f["current"] as? [String: Any], let th = cur["thinking"] as? String { thinkingLevel = th }
        case "enclave-result":          // reply to a control command
            if let reqId = f["reqId"] as? Int, let cont = pendingControl.removeValue(forKey: reqId) {
                cont.resume(returning: (f["ok"] as? Bool ?? true) ? nil : (f["message"] as? String ?? "failed"))
            }
        case "ui-request":
            uiRequest = f["request"] as? [String: Any]
        case "ui-request-end":
            if (uiRequest?["reqId"] as? Int) == (f["reqId"] as? Int) { uiRequest = nil }
        case "bye":
            end(f["reason"] as? String ?? "session ended"); return
        case "error":
            if !welcomed { end(f["message"] as? String ?? "host error"); return }
        default:
            break
        }
        rebuild()
    }

    private var fromByteFallback: Int { 0 }

    private func applyAgents(_ list: [[String: Any]]?) {
        guard let list else { return }
        agents = list.map { a in
            AgentInfo(id: a["id"] as? String ?? UUID().uuidString,
                      displayName: a["displayName"] as? String ?? "agent",
                      kind: a["kind"] as? String ?? "sub",
                      status: a["status"] as? String ?? "idle",
                      hasSessionFile: a["hasSessionFile"] as? Bool ?? false)
        }
    }

    private func applyBus(channel: String?, data: [String: Any]?) {
        guard let channel, let data else { return }
        if channel == "task:subagent:progress", let p = data["progress"] as? [String: Any] {
            let id = p["id"] as? String ?? "\(data["index"] as? Int ?? 0)"
            progressMap[id] = SubagentProgress(
                id: id,
                index: data["index"] as? Int ?? p["index"] as? Int ?? 0,
                task: data["task"] as? String ?? p["task"] as? String ?? "task",
                description: p["description"] as? String ?? data["assignment"] as? String,
                status: p["status"] as? String ?? "running",
                currentTool: p["currentTool"] as? String,
                lastIntent: p["lastIntent"] as? String,
                toolCount: p["toolCount"] as? Int ?? 0,
                tokens: p["tokens"] as? Int ?? 0,
                cost: (p["cost"] as? NSNumber)?.doubleValue ?? 0)
        } else if channel == "task:subagent:lifecycle", let id = data["id"] as? String {
            if let existing = progressMap[id] {
                progressMap[id] = SubagentProgress(id: existing.id, index: existing.index, task: existing.task,
                    description: existing.description, status: data["status"] as? String ?? existing.status,
                    currentTool: existing.currentTool, lastIntent: existing.lastIntent,
                    toolCount: existing.toolCount, tokens: existing.tokens, cost: existing.cost)
            } else {
                progressMap[id] = SubagentProgress(id: id, index: data["index"] as? Int ?? 0,
                    task: data["description"] as? String ?? "subagent", description: data["description"] as? String,
                    status: data["status"] as? String ?? "started", currentTool: nil, lastIntent: nil,
                    toolCount: 0, tokens: 0, cost: 0)
            }
        }
        progress = progressMap.values.sorted { $0.index < $1.index }
    }

    private func applyEvent(_ e: [String: Any]?) {
        guard let e, let type = e["type"] as? String else { return }
        switch type {
        case "message_start", "message_update":
            if let m = e["message"] as? [String: Any], m["role"] as? String == "assistant" { stream = m; streamDone = false }
        case "message_end":
            if let m = e["message"] as? [String: Any], m["role"] as? String == "assistant" { stream = m; streamDone = true }
        case "tool_execution_start", "tool_execution_update":
            if let id = e["toolCallId"] as? String {
                activeTools.removeAll { $0.id == id }
                activeTools.append((id, e))
            }
        case "tool_execution_end":
            if let id = e["toolCallId"] as? String { activeTools.removeAll { $0.id == id } }
        case "agent_start": working = true
        case "agent_end": working = false
        default: break
        }
    }

    private func applyState(_ s: [String: Any]?) {
        guard let s else { return }
        working = s["isStreaming"] as? Bool ?? working
        queued = s["queuedMessageCount"] as? Int ?? queued
        if let n = s["sessionName"] as? String, !n.isEmpty { title = n }
        if let c = s["cwd"] as? String { cwd = c }
        if let level = s["thinkingLevel"] as? String { thinkingLevel = level }
        if let m = s["model"] as? [String: Any], let name = m["name"] as? String { modelName = name }
        if let usage = s["contextUsage"] as? [String: Any] {
            if let tokens = usage["tokens"] as? Int { tokensLabel = tokens >= 1000 ? "\(tokens / 1000)K" : "\(tokens)" }
            contextPercent = (usage["percent"] as? NSNumber)?.doubleValue
        }
        if let list = s["participants"] as? [[String: Any]] {
            participants = list.map { p in
                ParticipantInfo(name: p["name"] as? String ?? "peer",
                                role: p["role"] as? String ?? "guest",
                                readOnly: p["readOnly"] as? Bool ?? false)
            }
        }
    }

    private func end(_ reason: String) {
        if phase == "ended" { return }
        phase = "ended"
        endedReason = reason
        working = false
        socket.close()
        rebuild()
    }

    // ── projection: omp transcript → [UITurn] ─────────────────────────────────

    private func rebuild() {
        var out: [UITurn] = []
        var toolIndex: [String: Int] = [:]   // toolCallId → index in `out`

        for entry in entries {
            guard let type = entry["type"] as? String else { continue }
            let eid = entry["id"] as? String ?? UUID().uuidString
            switch type {
            case "custom_message" where (entry["customType"] as? String) == "collab-prompt":
                out.append(userTurn(id: eid, content: entry["content"]))
            case "message":
                guard let msg = entry["message"] as? [String: Any], let role = msg["role"] as? String else { break }
                switch role {
                case "user":
                    out.append(userTurn(id: eid, content: msg["content"]))
                case "assistant":
                    for (i, block) in (msg["content"] as? [[String: Any]] ?? []).enumerated() {
                        switch block["type"] as? String {
                        case "text":
                            let text = block["text"] as? String ?? ""
                            if !text.isEmpty { out.append(agentTurn(id: "\(eid)#\(i)", text: text)) }
                        case "toolCall":
                            let id = block["id"] as? String ?? "\(eid)#\(i)"
                            out.append(toolTurn(id: id, name: block["name"] as? String ?? "tool",
                                                args: block["arguments"], intent: block["intent"] as? String))
                            toolIndex[id] = out.count - 1
                        default: break   // thinking / redactedThinking — skipped
                        }
                    }
                case "toolResult":
                    let id = msg["toolCallId"] as? String ?? eid
                    let isError = msg["isError"] as? Bool ?? false
                    if let idx = toolIndex[id] {
                        fillResult(&out[idx], content: msg["content"], isError: isError)
                    } else {
                        var turn = toolTurn(id: id, name: msg["toolName"] as? String ?? "tool", args: nil, intent: nil)
                        fillResult(&turn, content: msg["content"], isError: isError)
                        out.append(turn)
                    }
                default: break
                }
            case "compaction":
                out.append(UITurn.sys("compaction", (entry["shortSummary"] as? String ?? "COMPACTING CONTEXT").uppercased()))
            default: break
            }
        }

        // Executing tools with no result entry yet.
        for (id, tool) in activeTools where toolIndex[id] == nil {
            var turn = toolTurn(id: id, name: tool["toolName"] as? String ?? "tool", args: tool["args"], intent: tool["intent"] as? String)
            turn.pending = true
            out.append(turn)
        }

        // Streaming assistant ghost, until its entry lands.
        if let s = stream {
            let text = ((s["content"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }).joined(separator: "\n")
            if !text.isEmpty {
                var turn = agentTurn(id: "stream", text: text)
                turn.streaming = !streamDone
                out.append(turn)
            }
        }

        // Pending host ask.
        if let req = uiRequest, let reqId = req["reqId"] as? Int {
            var turn = UITurn(id: "ui-\(reqId)", type: .ask)
            turn.reqId = reqId
            turn.question = req["title"] as? String ?? "The host is asking…"
            turn.options = (req["options"] as? [Any] ?? []).map { opt in
                if let s = opt as? String { return s }
                if let d = opt as? [String: Any], let l = d["label"] as? String { return l }
                return "option"
            }
            out.append(turn)
        }

        turns = out
        onChange?()
    }

    // ── turn builders ─────────────────────────────────────────────────────────

    private func userTurn(id: String, content: Any?) -> UITurn {
        var t = UITurn(id: id, type: .user)
        t.text = contentString(content)
        t.image = firstImage(content)
        return t
    }
    private func agentTurn(id: String, text: String) -> UITurn {
        var t = UITurn(id: id, type: .agent); t.text = text; return t
    }
    private func toolTurn(id: String, name: String, args: Any?, intent: String?) -> UITurn {
        var t = UITurn(id: id, type: .tool)
        t.kind = toolKind(name)
        t.head = name
        t.meta = argSummary(args) ?? intent ?? ""
        return t
    }
    private func fillResult(_ turn: inout UITurn, content: Any?, isError: Bool) {
        turn.pending = false
        if let img = firstImage(content) { turn.image = img }
        let text = contentString(content)
        if !text.isEmpty {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count == 1 && lines[0].count <= 80 && turn.meta.isEmpty { turn.meta = lines[0] }
            else { turn.lines = Array(lines.prefix(14)) }
        }
        if isError && turn.meta.isEmpty { turn.meta = "error" }
    }

    // ── content helpers ───────────────────────────────────────────────────────

    private func contentString(_ content: Any?) -> String {
        if let s = content as? String { return s }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
        }
        return ""
    }
    private func firstImage(_ content: Any?) -> String? {
        guard let arr = content as? [[String: Any]] else { return nil }
        for block in arr where block["type"] as? String == "image" {
            if let data = block["data"] as? String, let mime = block["mimeType"] as? String {
                return "data:\(mime);base64,\(data)"
            }
        }
        return nil
    }

    /// omp tool name → the app's tool-kind vocabulary (drives glyph + color).
    private func toolKind(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("read") || n.contains("cat") { return "read" }
        if n.contains("grep") || n.contains("search") || n.contains("glob") || n.contains("find") { return "search" }
        if n.contains("ast_edit") { return "ast_edit" }
        if n.contains("edit") || n.contains("write") || n.contains("apply") { return "edit" }
        if n.contains("bash") || n.contains("shell") || n.contains("exec") || n.contains("eval") { return "bash" }
        if n.contains("lsp") || n.contains("diagnos") { return "lsp" }
        if n.contains("task") || n.contains("agent") || n.contains("spawn") { return "task" }
        if n.contains("debug") || n.contains("dap") || n.contains("lldb") { return "debug" }
        if n.contains("inspect") { return "inspect" }
        if n.contains("image") || n.contains("photo") { return "image" }
        return n
    }

    private func argSummary(_ args: Any?) -> String? {
        guard let dict = args as? [String: Any] else { return nil }
        for key in ["path", "file", "filePath", "file_path", "command", "cmd", "pattern", "query", "url", "name"] {
            if let v = dict[key] as? String, !v.isEmpty { return v }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let s = String(data: data, encoding: .utf8), s.count <= 60 { return s }
        return nil
    }

    private func isAssistantMessage(_ entry: [String: Any]) -> Bool {
        entry["type"] as? String == "message" && (entry["message"] as? [String: Any])?["role"] as? String == "assistant"
    }
}
