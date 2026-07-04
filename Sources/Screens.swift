//  Screens.swift
//  ActivityView — live subagent fan-out for the connected session (agents +
//  task:subagent:* bus), with transcript drill-in (fetch-transcript) and
//  kill/revive/chat (agent-cmd). PairView — paste a /collab link and join.
//  (The lock-screen surface is now a real ActivityKit Live Activity — see
//  Shared/EnclaveActivity.swift + the EnclaveWidgets extension.)

import SwiftUI
import UIKit

// MARK: - Activity (live subagents)

struct ActivityView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var app: AppModel
    private var t: Theme { theme.t }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LIVE · THIS SESSION").font(.labl(9)).tracking(1.6).foregroundStyle(t.txtLabel)
                        Text("Activity").font(.disp(40)).foregroundStyle(t.txt).textCase(.uppercase)
                    }.padding(.bottom, 3)
                    if let client = app.active {
                        ActivityLive(client: client, t: t)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg").font(.system(size: 30)).foregroundStyle(t.txtGhost)
                            Text("NOT CONNECTED").font(.labl(10)).tracking(2).foregroundStyle(t.txtMuted)
                            Text("Join a session to watch its agents and subagent fan-out.")
                                .font(.bodyF(13)).foregroundStyle(t.txtMuted).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                }.padding(16)
            }
            .background(t.bg.ignoresSafeArea())
            .toolbarBackground(t.bg, for: .navigationBar)
        }.tint(t.accent)
    }
}

struct ActivityLive: View {
    @ObservedObject var client: GuestClient
    let t: Theme
    @State private var drill: AgentInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(client.agents) { a in
                AgentRow(agent: a, progress: client.progress.first { $0.id == a.id || $0.task == a.displayName }, t: t)
                    .contentShape(Rectangle())
                    .onTapGesture { if a.hasSessionFile { drill = a } }
            }
            if client.agents.isEmpty && client.progress.isEmpty {
                Text("No agents running.").font(.term(14)).foregroundStyle(t.txtMuted).padding(.vertical, 20)
            }
            // Subagent progress not tied to a registered agent row.
            ForEach(client.progress.filter { p in !client.agents.contains { $0.id == p.id } }) { p in
                ProgressRow(p: p, t: t)
            }
        }
        .sheet(item: $drill) { a in SubagentSheet(client: client, agent: a) }
    }
}

struct AgentRow: View {
    let agent: AgentInfo; let progress: SubagentProgress?; let t: Theme
    private var running: Bool { agent.status == "running" }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: agent.kind == "main" ? "cpu" : "circle.grid.cross").font(.system(size: 16)).foregroundStyle(running ? t.accent : t.txtMuted)
                Text(agent.displayName).font(.disp(15)).foregroundStyle(t.txt).textCase(.uppercase).lineLimit(1)
                Spacer()
                if running { LiveDot(t: t) } else { Text(agent.status).font(.labl(9)).foregroundStyle(agent.status == "aborted" ? t.cAdvisor : t.txtMuted) }
            }.padding(.bottom, progress == nil ? 0 : 9)
            if let p = progress {
                Text(p.currentTool.map { "› \($0)" } ?? p.task).font(.term(13)).foregroundStyle(t.txtMuted).lineLimit(1).padding(.bottom, 6)
                HStack(spacing: 8) {
                    Text("\(p.toolCount) tools").font(.term(12)).foregroundStyle(t.txtGhost)
                    Text("\(p.tokens >= 1000 ? "\(p.tokens/1000)K" : "\(p.tokens)") tok").font(.term(12)).foregroundStyle(t.txtGhost)
                    if p.cost > 0 { Text(String(format: "$%.2f", p.cost)).font(.term(12)).foregroundStyle(t.txtGhost) }
                    Spacer()
                    if agent.hasSessionFile { Text("transcript ›").font(.labl(9)).foregroundStyle(t.accent) }
                }
            }
        }.padding(13).glass(t, 4)
    }
}

struct ProgressRow: View {
    let p: SubagentProgress; let t: Theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "circle.grid.cross").font(.system(size: 15)).foregroundStyle(t.cTask)
                Text(p.task).font(.disp(14)).foregroundStyle(t.txt).lineLimit(1)
                Spacer()
                Text(p.status).font(.labl(9)).foregroundStyle(p.status == "failed" || p.status == "aborted" ? t.cAdvisor : p.status == "completed" ? t.cOk : t.txtMuted)
            }
            if let d = p.description { Text(d).font(.term(13)).foregroundStyle(t.txtMuted).lineLimit(2) }
        }.padding(13).glass(t, 4, flat: true)
    }
}

// MARK: - Subagent drill-in (fetch-transcript + agent-cmd)

struct SubagentSheet: View {
    @ObservedObject var client: GuestClient
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) var dismiss
    let agent: AgentInfo
    @State private var text = ""
    @State private var loading = true
    @State private var chat = ""
    private var t: Theme { theme.t }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if loading { ProgressView().tint(t.accent).frame(maxWidth: .infinity).padding(.vertical, 30) }
                    else if text.isEmpty { Text("No transcript.").font(.term(14)).foregroundStyle(t.txtMuted) }
                    else {
                        ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: true).enumerated()), id: \.offset) { _, line in
                            Text(String(line)).font(.term(12)).foregroundStyle(t.txtBody)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.padding(14)
            }
            .background(t.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("", text: $chat, prompt: Text("Message this subagent…").foregroundStyle(t.txtMuted))
                            .font(.bodyF(14)).foregroundStyle(t.txt).tint(t.accent)
                            .onSubmit(sendChat)
                        Button(action: sendChat) { Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold)).foregroundStyle(t.accent) }
                    }.padding(.horizontal, 10).padding(.vertical, 7).glass(t, 4)
                    HStack(spacing: 8) {
                        Button { client.sendAgentCmd("kill", agentId: agent.id); dismiss() } label: {
                            Text("KILL").font(.labl(10.5)).foregroundStyle(t.cAdvisor).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.cAdvisor.opacity(0.5)))
                        }.press()
                        Button { client.sendAgentCmd("revive", agentId: agent.id) } label: {
                            Text("REVIVE").font(.labl(10.5)).foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
                        }.press()
                    }
                }.padding(.horizontal, 12).padding(.bottom, 6).background(t.bg)
            }
            .navigationTitle(agent.displayName).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(t.txt) } } }
            .toolbarBackground(t.bg, for: .navigationBar)
        }
        .tint(t.accent).preferredColorScheme(theme.mode == .dark ? .dark : .light)
        .task {
            if let r = await client.fetchTranscript(agentId: agent.id, fromByte: 0) { text = r.text }
            loading = false
        }
    }

    private func sendChat() {
        let c = chat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return }
        client.sendAgentCmd("chat", agentId: agent.id, text: c); chat = ""
    }
}

// MARK: - Pair (paste a /collab link and join)

struct PairView: View {
    @EnvironmentObject var theme: ThemeStore
    let onClose: () -> Void
    var onConnect: (String) -> Void = { _ in }
    @State private var link = ""
    @State private var error: String?
    private var t: Theme { theme.t }

    private func connect() {
        let clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason = GuestClient.validate(clean) { error = reason; return }
        error = nil
        onConnect(clean)
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("PAIR A BOX").font(.labl(10)).tracking(2).foregroundStyle(t.txtLabel)
                        Spacer()
                        Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 20)).foregroundStyle(t.txt) }
                    }.padding(.bottom, 18)

                    Text("Join a\nsession.").font(.disp(34)).foregroundStyle(t.txt).textCase(.uppercase).padding(.bottom, 12)
                    (Text("Run ").foregroundStyle(t.txtBody) + Text("omp /collab").font(.term(15)).foregroundStyle(t.accent) + Text(" on the box and paste its link. Frames are sealed on-device — the relay never sees your keys.").foregroundStyle(t.txtBody))
                        .font(.bodyF(14)).padding(.bottom, 22)

                    Text("COLLAB LINK").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted).padding(.bottom, 8)
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 15)).foregroundStyle(t.txtMuted)
                        TextField("", text: $link, prompt: Text("my.omp.sh link or ws://…").foregroundStyle(t.txtMuted), axis: .vertical)
                            .font(.term(14)).foregroundStyle(t.txt).tint(t.accent)
                            .autocorrectionDisabled().textInputAutocapitalization(.never).lineLimit(1...4)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11).glass(t, 4, flat: true).padding(.bottom, 8)

                    Button(action: connect) {
                        HStack(spacing: 8) { Image(systemName: "bolt.fill"); Text("CONNECT").font(.labl(11)) }
                            .foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
                    }.press().disabled(link.trimmingCharacters(in: .whitespaces).isEmpty).padding(.bottom, error == nil ? 20 : 6)
                    if let err = error { Text(err).font(.term(12)).foregroundStyle(t.cAdvisor).padding(.bottom, 16) }

                    Text("A full link (control) can prompt and steer; a view link joins read-only. Access is set by the link, not chosen here.")
                        .font(.bodyF(12.5)).foregroundStyle(t.txtMuted)
                }.padding(22)
            }
        }
        .preferredColorScheme(theme.mode == .dark ? .dark : .light)
    }
}
