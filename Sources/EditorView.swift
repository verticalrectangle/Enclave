//  EditorView.swift
//  The hero: streaming transcript + composer. Tool cards, sys chips, advisor notes,
//  ask pickers, the pending-approval bar, Stop/abort, and message edit→rewind — all
//  driven by SessionVM (mock now, EngineBridge later). NavigationStack pushes this;
//  the native back button returns to Sessions.

import SwiftUI

struct EditorView: View {
    @EnvironmentObject var theme: ThemeStore
    @StateObject var vm: SessionVM
    @State private var draft = ""
    @State private var attachImg: String? = nil
    @State private var listening = false
    @State private var showPalette = false
    @State private var showAttach = false
    @State private var viewer: String? = nil

    init(_ s: Session) { _vm = StateObject(wrappedValue: SessionVM(s)) }
    private var t: Theme { theme.t }
    private var editing: Bool { vm.editingIndex != nil }

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
                    Text(vm.session.repo).font(.disp(15)).foregroundStyle(t.txt).textCase(.uppercase)
                    Text("\(vm.session.dir) · \(vm.session.branch)").font(.term(12)).foregroundStyle(t.txtMuted)
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
                    ForEach(Array(vm.turns.enumerated()), id: \.element.id) { idx, turn in
                        TurnRow(turn: turn, t: t,
                                dim: editing && vm.editingIndex! < idx,
                                isEditTarget: vm.editingIndex == idx,
                                canEdit: !vm.isRunning && !editing && turn.type == .user,
                                onEdit: { startEdit(idx, turn) },
                                onImage: { viewer = $0 })
                            .id(turn.id)
                        if vm.editingIndex == idx { RewindDivider(t: t) }
                    }
                    if vm.isRunning && !editing { ThinkingLine(t: t).id("think") }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: vm.turns.count) { _ in
                if !editing { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }

    // MARK: composer

    private var composerStack: some View {
        VStack(spacing: 8) {
            if vm.isRunning && !editing {
                HStack(spacing: 8) {
                    LiveDot(t: t)
                    Text("▶ \(vm.session.action)").font(.term(14)).foregroundStyle(t.accent).lineLimit(1)
                    Spacer()
                    Text("\(vm.session.tokens) · \(vm.session.cost)").font(.term(13)).foregroundStyle(t.txtMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glass(t, 4, flat: true)
            }

            if !editing, let perm = vm.turns.first(where: { $0.type == .permission && $0.pending }) {
                PendingApproval(turn: perm, t: t)
            }

            composer
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            if showPalette { SlashPalette(t: t) { draft = $0; showPalette = false } .padding(.horizontal, 12).offset(y: -68) }
            if showAttach { AttachMenu(t: t) { attachImg = "https://picsum.photos/seed/att\(UUID().uuidString.prefix(6))/400/300"; showAttach = false } .padding(.horizontal, 12).offset(y: -68) }
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if editing {
                HStack(spacing: 8) {
                    Image(systemName: "pencil").font(.system(size: 13)).foregroundStyle(t.accent)
                    Text("Editing · turns below rewind on resend").font(.term(13)).foregroundStyle(t.accent)
                    Spacer()
                    Button { vm.cancelEdit(); resetDraft() } label: { Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(t.accent) }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(t.accentDim)
            }
            if let img = attachImg {
                HStack(spacing: 9) {
                    AsyncImage(url: URL(string: img)) { $0.resizable().scaledToFill() } placeholder: { t.line }
                        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("image attached · sent with your message").font(.term(13)).foregroundStyle(t.txtMuted)
                    Spacer()
                    Button { attachImg = nil } label: { Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(t.txtMuted) }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint), alignment: .top)
            }
            HStack(spacing: 4) {
                Button { showAttach.toggle(); showPalette = false } label: {
                    Image(systemName: "paperclip").font(.system(size: 20)).foregroundStyle(showAttach ? t.accent : t.txtMuted).frame(width: 34, height: 34)
                }
                TextField("", text: $draft, prompt: Text(editing ? "Edit your message…" : listening ? "Listening…" : "Message the agent…").foregroundStyle(t.txtMuted))
                    .font(.bodyF(14)).foregroundStyle(t.txt).tint(t.accent)
                    .onSubmit { editing ? doResend() : doSend() }
                if !editing {
                    Button { listening.toggle() } label: {
                        Image(systemName: "mic").font(.system(size: 20)).foregroundStyle(listening ? t.accent : t.txtMuted).frame(width: 34, height: 34)
                    }
                }
                sendOrStop
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            if !editing { SlashHints(t: t) { draft = $0 } onOpen: { showPalette.toggle(); showAttach = false } }
        }
        .glass(t, 4, active: editing)
    }

    @ViewBuilder private var sendOrStop: some View {
        if vm.isRunning && !editing {
            Button { vm.stop() } label: {
                Image(systemName: "stop.fill").font(.system(size: 15)).foregroundStyle(t.txt)
                    .frame(width: 38, height: 38).background(t.glassFill2).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.lineHover))
            }.press()
        } else {
            Button { editing ? doResend() : doSend() } label: {
                Image(systemName: editing ? "checkmark" : "arrow.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(t.accent)
                    .frame(width: 38, height: 38).background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
            }.press()
        }
    }

    private func startEdit(_ i: Int, _ turn: UITurn) { vm.beginEdit(i); draft = turn.text; attachImg = turn.image; showPalette = false; showAttach = false }
    private func resetDraft() { draft = ""; attachImg = nil }
    private func doSend() { let x = draft.trimmingCharacters(in: .whitespaces); guard !x.isEmpty || attachImg != nil else { return }; vm.send(x, image: attachImg); resetDraft(); listening = false }
    private func doResend() { guard let i = vm.editingIndex else { return }; vm.resend(i, text: draft.trimmingCharacters(in: .whitespaces), image: attachImg); resetDraft() }
}

struct IdStr: Identifiable { let v: String; var id: String { v }; init(_ v: String) { self.v = v } }
