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
                                Text("CLEAR ALL").font(.labl(9)).tracking(1.4).foregroundStyle(t.cAdvisor)
                            }
                        }
                        .textCase(nil)
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))
                    }
                }
            }

            Button { showPair = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                    Text("PAIR A SESSION").font(.labl(11)).tracking(1)
                }
                .foregroundStyle(t.txt).frame(maxWidth: .infinity).padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.lineStrong))
            }.plainRow(top: 14, bottom: 20)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(t.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.immediately)
        .refreshable { app.refreshLiveness() }
        .tint(t.accent)
        .task { app.refreshLiveness() }
    }

    @ViewBuilder private func sessionRow(_ s: JoinedSession) -> some View {
        card(s, live: app.live[s.id] == true)
            .opacity(app.live[s.id] == true ? 1 : 0.6)
            .plainRow(top: 5, bottom: 5)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { app.remove(s) } label: { Label("Delete", systemImage: "trash") }
            }
    }

    private var deviceName: String { UIDevice.current.name }

    private func activeAction(for s: JoinedSession, live: Bool) -> String? {
        guard live, app.active?.sessionId == s.id, app.active?.working == true else { return nil }
        return "REPLYING"
    }
    private var liveSessions: [JoinedSession] {
        app.sessions.filter { app.live[$0.id] == true }.sorted { $0.savedAt > $1.savedAt }
    }
    private var offlineSessions: [JoinedSession] {
        app.sessions.filter { app.live[$0.id] != true }.sorted { $0.savedAt > $1.savedAt }
    }
    // One ordered list (live first) so a session moving between groups keeps a
    // stable identity and its `live` value re-derives instead of going stale.
    private var ordered: [JoinedSession] { liveSessions + offlineSessions }
    private var firstOfflineId: String? { offlineSessions.first?.id }

    @ViewBuilder private func card(_ s: JoinedSession, live: Bool) -> some View {
        let action = activeAction(for: s, live: live)
        Button { app.connect(link: s.link, name: deviceName) } label: {
            JoinedCard(session: s, t: t, live: live, action: action)
        }
        .press()
        .contextMenu {
            Button(role: .destructive) { app.remove(s) } label: { Label("Remove", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            LogoMark(t: t, size: 44, color: t.txtGhost)
            Text("NO SESSIONS YET").font(.labl(10)).tracking(2).foregroundStyle(t.txtMuted)
            (Text("Share a session from your coding agent — run ").foregroundStyle(t.txtMuted) + Text("omp /collab").font(.term(15)).foregroundStyle(t.accent) + Text(" on the box — then pair with the link.").foregroundStyle(t.txtMuted))
                .font(.bodyF(13.5)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48).padding(.horizontal, 24)
    }
}

/// Strip a List row down to the app's look: no separator, transparent background,
/// custom insets — so the List reads like the old card stack but gains swipe-to-delete.
private extension View {
    func plainRow(top: CGFloat = 0, leading: CGFloat = 16, bottom: CGFloat = 0, trailing: CGFloat = 16) -> some View {
        self.listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
    }
}

/// The Apple-Music-style search tab (a detached search button by the tabs). Filters
/// your joined sessions by title; tap a result to connect.
struct SearchView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var app: AppModel
    @State private var query = ""
    @FocusState private var focused: Bool
    private var t: Theme { theme.t }

    private var results: [JoinedSession] {
        let all = app.sessions.sorted { $0.savedAt > $1.savedAt }
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(t.txtMuted)
                TextField("", text: $query, prompt: Text("Search sessions").foregroundStyle(t.txtMuted))
                    .font(.bodyF(15)).foregroundStyle(t.txt).tint(t.accent)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .focused($focused).submitLabel(.search).onSubmit { focused = false }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(t.txtMuted) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10).glass(t, 14, flat: true)
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 11) {
                    if results.isEmpty {
                        Text(query.isEmpty ? "Your sessions appear here." : "No sessions match “\(query)”.")
                            .font(.bodyF(14)).foregroundStyle(t.txtMuted).frame(maxWidth: .infinity).padding(.vertical, 44)
                    }
                    ForEach(results) { s in
                        let live = app.live[s.id] == true
                        let action: String? = (live && app.active?.sessionId == s.id && app.active?.working == true) ? "REPLYING" : nil
                        Button { app.connect(link: s.link, name: UIDevice.current.name) } label: {
                            JoinedCard(session: s, t: t, live: live, action: action)
                                .opacity(live ? 1 : 0.6)
                        }
                        .press()
                        .contextMenu {
                            Button(role: .destructive) { app.remove(s) } label: { Label("Remove", systemImage: "trash") }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(t.bg.ignoresSafeArea())
        .tint(t.accent)
        .onAppear { focused = true }
    }
}

struct JoinedCard: View {
    let session: JoinedSession; let t: Theme; var live: Bool = false
    var action: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(session.title).font(.disp(17)).foregroundStyle(t.txt).textCase(.uppercase).lineLimit(1)
                    .padding(.leading, 5)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(t.txtGhost)
            }.padding(.bottom, 11)
            HStack(spacing: 6) {
                if let enh = session.enhanced {
                    Text(enh ? "ENCLAVE" : "COLLAB").font(.term(12)).foregroundStyle(t.txtMuted)
                }
                Text(session.readOnly ? "WATCH" : "CONTROL").font(.term(12)).foregroundStyle(t.txtMuted)
                Text(session.relay).font(.term(12)).foregroundStyle(t.txtMuted)
                if let action {
                    Text(action).font(.term(12)).foregroundStyle(t.accent)
                }
                if !live { Text("offline").font(.term(12)).foregroundStyle(t.txtGhost) }
            }
        }
        .padding(13)
        .glass(t, 16)
    }
}
