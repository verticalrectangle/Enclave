//  RootView.swift
//  Native TabView — Sessions / Activity / Trust — with SF Symbol tab items, so the
//  bottom bar is the real iOS tab bar (Liquid Glass on iOS 26). Pair and Lock are
//  full-screen covers over the whole thing.

import SwiftUI
import UIKit

/// A connected live collab session, presented full-screen over the tabs.
struct LiveSession: Identifiable {
    let id = UUID()
    let client: GuestClient
    let seed: Session
}

struct RootView: View {
    @EnvironmentObject var theme: ThemeStore
    @State private var tab = 0
    @State private var showPair = false
    @State private var showLock = false
    @State private var liveSession: LiveSession?
    private var t: Theme { theme.t }

    var body: some View {
        TabView(selection: $tab) {
            SessionsView(showPair: $showPair, showLock: $showLock)
                .tabItem { Label("Sessions", systemImage: "square.stack.3d.up") }.tag(0)
            ActivityView()
                .tabItem { Label("Activity", systemImage: "waveform.path.ecg") }.tag(1)
            TrustView()
                .tabItem { Label("Trust", systemImage: "checkmark.shield") }.tag(2)
        }
        .tint(t.accent)
        .preferredColorScheme(theme.mode == .dark ? .dark : .light)
        .fullScreenCover(isPresented: $showPair) {
            PairView(onClose: { showPair = false }, onConnect: { session in
                showPair = false
                liveSession = session
            }).environmentObject(theme)
        }
        .fullScreenCover(isPresented: $showLock) { LockScreenView { showLock = false }.environmentObject(theme) }
        .task {
            // Launch seam / deep-link: auto-join a collab session from the
            // ENCLAVE_COLLAB_LINK env var (used for scripted end-to-end testing).
            guard liveSession == nil,
                  let link = ProcessInfo.processInfo.environment["ENCLAVE_COLLAB_LINK"],
                  GuestClient.validate(link) == nil,
                  let client = GuestClient(link: link, name: UIDevice.current.name)
            else { return }
            let seed = Session(id: "live", repo: "connecting…", branch: "collab", dir: "~", model: "—",
                               role: "default", status: .waiting, lastSeen: "live", action: "CONNECTING…",
                               tokens: "—", cost: "—", turns: [])
            liveSession = LiveSession(client: client, seed: seed)
        }
        .fullScreenCover(item: $liveSession) { session in
            NavigationStack {
                EditorView(live: session.client, seed: session.seed)
                    .environmentObject(theme)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { session.client.close(); liveSession = nil } label: {
                                HStack(spacing: 5) { Image(systemName: "chevron.left"); Text("Leave") }.foregroundStyle(t.accent)
                            }
                        }
                    }
            }
            .tint(t.accent)
            .preferredColorScheme(theme.mode == .dark ? .dark : .light)
        }
    }
}
