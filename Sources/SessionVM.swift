//  SessionVM.swift
//  View model for one open session's transcript + composer. Backed entirely by
//  the live GuestClient: `turns` mirrors the projected transcript, and send/stop/
//  answer map to the guest frames (prompt / abort / ui-response). Guests cannot
//  rewind (host-only), so there is no edit path.

import SwiftUI
import Combine

@MainActor
final class SessionVM: ObservableObject {
    @Published var turns: [UITurn] = []
    @Published private(set) var session: Session

    let live: GuestClient
    private let seed: Session

    var isRunning: Bool { live.working }
    var readOnly: Bool { live.readOnly }

    init(live client: GuestClient, seed s: Session) {
        session = s
        seed = s
        live = client
        client.onChange = { [weak self] in self?.syncLive() }
        syncLive()
        // Dev seam: auto-send a prompt shortly after connect (streaming test / demo).
        if let p = ProcessInfo.processInfo.environment["ENCLAVE_COLLAB_PROMPT"], !p.isEmpty {
            Task { try? await Task.sleep(nanoseconds: 1_500_000_000); client.sendPrompt(p) }
        }
    }

    private func syncLive() {
        turns = live.turns
        let action: String
        switch live.phase {
        case "connecting", "waiting", "reconnecting": action = live.phase.uppercased() + "…"
        case "ended": action = "ENDED · \(live.endedReason ?? "session closed")"
        default: action = live.working ? "STREAMING" : (turns.contains { $0.type == .ask } ? "WAITING · ANSWER" : "LIVE")
        }
        session = Session(id: seed.id, repo: live.title, branch: live.readOnly ? "watch" : "control",
                          dir: live.cwd, model: live.modelName,
                          status: live.working ? .running : (live.phase == "ended" ? .idle : .waiting),
                          lastSeen: "live", action: action, tokens: live.tokensLabel, cost: live.costLabel)
    }

    func send(_ text: String, images: [(mime: String, base64: String)] = []) {
        guard !readOnly else { return }
        live.sendPrompt(text, images: images)   // host echoes it back as an entry
    }

    func stop() { guard !readOnly else { return }; live.sendAbort() }

    /// Answer a live host ask (select). `idx` is the chosen option.
    func answer(_ turn: UITurn, _ idx: Int) {
        guard !readOnly, let reqId = turn.reqId, idx < turn.options.count else { return }
        live.answer(reqId: reqId, value: turn.options[idx])
    }
}
