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

    private let key = "enclave.sessions"
    private let liveActivity = LiveActivityController()
    private var cancellable: AnyCancellable?
    private var wasWorking = false
    private var notifiedAsks: Set<String> = []
    private var lastDoneTurnCount = -1

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([JoinedSession].self, from: data) {
            sessions = list
        } else { sessions = [] }
        tab = Int(ProcessInfo.processInfo.environment["ENCLAVE_TAB"] ?? "") ?? 0
    }

    @discardableResult
    func connect(link: String, name: String) -> Bool {
        guard let client = GuestClient(link: link, name: name) else { return false }
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
                Notifier.post(title: c.title.isEmpty ? "omp session" : c.title,
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
                    Notifier.post(title: c.title.isEmpty ? "omp session" : c.title,
                                  body: ask.question.isEmpty ? "The host is asking for your input." : ask.question,
                                  id: "ask-\(rq)")
                }
            }
        }
    }

    func leave() {
        guard active != nil else { return }   // idempotent: Leave button + onDisappear both call this
        if let c = active, c.welcomed, let link = connectedLink, let i = sessions.firstIndex(where: { $0.link == link }) {
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
        connectedLink = nil
        showEditor = false
        refreshLiveness()   // re-probe now that we've left
    }

    func remove(_ s: JoinedSession) { sessions.removeAll { $0.id == s.id }; live[s.id] = nil; save() }

    /// Ping each saved room's relay status endpoint to see if a host is connected.
    /// Sessions whose relay has no status endpoint (or is unreachable) read offline.
    func refreshLiveness() {
        let connected = connectedLink
        for s in sessions {
            if s.link == connected { live[s.id] = active?.welcomed ?? false; continue }  // in it → live iff a host answered
            guard let url = statusURL(for: s.link) else { live[s.id] = false; continue }
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
                await MainActor.run { self?.live[s.id] = isLive }
            }
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
    }
    private func save() {
        if let data = try? JSONEncoder().encode(sessions) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// The persistent top bar shared by all three tabs: the Enclave mark on the left
/// (taps back to the first tab) and the appearance toggle on the right.
struct EnclaveTopBar: ViewModifier {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var app: AppModel
    func body(content: Content) -> some View {
        let t = theme.t
        return content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { app.tab = 0 } label: { LogoMark(t: t, size: 22, color: t.txt) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { theme.toggle() } label: {
                    Image(systemName: theme.effective == .dark ? "sun.max" : "moon").foregroundStyle(t.txtMuted)
                }
            }
        }
    }
}
extension View {
    func enclaveTopBar() -> some View { modifier(EnclaveTopBar()) }
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
                topBar
                TabView(selection: $app.tab) {
                    SessionsView(showPair: $showPair)
                        .tabItem { Label("Sessions", systemImage: "square.stack.3d.up") }.tag(0)
                    ActivityView()
                        .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }.tag(1)
                    TrustView()
                        .tabItem { Label("Trust", systemImage: "checkmark.shield") }.tag(2)
                }
            }
            .background(t.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)   // we draw our own pinned top bar
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
                         onConnect: { link in showPair = false; app.connect(link: link, name: UIDevice.current.name) })
                    .environmentObject(theme)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .tint(t.accent)
        .onChange(of: colorScheme, initial: true) { _, new in theme.systemDark = (new == .dark) }
        .task {
            // Launch seam / deep-link: auto-join a collab session from an env var.
            guard app.active == nil,
                  let link = ProcessInfo.processInfo.environment["ENCLAVE_COLLAB_LINK"]
            else { return }
            app.connect(link: link, name: UIDevice.current.name)
        }
    }

    /// Pinned above the tabs (outside the TabView) so it stays put as you swipe tabs,
    /// just like the bottom tab bar. The mark taps back to the first tab.
    private var topBar: some View {
        HStack {
            Button { app.tab = 0 } label: { LogoMark(t: t, size: 22, color: t.txt) }
            Spacer()
            Button { theme.toggle() } label: {
                Image(systemName: theme.effective == .dark ? "sun.max" : "moon").font(.system(size: 17)).foregroundStyle(t.txtMuted)
            }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
        .background(t.bg)
    }
}
