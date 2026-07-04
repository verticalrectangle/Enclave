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
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var t: Theme { theme.t }

    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("ENCLAVE").font(.labl(10)).tracking(2.5).foregroundStyle(t.txtLabel)
                        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 2)
                    Text("Sessions").font(.disp(40)).foregroundStyle(t.txt).textCase(.uppercase)
                        .padding(.horizontal, 16).padding(.bottom, 12)

                    if app.sessions.isEmpty {
                        emptyState
                    } else {
                        searchBar
                        if ordered.isEmpty {
                            Text("No sessions match “\(query)”.").font(.bodyF(14)).foregroundStyle(t.txtMuted)
                                .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
                        }
                        LazyVStack(spacing: 11) {
                            ForEach(ordered) { s in
                                if s.id == firstOfflineId {
                                    HStack(spacing: 8) {
                                        Text("OFFLINE").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted)
                                        Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint)
                                    }.padding(.top, 6)
                                }
                                card(s, live: app.live[s.id] == true)
                                    .opacity(app.live[s.id] == true ? 1 : 0.6)
                            }
                        }.padding(.horizontal, 16)
                    }

                    Button { showPair = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            Text("PAIR A SESSION").font(.labl(11)).tracking(1)
                        }
                        .foregroundStyle(t.txt).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.lineStrong))
                    }.padding(16)
                }
                .padding(.bottom, 20)
                .contentShape(Rectangle())
                .onTapGesture { searchFocused = false }   // tap off the field to dismiss
            }
            .background(t.bg.ignoresSafeArea())
            .scrollDismissesKeyboard(.immediately)        // …or drag the list
            .refreshable { app.refreshLiveness() }
            .tint(t.accent)
            .task { app.refreshLiveness() }
    }

    private var deviceName: String { UIDevice.current.name }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(t.txtMuted)
            TextField("", text: $query, prompt: Text("Search sessions").foregroundStyle(t.txtMuted))
                .font(.bodyF(15)).foregroundStyle(t.txt).tint(t.accent)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(t.txtMuted)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .glass(t, 14, flat: true)
        .padding(.horizontal, 16).padding(.bottom, 12)
    }

    private func matches(_ s: JoinedSession) -> Bool {
        query.isEmpty || s.title.localizedCaseInsensitiveContains(query)
    }
    private var liveSessions: [JoinedSession] {
        app.sessions.filter { app.live[$0.id] == true && matches($0) }.sorted { $0.savedAt > $1.savedAt }
    }
    private var offlineSessions: [JoinedSession] {
        app.sessions.filter { app.live[$0.id] != true && matches($0) }.sorted { $0.savedAt > $1.savedAt }
    }
    // One ordered list (live first) so a session moving between groups keeps a
    // stable identity and its `live` value re-derives instead of going stale.
    private var ordered: [JoinedSession] { liveSessions + offlineSessions }
    private var firstOfflineId: String? { offlineSessions.first?.id }

    @ViewBuilder private func card(_ s: JoinedSession, live: Bool) -> some View {
        Button { app.connect(link: s.link, name: deviceName) } label: {
            JoinedCard(session: s, t: t, live: live)
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

struct JoinedCard: View {
    let session: JoinedSession; let t: Theme; var live: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(live ? t.cOk : t.txtGhost).frame(width: 7, height: 7)
                Text(session.title).font(.disp(17)).foregroundStyle(t.txt).textCase(.uppercase).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(t.txtGhost)
            }.padding(.bottom, 11)
            HStack(spacing: 6) {
                if let enh = session.enhanced {
                    MetaChip(t: t, text: enh ? "enclave" : "collab", tint: enh ? t.accent : nil)
                }
                MetaChip(t: t, text: session.readOnly ? "watch" : "control")
                MetaChip(t: t, text: session.relay)
                Spacer()
                Text(live ? "tap to join" : "offline").font(.term(12)).foregroundStyle(t.txtGhost)
            }
        }
        .padding(13)
        .glass(t, 16)
    }
}
