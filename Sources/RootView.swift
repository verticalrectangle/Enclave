//  RootView.swift
//  Native TabView — Sessions / Activity / Trust. AppModel holds the guest's saved
//  rooms and the one live connection, so Activity/Trust read live frames too.
//  A guest joins one omp session per link; there is no session enumeration in the
//  collab protocol, so "Sessions" is the rooms you've joined, stored on-device.

import SwiftUI
import UIKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var sessions: [JoinedSession]
    @Published var active: GuestClient?
    @Published var showEditor = false

    private let key = "enclave.sessions"
    private let liveActivity = LiveActivityController()
    private var cancellable: AnyCancellable?
    private var lastAskReqId: Int?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([JoinedSession].self, from: data) {
            sessions = list
        } else { sessions = [] }
    }

    @discardableResult
    func connect(link: String, name: String) -> Bool {
        guard let client = GuestClient(link: link, name: name) else { return false }
        active = client
        client.connect()
        showEditor = true
        upsert(JoinedSession(id: link, link: link, title: "omp session",
                             relay: client.relay, readOnly: client.readOnly, savedAt: Date()))
        // Drive the Live Activity + ask notifications from live frames.
        Notifier.requestAuth()
        lastAskReqId = nil
        cancellable = client.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.onClientChanged() }
        return true
    }

    private func onClientChanged() {
        guard let c = active else { return }
        if c.phase == "ended" { liveActivity.end() }
        else { liveActivity.sync(sessionId: c.sessionId, state: LiveActivityController.state(from: c)) }
        // Local notification the first time each host ask appears.
        if let ask = c.turns.last(where: { $0.type == .ask }), let rq = ask.reqId, rq != lastAskReqId {
            lastAskReqId = rq
            Notifier.post(title: c.title,
                          body: ask.question.isEmpty ? "The host is asking for your input." : ask.question,
                          id: "ask-\(rq)")
        }
    }

    func leave() {
        if let c = active, let link = connectedLink, let i = sessions.firstIndex(where: { $0.link == link }) {
            sessions[i].title = c.title
            sessions[i].readOnly = c.readOnly
            save()
        }
        cancellable?.cancel(); cancellable = nil
        lastAskReqId = nil
        liveActivity.end()
        active?.close()
        active = nil
        showEditor = false
    }

    func remove(_ s: JoinedSession) { sessions.removeAll { $0.id == s.id }; save() }

    private var connectedLink: String?

    private func upsert(_ s: JoinedSession) {
        connectedLink = s.link
        if let i = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[i].savedAt = s.savedAt; sessions[i].relay = s.relay; sessions[i].readOnly = s.readOnly
        } else {
            sessions.insert(s, at: 0)
        }
        save()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct RootView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var app: AppModel
    @State private var tab = 0
    @State private var showPair = false
    private var t: Theme { theme.t }

    var body: some View {
        TabView(selection: $tab) {
            SessionsView(showPair: $showPair)
                .tabItem { Label("Sessions", systemImage: "square.stack.3d.up") }.tag(0)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }.tag(1)
            TrustView()
                .tabItem { Label("Trust", systemImage: "checkmark.shield") }.tag(2)
        }
        .tint(t.accent)
        .preferredColorScheme(theme.mode == .dark ? .dark : .light)
        .fullScreenCover(isPresented: $showPair) {
            PairView(onClose: { showPair = false },
                     onConnect: { link in showPair = false; app.connect(link: link, name: UIDevice.current.name) })
                .environmentObject(theme)
        }
        .fullScreenCover(isPresented: $app.showEditor) {
            if let client = app.active {
                NavigationStack {
                    EditorView(client: client)
                        .environmentObject(theme)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { app.leave() } label: {
                                    HStack(spacing: 5) { Image(systemName: "chevron.left"); Text("Leave") }.foregroundStyle(t.accent)
                                }
                            }
                        }
                }
                .tint(t.accent)
                .preferredColorScheme(theme.mode == .dark ? .dark : .light)
            }
        }
        .task {
            // Launch seam / deep-link: auto-join a collab session from an env var.
            guard app.active == nil,
                  let link = ProcessInfo.processInfo.environment["ENCLAVE_COLLAB_LINK"]
            else { return }
            app.connect(link: link, name: UIDevice.current.name)
        }
    }
}
