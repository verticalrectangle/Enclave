//  SessionsView.swift
//  Project library. Large title, sort chips, glass session cards with the live
//  current-action line. NavigationStack pushes EditorView; the native tab bar and
//  large-title behavior come from SwiftUI.

import SwiftUI

struct SessionsView: View {
    @EnvironmentObject var theme: ThemeStore
    @Binding var showPair: Bool
    @Binding var showLock: Bool
    @State private var sort: Sort = .recent
    private var t: Theme { theme.t }

    enum Sort: String, CaseIterable { case recent = "Recent", name = "Name", fx = "Cost" }

    private var sessions: [Session] {
        switch sort {
        case .recent: return Sample.sessions
        case .name: return Sample.sessions.sorted { $0.repo < $1.repo }
        case .fx: return Sample.sessions.sorted { $0.cost > $1.cost }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Sessions").font(.disp(40)).foregroundStyle(t.txt).textCase(.uppercase)
                        }
                        Spacer()
                        Text(Sample.host.name).font(.term(16)).foregroundStyle(t.accent)
                    }
                    .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)

                    HStack(spacing: 6) {
                        ForEach(Sort.allCases, id: \.self) { s in
                            Button { sort = s } label: { Chip(t: t, text: s.rawValue, on: sort == s) }
                        }
                        Spacer()
                    }.padding(.horizontal, 16).padding(.bottom, 14)

                    LazyVStack(spacing: 11) {
                        ForEach(sessions) { s in
                            NavigationLink { EditorView(s).environmentObject(theme) } label: { SessionCard(session: s, t: t) }
                        }
                    }.padding(.horizontal, 16)

                    Button { showPair = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            Text("PAIR A BOX").font(.labl(11)).tracking(1)
                        }
                        .foregroundStyle(t.txt).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.lineStrong))
                    }.padding(16)
                }
                .padding(.bottom, 20)
            }
            .background(t.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 9) { LogoMark(t: t, size: 22, color: t.txt); Text("ENCLAVE").font(.disp(16)).foregroundStyle(t.txt) }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showLock = true } label: { Image(systemName: "lock").foregroundStyle(t.txtMuted) }
                    Button { theme.toggle() } label: { Image(systemName: theme.mode == .dark ? "sun.max" : "moon").foregroundStyle(t.txtMuted) }
                }
            }
            .toolbarBackground(t.bg, for: .navigationBar)
        }
        .tint(t.accent)
    }
}

struct SessionCard: View {
    let session: Session; let t: Theme
    private var statusColor: Color { session.status == .running ? t.accent : session.status == .waiting ? t.cAdvisor : t.txtGhost }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if session.status == .running { LiveDot(t: t) }
                else { Circle().fill(statusColor).frame(width: 7, height: 7) }
                Text(session.repo).font(.disp(17)).foregroundStyle(t.txt).textCase(.uppercase)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(t.txtGhost)
            }.padding(.bottom, 9)
            Text("\(session.status != .idle ? "▶ " : "")\(session.action)")
                .font(.term(14)).foregroundStyle(session.status == .idle ? t.txtMuted : t.accent).lineLimit(1)
                .padding(.bottom, 11)
            HStack(spacing: 6) {
                MetaChip(t: t, text: session.branch)
                MetaChip(t: t, text: session.model)
                Spacer()
                Text(session.lastSeen).font(.term(12)).foregroundStyle(t.txtGhost)
            }
        }
        .padding(13)
        .glass(t, 4)
    }
}
