//  SessionsView.swift
//  The rooms you've joined. The collab protocol has no way to enumerate a host's
//  sessions, so this is the guest's own on-device list (AppModel.sessions): each
//  entry is a /collab link you've connected to. Tap to reconnect; Pair to add.

import SwiftUI
import UIKit

struct SessionsView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var app: AppModel
    @Binding var showPair: Bool
    private var t: Theme { theme.t }

    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 0) {
                Text("ENCLAVE").font(.labl(10)).tracking(2.5).foregroundStyle(t.txtLabel).padding(.bottom, 2)
                Text("Sessions").font(.disp(40)).foregroundStyle(t.txt).textCase(.uppercase)
            }.plainRow(top: 6, bottom: 10)

            if app.sessions.isEmpty {
                emptyState.plainRow(leading: 0, trailing: 0)
            } else {
                ForEach(liveSessions) { s in sessionRow(s) }
                if !offlineSessions.isEmpty {
                    Section {
                        ForEach(offlineSessions) { s in sessionRow(s) }
                    } header: {
                        HStack(spacing: 8) {
                            Text("OFFLINE").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted)
                            Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint)
                            Button { withAnimation { app.clearOffline() } } label: {
                                Text("CLEAR ALL").font(.labl(9)).tracking(1).foregroundStyle(t.cAdvisor)
                            }
                        }
                    }
                }
                pairButton.plainRow(top: 10, bottom: 16)
            }
        }
        .listStyle(.plain)
        .background(t.bg.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - derived lists

    private var liveSessions: [JoinedSession] {
        app.sessions.filter { app.live[$0.id] == true }.sorted { $0.savedAt > $1.savedAt }
    }
    private var offlineSessions: [JoinedSession] {
        app.sessions.filter { app.live[$0.id] != true }.sorted { $0.savedAt > $1.savedAt }
    }

    // MARK: - rows

    private func sessionRow(_ s: JoinedSession) -> some View {
        Button { app.connect(link: s.link, name: UIDevice.current.name) } label: {
            JoinedCard(session: s, t: t, state: app.state[s.id] ?? SessionState())
                .opacity(app.live[s.id] == true ? 1 : 0.6)
                .frame(maxWidth: sessionCardMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .plainRow(top: 8, bottom: 8, leading: 0, trailing: 0)
        .contextMenu {
            ColorMenu(session: s, t: t)
            Button(role: .destructive) { app.remove(s) } label: { Label("Remove", systemImage: "trash") }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { app.remove(s) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: - pair button

    private var pairButton: some View {
        Button { showPair = true } label: {
            HStack(spacing: 8) { Image(systemName: "plus"); Text("PAIR A SESSION").font(.labl(11)) }
                .foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 14)
                .glass(t, 16, active: true)
        }.press()
        .frame(maxWidth: sessionCardMaxWidth)
        .frame(maxWidth: .infinity)
    }

    // MARK: - empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            LogoMark(t: t, size: 44, color: t.txtGhost)
            Text("NO SESSIONS YET").font(.labl(10)).tracking(2).foregroundStyle(t.txtMuted)
            (Text("Share a session from your coding agent — run ").foregroundStyle(t.txtMuted) + Text("omp /collab").font(.term(15)).foregroundStyle(t.accent) + Text(" on the box — then pair with the link.").foregroundStyle(t.txtMuted))
                .font(.bodyF(13.5)).multilineTextAlignment(.center)
            pairButton.padding(.top, 6)
        }
        .padding(.horizontal, 24).padding(.vertical, 48)
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var app: AppModel
    @FocusState private var focused: Bool
    @State private var query = ""
    private var t: Theme { theme.t }

    private var results: [JoinedSession] {
        app.sessions.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.relay.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(t.txtGhost)
                TextField("Search sessions", text: $query)
                    .font(.bodyF(15))
                    .foregroundStyle(t.txt)
                    .focused($focused)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(t.txtGhost)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10).glass(t, 14, flat: true)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 11) {
                    ForEach(results) { s in
                        Button { app.connect(link: s.link, name: UIDevice.current.name) } label: {
                            JoinedCard(session: s, t: t, state: app.state[s.id] ?? SessionState())
                                .opacity(app.live[s.id] == true ? 1 : 0.6)
                        }
                        .plainRow(leading: 0, trailing: 0)
                        .contextMenu {
                            ColorMenu(session: s, t: t)
                            Button(role: .destructive) { app.remove(s) } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 20)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .tint(t.accent)
        .onAppear { focused = true }
    }
}

/// Color tag picker for a session card.
private struct ColorMenu: View {
    let session: JoinedSession
    let t: Theme
    @EnvironmentObject var app: AppModel

    var body: some View {
        Menu {
            ForEach(SessionColor.allCases) { color in
                Button { app.setTagColor(color, for: session.id) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(color.color(in: t)).frame(width: 12, height: 12)
                        Text(label(for: color)).font(.bodyF(14))
                        Spacer()
                        if session.tagColor == color {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
            }
        } label: {
            Label("Color", systemImage: "paintpalette")
        }
    }

    private func label(for color: SessionColor) -> String {
        switch color {
        case .default: return "Default"
        case .accent: return "Accent"
        case .foam: return "Foam"
        case .iris: return "Iris"
        case .pine: return "Pine"
        case .rose: return "Rose"
        case .green: return "Green"
        }
    }
}

// MARK: - Joined card

struct JoinedCard: View {
    let session: JoinedSession
    let t: Theme
    let state: SessionState

    private var isLive: Bool { state.live }
    private var isReplying: Bool { state.live && state.working }
    private var statusText: String {
        isReplying ? "REPLYING" : (isLive ? "LIVE" : "OFFLINE")
    }
    private var statusColor: Color {
        isReplying ? t.accent : (isLive ? t.cOk : t.txtGhost)
    }
    private var statusIcon: String {
        isReplying ? "circle.dashed" : (isLive ? "circle.fill" : "network.slash")
    }
    private var iconColor: Color { session.tagColor.color(in: t) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 46pt Liquid Glass icon tile with etched Enclave logo + mode badge
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.clear)
                    .frame(width: 46, height: 46)
                    .glassEffect(
                        .regular.tint(iconColor.opacity(0.30)).interactive(),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        LogoMark(t: t, size: 24, color: iconColor)
                            .shadow(color: .black.opacity(t.mode == .dark ? 0.30 : 0.15), radius: 0.6, x: 0, y: 0.6)
                            .shadow(color: .white.opacity(t.mode == .dark ? 0.10 : 0.50), radius: 0.4, x: 0, y: -0.4)
                    }

                // read-only / control mode badge — ENLARGED
                Circle().fill(t.bg).frame(width: 18, height: 18)
                    .overlay(Circle().stroke(iconColor.opacity(0.60), lineWidth: 1))
                    .overlay(
                        Image(systemName: session.readOnly ? "eye" : "pen")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(iconColor)
                    )
                    .offset(x: 5, y: 5)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(session.title)
                        .font(.disp(17))
                        .foregroundStyle(t.txt)
                        .lineLimit(1)
                    Spacer()
                    Text(formatDate(session.savedAt))
                        .font(.term(12))
                        .foregroundStyle(t.txtGhost)
                }
                HStack(spacing: 6) {
                    Image(systemName: statusIcon).font(.system(size: 8)).foregroundStyle(statusColor)
                    Text(statusText).font(.term(12)).foregroundStyle(statusColor)
                    Text("·").font(.term(12)).foregroundStyle(t.txtGhost)
                    if let enh = session.enhanced {
                        Text(enh ? "ENCLAVE" : "COLLAB").font(.term(12)).foregroundStyle(t.txtMuted)
                        Text("·").font(.term(12)).foregroundStyle(t.txtGhost)
                    }
                    Text(session.relay).font(.term(12)).foregroundStyle(t.txtMuted)
                }
            }
        }
        .padding(13)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)
        if diff < 60 { return "now" }
        if diff < 3600 { return "\(Int(diff / 60))m" }
        if diff < 86400 { return "\(Int(diff / 3600))h" }
        if diff < 604800 { return "\(Int(diff / 86400))d" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

// MARK: - List row helper

extension View {
    func plainRow(
        top: CGFloat = 0,
        bottom: CGFloat = 0,
        leading: CGFloat = 16,
        trailing: CGFloat = 16
    ) -> some View {
        listRowSpacing(0)
            .listRowInsets(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Preview

#Preview {
    let t = Theme(.dark)
    return List {
        JoinedCard(
            session: JoinedSession(id: "wss://example.com/r/abc", link: "wss://example.com/r/abc", title: "Example", relay: "example.com", readOnly: false, savedAt: Date(), enhanced: true),
            t: t,
            state: SessionState()
        )
        .plainRow()
    }
    .listStyle(.plain)
    .background(t.bg)
}
