//  SessionVM.swift
//  Drives one open session's transcript + composer. In the mock it animates the
//  live stream, stop/abort, and message edit→rewind locally; when wired to the
//  engine each of these maps to an EngineBridge command (prompt/steer/abort/
//  approve/rewind) and `turns` is fed by EngineBridge.turns instead.

import SwiftUI
import Combine

@MainActor
final class SessionVM: ObservableObject {
    @Published var turns: [UITurn]
    @Published var aborted = false
    @Published var editingIndex: Int? = nil
    @Published private(set) var session: Session

    /// Non-nil when this session is backed by a live omp collab host.
    let live: GuestClient?

    private var revealTimer: Timer?
    private var streamTimer: Timer?
    private var revealCount: Int
    private var streamIdx = 0
    private let seed: Session

    var isRunning: Bool { live != nil ? live!.working : (session.status == .running && !aborted) }

    init(_ s: Session) {
        session = s
        seed = s
        live = nil
        turns = s.turns
        // running sessions reveal history progressively, then stream live activity
        revealCount = s.status == .running ? min(s.turns.count, 3) : s.turns.count
        if s.status == .running {
            turns = Array(s.turns.prefix(revealCount))
            startReveal()
        }
    }

    /// Live mode: transcript + status come from the collab guest client.
    init(live client: GuestClient, seed s: Session) {
        session = s
        seed = s
        live = client
        turns = []
        revealCount = 0
        client.onChange = { [weak self] in self?.syncLive() }
        client.connect()
        syncLive()
    }

    private func syncLive() {
        guard let live else { return }
        turns = live.turns
        let action: String
        switch live.phase {
        case "connecting", "waiting", "reconnecting": action = live.phase.uppercased() + "…"
        case "ended": action = "ENDED · \(live.endedReason ?? "session closed")"
        default: action = live.working ? "STREAMING" : (turns.contains { $0.type == .ask } ? "WAITING · ANSWER" : "LIVE")
        }
        session = Session(id: seed.id, repo: live.title, branch: live.readOnly ? "watch" : seed.branch,
                          dir: live.cwd, model: live.modelName, role: seed.role,
                          status: live.working ? .running : (live.phase == "ended" ? .idle : .waiting),
                          lastSeen: "live", action: action, tokens: live.tokensLabel, cost: live.costLabel, turns: [])
    }

    private func startReveal() {
        revealTimer = Timer.scheduledTimer(withTimeInterval: 0.62, repeats: true) { [weak self] tm in
            Task { @MainActor in
                guard let self else { return }
                if self.aborted { tm.invalidate(); return }
                if self.revealCount >= self.session.turns.count { tm.invalidate(); self.startStream(); return }
                self.turns.append(self.session.turns[self.revealCount]); self.revealCount += 1
            }
        }
    }
    private func startStream() {
        streamTimer = Timer.scheduledTimer(withTimeInterval: 2.4, repeats: true) { [weak self] tm in
            Task { @MainActor in
                guard let self else { return }
                if self.aborted || self.turns.count > 40 { tm.invalidate(); return }
                self.turns.append(Sample.liveStream[self.streamIdx % Sample.liveStream.count]); self.streamIdx += 1
            }
        }
    }

    func stop() {
        if let live { live.sendAbort(); return }
        aborted = true
        revealTimer?.invalidate(); streamTimer?.invalidate()
        turns.append(Sample.sys("stop", "STOPPED BY YOU"))
    }

    func send(_ text: String, image: String?) {
        if let live { live.sendPrompt(text); return }   // host echoes it back as an entry
        let steering = isRunning
        if isRunning { aborted = true; revealTimer?.invalidate(); streamTimer?.invalidate() }
        turns.append(Sample.user(text, image: image))
        turns.append(Sample.sys(steering ? "queued" : "sent", steering ? "QUEUED · STEERING THE TURN" : "SENT"))
    }

    func beginEdit(_ i: Int) { editingIndex = i }
    func cancelEdit() { editingIndex = nil }

    func resend(_ i: Int, text: String, image: String?) {
        if let live { live.sendPrompt(text); editingIndex = nil; return }   // guests re-prompt (no host rewind)
        var kept = Array(turns.prefix(i + 1))
        kept[i].text = text
        kept[i].image = image
        kept.append(Sample.sys("rewind", "REWOUND HERE · RE-RUNNING"))
        turns = kept
        editingIndex = nil
    }

    /// Answer a live host ask (select). `idx` is the chosen option.
    func answer(_ turn: UITurn, _ idx: Int) {
        guard let live, let reqId = turn.reqId, idx < turn.options.count else { return }
        live.answer(reqId: reqId, value: turn.options[idx])
    }
}
