//  EditorView.swift
//  The hero: live streaming transcript + composer. Backed by a GuestClient via
//  SessionVM. A guest can prompt, abort, and answer asks — nothing else the
//  collab wire doesn't expose. View (watch) links are read-only: the composer is
//  replaced by a read-only bar.

import SwiftUI
import PhotosUI
import UIKit

/// A picked, downscaled image ready to send with a prompt.
struct Attachment: Identifiable {
    let id = UUID()
    let image: UIImage      // thumbnail to show
    let data: Data          // JPEG bytes to send
    let mime: String
}

struct EditorView: View {
    @EnvironmentObject var theme: ThemeStore
    @StateObject var vm: SessionVM
    @StateObject private var dictation = Dictation()
    @State private var draft = ""
    @State private var viewer: String? = nil
    @State private var pickerItem: PhotosPickerItem?
    @State private var attachment: Attachment?
    @State private var showPalette = false
    @State private var showVisionHelp = false

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
                                onAnswer: vm.readOnly ? nil : { vm.answer($0, $1) },
                                onRewind: (vm.enhanced && !vm.isRunning && turn.type == .user) ? { vm.rewind(to: turn) } : nil,
                                onEdit: (vm.enhanced && !vm.isRunning && turn.type == .user) ? { draft = turn.text; vm.rewindBefore(to: turn) } : nil)
                            .id(turn.id)
                    }
                    if vm.isRunning { ThinkingLine(t: t).id("think") }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(16)
            }
            .onChange(of: scrollKey) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Changes on a new turn AND as the streaming turn's text grows, so the view
    /// follows the agent live instead of jumping only when the turn finishes.
    private var scrollKey: String {
        "\(vm.turns.count)|\(vm.turns.first(where: { $0.id == "stream" })?.text.count ?? 0)"
    }

    // MARK: composer

    private var composerStack: some View {
        VStack(spacing: 8) {
            if vm.isRunning {
                HStack(spacing: 8) {
                    if vm.awaitingVision { Image(systemName: "eye").font(.system(size: 13)).foregroundStyle(t.accent) } else { LiveDot(t: t) }
                    Text(vm.session.action).font(.term(14)).foregroundStyle(t.accent).lineLimit(1)
                    Spacer()
                    Text("\(vm.session.tokens) · \(vm.session.model)").font(.term(13)).foregroundStyle(t.txtMuted).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glass(t, 16, flat: true)
            }
            if vm.readOnly { readOnlyBar } else { composer }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            if showPalette {
                SlashPalette(t: t, commands: vm.commands) { name in vm.runCommand(name); showPalette = false }
                    .padding(.horizontal, 12).offset(y: -70)
            }
        }
    }

    private var readOnlyBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye").font(.system(size: 15)).foregroundStyle(t.txtMuted)
            Text("WATCHING · READ-ONLY").font(.labl(10)).tracking(1.4).foregroundStyle(t.txtMuted)
            Spacer()
            Text("view link").font(.term(13)).foregroundStyle(t.txtGhost)
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .glass(t, 16, flat: true)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            if let a = attachment {
                HStack(spacing: 9) {
                    Image(uiImage: a.image).resizable().scaledToFill()
                        .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("image attached · sent with your message").font(.term(13)).foregroundStyle(t.txtMuted)
                        if vm.viaVisionModel {
                            HStack(spacing: 4) {
                                Image(systemName: "eye").font(.system(size: 9))
                                Text("read via vision model").font(.labl(8.5)).tracking(0.8)
                            }.foregroundStyle(t.accent.opacity(0.85))
                        }
                    }
                    Spacer()
                    Button { attachment = nil } label: { Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(t.txtMuted) }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .overlay(Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint), alignment: .bottom)
            }
            HStack(spacing: 4) {
                if vm.enhanced && !vm.commands.isEmpty {
                    Button { showPalette.toggle() } label: {
                        Image(systemName: "slash.circle").font(.system(size: 20)).foregroundStyle(showPalette ? t.accent : t.txtMuted).frame(width: 34, height: 34)
                    }
                }
                if vm.canSendImages {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "paperclip").font(.system(size: 20)).foregroundStyle(t.txtMuted).frame(width: 34, height: 34)
                    }
                } else if vm.imagePossible {
                    Button { showVisionHelp = true } label: {
                        Image(systemName: "paperclip").font(.system(size: 20)).foregroundStyle(t.txtGhost).frame(width: 34, height: 34).opacity(0.5)
                    }
                }
                TextField("", text: $draft, prompt: Text(placeholder).foregroundStyle(t.txtMuted), axis: .vertical)
                    .font(.bodyF(14)).foregroundStyle(t.txt).tint(t.accent)
                    .lineLimit(1...5)
                    .onSubmit(doSend)
                Button { dictation.toggle() } label: {
                    Image(systemName: dictation.recording ? "mic.fill" : "mic").font(.system(size: 20))
                        .foregroundStyle(dictation.recording ? t.accent : t.txtMuted).frame(width: 34, height: 34)
                }
                sendOrStop
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            if draft.isEmpty && !dictation.recording {
                ComposerTips(t: t, hasCommands: vm.enhanced && !vm.commands.isEmpty) { showPalette = true }
            }
        }
        .glass(t, 16)
        .onChange(of: pickerItem) { _, item in loadAttachment(item) }
        .onAppear { dictation.onText = { draft = $0 } }
        .alert("Vision is off for this session", isPresented: $showVisionHelp) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This model can't read images yet. On the box, enable it:\n\nomp config set inspect_image.enabled true\n\nthen reconnect — or switch to a vision-capable model.")
        }
    }

    private var placeholder: String {
        dictation.recording ? "Listening…" : (vm.isRunning ? "Steer the turn…" : "Message the agent…")
    }

    @ViewBuilder private var sendOrStop: some View {
        if vm.isRunning {
            Button { vm.stop() } label: {
                Image(systemName: "stop.fill").font(.system(size: 15)).foregroundStyle(t.txt)
                    .frame(width: 38, height: 38).glass(t, 16)
            }.press()
        } else {
            Button(action: doSend) {
                Image(systemName: "arrow.right").font(.system(size: 17, weight: .semibold)).foregroundStyle(t.accent)
                    .frame(width: 38, height: 38).glass(t, 16, active: true)
            }.press()
        }
    }

    private func doSend() {
        let x = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        var images: [(mime: String, base64: String)] = []
        if let a = attachment { images = [(a.mime, a.data.base64EncodedString())] }
        guard !x.isEmpty || !images.isEmpty else { return }
        if dictation.recording { dictation.stop() }
        vm.send(x, images: images)
        draft = ""; attachment = nil
    }

    /// Load, downscale (max 1568px, JPEG 0.75) and stage a picked photo.
    private func loadAttachment(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            defer { Task { @MainActor in pickerItem = nil } }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ui = UIImage(data: data) else { return }
            // 1568px long edge is the vision-model sweet spot (enough to read text in
            // a screenshot; larger just gets downscaled anyway). Only ever shrink.
            let maxDim: CGFloat = 1568
            let scale = min(1, maxDim / max(ui.size.width, ui.size.height))
            let size = CGSize(width: ui.size.width * scale, height: ui.size.height * scale)
            let resized = UIGraphicsImageRenderer(size: size).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
            guard let jpeg = resized.jpegData(compressionQuality: 0.75), let thumb = UIImage(data: jpeg) else { return }
            await MainActor.run { attachment = Attachment(image: thumb, data: jpeg, mime: "image/jpeg") }
        }
    }
}

struct IdStr: Identifiable { let v: String; var id: String { v }; init(_ v: String) { self.v = v } }
