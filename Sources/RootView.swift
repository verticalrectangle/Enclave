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
    @Published var tab = 0          // selected main tab; the logo button jumps here to 0
    @Published var live: [String: Bool] = [:]   // session.id → host currently connected
    @Published var state: [String: SessionState] = [:] // session.id → richer background state

    private let key = "enclave.sessions"
    private let liveActivity = LiveActivityController()
    private var cancellable: AnyCancellable?
    private var wasWorking = false
    private var notifiedAsks: Set<String> = []
    private var lastDoneTurnCount = -1
    private var clients: [String: GuestClient] = [:]    // background watchers
    private var watchers: [String: AnyCancellable] = [:]  // objectWillChange subscriptions

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([JoinedSession].self, from: data) {
            sessions = list
        } else { sessions = [] }
        tab = Int(ProcessInfo.processInfo.environment["ENCLAVE_TAB"] ?? "") ?? 0
    }

    @discardableResult
    func connect(link: String, name: String, paired: Bool = false) -> Bool {
        stopWatcher(for: link)   // hand off from background watcher to active editor client
        guard let client = GuestClient(link: link, name: name) else { return false }
        client.justPaired = paired   // fresh QR pair → transcript shows a paired notice
        active = client
        client.connect()
        // Showcase/screenshot mode connects in the background so the tabs stay visible.
        showEditor = ProcessInfo.processInfo.environment["ENCLAVE_SHOWCASE"] != "1"
        upsert(JoinedSession(id: link, link: link, title: "live session",
                             relay: client.relay, readOnly: client.readOnly, savedAt: Date()))
        // Drive the Live Activity + ask notifications from live frames.
        if ProcessInfo.processInfo.environment["ENCLAVE_SCREENSHOT"] != "1" { Notifier.requestAuth() }
        wasWorking = false; lastDoneTurnCount = -1
        cancellable = client.objectWillChange.receive(on: RunLoop.main).sink { [weak self] in self?.onClientChanged() }
        return true
    }

    private func onClientChanged() {
        guard let c = active else { return }
        if let link = connectedLink, let i = sessions.firstIndex(where: { $0.link == link }) {
            updateState(sessions[i].id, from: c)
        }
        if c.phase == "ended" { liveActivity.end() }
        else { liveActivity.sync(sessionId: c.sessionId, state: LiveActivityController.state(from: c)) }
        // Only trust a WELCOMED connection (a host actually answered). Tapping a
        // dead room connects but never welcomes — don't overwrite the saved room's
        // title/badge with the client's pre-welcome defaults, and don't call it live.
        if let link = connectedLink, let i = sessions.firstIndex(where: { $0.link == link }) {
            live[sessions[i].id] = c.welcomed
            if c.welcomed {
                if !c.title.isEmpty, c.title != "live session", sessions[i].title != c.title { sessions[i].title = c.title; save() }
                if c.enhanced, sessions[i].enhanced != true { sessions[i].enhanced = true; save() }
            }
        }
        // Only notify while you're AWAY (locked / another app). Foreground banners
        // fired while you're watching the transcript — that's the "random" one.
        let away = UIApplication.shared.applicationState != .active

        // Agent finished a turn. Fire on the working true→false edge, deduped by the
        // turn count so a flickering state frame or a reconnect can't repeat it.
        if wasWorking && !c.working, c.turns.count != lastDoneTurnCount {
            lastDoneTurnCount = c.turns.count
            if away {
                let last = c.turns.last(where: { $0.type == .agent })?.text ?? ""
                Notifier.post(title: c.title.isEmpty ? "session" : c.title,
                              body: last.isEmpty ? "The agent finished." : String(last.prefix(140)),
                              id: "done-\(c.sessionId)-\(c.turns.count)")
            }
        }
        wasWorking = c.working

        // A host ask is waiting on you — once per (session, reqId), never on replay.
        if let ask = c.turns.last(where: { $0.type == .ask }), let rq = ask.reqId {
            let key = "\(c.sessionId)-\(rq)"
            if !notifiedAsks.contains(key) {
                notifiedAsks.insert(key)
                if away {
                    Notifier.post(title: c.title.isEmpty ? "session" : c.title,
                                  body: ask.question.isEmpty ? "The host is asking for your input." : ask.question,
                                  id: "ask-\(rq)")
                }
            }
        }
    }

    func leave() {
        guard active != nil else { return }   // idempotent: Leave button + onDisappear both call this
        let leftLink = connectedLink
        if let c = active, c.welcomed, let link = leftLink, let i = sessions.firstIndex(where: { $0.link == link }) {
            sessions[i].title = c.title
            sessions[i].readOnly = c.readOnly
            sessions[i].enhanced = c.enhanced   // authoritative once actually welcomed
            save()
        }
        cancellable?.cancel(); cancellable = nil
        wasWorking = false; lastDoneTurnCount = -1
        liveActivity.end()
        active?.close()
        active = nil
        showEditor = false
        // Hand off the just-left session to a background watcher so the list stays live.
        if let link = leftLink, let s = sessions.first(where: { $0.link == link }) {
            connectedLink = nil
            startWatcher(for: s)
        } else {
            connectedLink = nil
        }
        refreshLiveness()
    }

    func remove(_ s: JoinedSession) { sessions.removeAll { $0.id == s.id }; live[s.id] = nil; state[s.id] = nil; stopWatcher(for: s.id); save() }

    func setTagColor(_ color: SessionColor, for id: String) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].tagColor = color
        save()
    }

    /// Drop every offline session in one go (keeps the one you're connected to).
    func clearOffline() {
        let keep = connectedLink
        for s in sessions where live[s.id] != true && s.link != keep {
            live[s.id] = nil
            state[s.id] = nil
            stopWatcher(for: s.id)
        }
        sessions.removeAll { live[$0.id] != true && $0.link != keep }
        save()
    }

    /// Ping each saved room's relay status endpoint to see if a host is connected.
    /// Live sessions also get a background GuestClient watcher so the list reflects
    /// realtime state (working, phase, title) without loading the full chat.
    func refreshLiveness() {
        let connected = connectedLink
        for s in sessions {
            if s.link == connected {
                live[s.id] = active?.welcomed ?? false
                syncWatchers()
                continue
            }
            guard let url = statusURL(for: s.link) else { live[s.id] = false; state[s.id] = SessionState(); syncWatchers(); continue }
            Task { [weak self] in
                var req = URLRequest(url: url)
                req.timeoutInterval = 6
                req.cachePolicy = .reloadIgnoringLocalCacheData
                var isLive = false
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200,
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    isLive = obj["live"] as? Bool ?? false
                }
                await MainActor.run {
                    self?.live[s.id] = isLive
                    if !isLive { self?.state[s.id] = SessionState() }
                    self?.syncWatchers()
                }
            }
        }
    }

    // MARK: - Background session watchers

    private var deviceName: String { UIDevice.current.name }

    private func startWatcher(for s: JoinedSession) {
        guard clients[s.id] == nil else { return }
        guard let client = GuestClient(link: s.link, name: deviceName) else { return }
        clients[s.id] = client
        client.connect()
        watchers[s.id] = client.objectWillChange.receive(on: RunLoop.main).sink { [weak self, weak client] in
            guard let self, let client else { return }
            self.updateState(s.id, from: client)
        }
    }

    private func stopWatcher(for id: String) {
        clients[id]?.close()
        clients[id] = nil
        watchers[id]?.cancel()
        watchers[id] = nil
    }

    private func syncWatchers() {
        for s in sessions {
            // Never run a background watcher for the currently active editor session.
            if s.link == connectedLink || clients[s.id] === active { stopWatcher(for: s.id); continue }
            if live[s.id] == true { startWatcher(for: s) } else { stopWatcher(for: s.id) }
        }
    }

    private func updateState(_ id: String, from client: GuestClient) {
        let welcomed = client.welcomed
        let phase = client.phase
        state[id] = SessionState(
            live: welcomed,
            working: client.working,
            phase: phase,
            title: client.title,
            lastSeen: Date()
        )
        live[id] = welcomed

        if welcomed, !client.title.isEmpty, client.title != "live session",
           let i = sessions.firstIndex(where: { $0.id == id }),
           sessions[i].title != client.title {
            sessions[i].title = client.title
            save()
        }

        if phase == "ended" {
            live[id] = false
            state[id] = SessionState()
            stopWatcher(for: id)
        }
    }

    private func statusURL(for link: String) -> URL? {
        guard case let .ok(parsed) = CollabLink.parse(link) else { return nil }
        var s = parsed.wsURL.absoluteString
        if s.hasPrefix("wss://") { s = "https://" + s.dropFirst(6) }
        else if s.hasPrefix("ws://") { s = "http://" + s.dropFirst(5) }
        return URL(string: s)
    }

    private var connectedLink: String?

    private func upsert(_ s: JoinedSession) {
        connectedLink = s.link
        if let i = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[i].savedAt = s.savedAt; sessions[i].relay = s.relay; sessions[i].readOnly = s.readOnly
        } else {
            sessions.insert(s, at: 0)
        }
        save()
        syncWatchers()
    }
    private func save() {
        if let data = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(data, forKey: key) }
    }
}

struct RootView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var app: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPair = ProcessInfo.processInfo.environment["ENCLAVE_SHOW_PAIR"] == "1"
    private var t: Theme { theme.t }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $app.tab) {
                    Tab("Sessions", systemImage: "square.stack.3d.up", value: 0) {
                        SessionsView(showPair: $showPair)
                    }
                    Tab("Activity", systemImage: "waveform.path.ecg", value: 1) {
                        ActivityView()
                    }
                    Tab("Trust", systemImage: "checkmark.shield", value: 2) {
                        TrustView()
                    }
                    Tab("Search", systemImage: "magnifyingglass", value: 3, role: .search) {
                        SearchView()
                    }
                }
            }
            .background(t.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { app.tab = 0 } label: {
                        LogoMark(t: t, size: 18, color: t.txt)
                            .frame(width: 38, height: 38)
                            .glass(t, 16)
                    }
                    .press()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { theme.toggle() } label: {
                        Image(systemName: theme.effective == .dark ? "sun.max" : "moon")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(t.txt)
                            .frame(width: 38, height: 38)
                            .glass(t, 16)
                    }
                    .press()
                }
            }
            // Native push: tapping a session (→ showEditor) slides the editor in from
            // the right; Leave / back-swipe pops it left.
            .navigationDestination(isPresented: $app.showEditor) {
                if let client = app.active {
                    EditorView(client: client)
                        .environmentObject(theme)
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { app.leave() } label: {
                                    HStack(spacing: 5) { Image(systemName: "chevron.left"); Text("Leave") }.foregroundStyle(t.accent)
                                }
                            }
                        }
                        .onDisappear { app.leave() }   // covers the native back-swipe
                }
            }
            .navigationDestination(isPresented: $showPair) {
                PairView(onClose: { showPair = false },
                         onConnect: { link in showPair = false; app.connect(link: link, name: UIDevice.current.name, paired: true) })
                    .environmentObject(theme)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .tint(t.accent)
        .onChange(of: colorScheme, initial: true) { _, new in theme.systemDark = (new == .dark) }
        .task {
            // Launch seam / deep-link: auto-join a collab session from an env var,
            // or fall back to the most recently saved session so the user lands in
            // the live room without an extra tap after a cold launch.
            guard app.active == nil else { return }
            if let link = ProcessInfo.processInfo.environment["ENCLAVE_COLLAB_LINK"] {
                app.connect(link: link, name: UIDevice.current.name)
            } else if let latest = app.sessions.max(by: { $0.savedAt < $1.savedAt }) {
                app.connect(link: latest.link, name: UIDevice.current.name)
            }
        }
    }

}
