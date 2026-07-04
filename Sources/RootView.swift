//  RootView.swift
//  Native TabView — Sessions / Activity / Trust — with SF Symbol tab items, so the
//  bottom bar is the real iOS tab bar (Liquid Glass on iOS 26). Pair and Lock are
//  full-screen covers over the whole thing.

import SwiftUI

struct RootView: View {
    @EnvironmentObject var theme: ThemeStore
    @State private var tab = 0
    @State private var showPair = false
    @State private var showLock = false
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
        .fullScreenCover(isPresented: $showPair) { PairView { showPair = false }.environmentObject(theme) }
        .fullScreenCover(isPresented: $showLock) { LockScreenView { showLock = false }.environmentObject(theme) }
    }
}
