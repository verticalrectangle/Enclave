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
    let session: Session

    private var revealTimer: Timer?
    private var streamTimer: Timer?
    private var revealCount: Int
    private var streamIdx = 0

    var isRunning: Bool { session.status == .running && !aborted }

    init(_ s: Session) {
        session = s
        turns = s.turns
        // running sessions reveal history progressively, then stream live activity
        revealCount = s.status == .running ? min(s.turns.count, 3) : s.turns.count
        if s.status == .running {
            turns = Array(s.turns.prefix(revealCount))
            startReveal()
        }
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
        aborted = true
        revealTimer?.invalidate(); streamTimer?.invalidate()
        turns.append(Sample.sys("stop", "STOPPED BY YOU"))
        // engine: bridge.abort()
    }

    func send(_ text: String, image: String?) {
        let steering = isRunning
        if isRunning { aborted = true; revealTimer?.invalidate(); streamTimer?.invalidate() }
        turns.append(Sample.user(text, image: image))
        turns.append(Sample.sys(steering ? "queued" : "sent", steering ? "QUEUED · STEERING THE TURN" : "SENT"))
        // engine: steering ? bridge.steer(text) : bridge.prompt(text, images: image.map { [$0] } ?? [])
    }

    func beginEdit(_ i: Int) { editingIndex = i }
    func cancelEdit() { editingIndex = nil }

    func resend(_ i: Int, text: String, image: String?) {
        var kept = Array(turns.prefix(i + 1))
        kept[i].text = text
        kept[i].image = image
        kept.append(Sample.sys("rewind", "REWOUND HERE · RE-RUNNING"))
        turns = kept
        editingIndex = nil
        // engine: bridge.rewind(to: turns[i].id); bridge.prompt(text, ...)
    }
}
