//  EditorView.swift
//  The hero: live streaming transcript + composer. Backed by a GuestClient via
//  SessionVM. A guest can prompt, abort, and answer asks — nothing else the
//  collab wire doesn't expose. View (watch) links are read-only: the composer is
//  replaced by a read-only bar.

import SwiftUI

struct EditorView: View {
    @EnvironmentObject var theme: ThemeStore
    @StateObject var vm: SessionVM
    @State private var draft = ""
    @State private var viewer: String? = nil

    init(client: GuestClient) {
        let seed = Session(id: "live", repo: client.title, branch: client.readOnly ? "watch" : "control",
                           dir: client.cwd, model: client.modelName, status: .waiting,
                           lastSeen: "live", action: "CONNECTING…", tokens: "—", cost: "—")
        _vm = StateObject(wrappedValue: SessionVM(live: client, seed: seed))
    }
    private var t: Theme { theme.t }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                transcript
                composerStack
            }
        }
        .navigationTitle(vm.session.repo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(vm.session.repo).font(.disp(15)).foregroundStyle(t.txt).textCase(.uppercase).lineLimit(1)
                    Text("\(vm.session.dir) · \(vm.session.branch)").font(.term(12)).foregroundStyle(t.txtMuted).lineLimit(1)
                }
            }
        }
        .fullScreenCover(item: Binding(get: { viewer.map { IdStr($0) } }, set: { viewer = $0?.v })) { img in
            ImageViewer(src: img.v, label: "focused image") { viewer = nil }.environmentObject(theme)
        }
    }

    // MARK: transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(vm.turns.enumerated()), id: \.element.id) { _, turn in
                        TurnRow(turn: turn, t: t,
                                onImage: { viewer = $0 },
                                onAnswer: vm.readOnly ? nil : { vm.answer($0, $1) })
                            .id(turn.id)
                    }
                    if vm.isRunning { ThinkingLine(t: t).id("think") }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: vm.turns.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: composer

    private var composerStack: some View {
        VStack(spacing: 8) {
            if vm.isRunning {
                HStack(spacing: 8) {
                    LiveDot(t: t)
                    Text("▶ \(vm.session.action)").font(.term(14)).foregroundStyle(t.accent).lineLimit(1)
                    Spacer()
                    Text("\(vm.session.tokens) · \(vm.session.model)").font(.term(13)).foregroundStyle(t.txtMuted).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glass(t, 4, flat: true)
            }
            if vm.readOnly { readOnlyBar } else { composer }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var readOnlyBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye").font(.system(size: 15)).foregroundStyle(t.txtMuted)
            Text("WATCHING · READ-ONLY").font(.labl(10)).tracking(1.4).foregroundStyle(t.txtMuted)
            Spacer()
            Text("view link").font(.term(13)).foregroundStyle(t.txtGhost)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .glass(t, 4, flat: true)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("", text: $draft, prompt: Text(vm.isRunning ? "Steer the turn…" : "Message the agent…").foregroundStyle(t.txtMuted), axis: .vertical)
                .font(.bodyF(14)).foregroundStyle(t.txt).tint(t.accent)
                .lineLimit(1...5)
                .onSubmit(doSend)
            sendOrStop
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .glass(t, 4)
    }

    @ViewBuilder private var sendOrStop: some View {
        if vm.isRunning {
            Button { vm.stop() } label: {
                Image(systemName: "stop.fill").font(.system(size: 15)).foregroundStyle(t.txt)
                    .frame(width: 38, height: 38).background(t.glassFill2).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.lineHover))
            }.press()
        } else {
            Button(action: doSend) {
                Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(t.accent)
                    .frame(width: 38, height: 38).background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
            }.press()
        }
    }

    private func doSend() {
        let x = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.isEmpty else { return }
        vm.send(x); draft = ""
    }
}

struct IdStr: Identifiable { let v: String; var id: String { v }; init(_ v: String) { self.v = v } }
