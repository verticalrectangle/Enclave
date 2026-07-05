//  TranscriptViews.swift
//  The pieces that render a transcript turn, matching the prototype 1:1.

import SwiftUI
import UIKit

// MARK: - Turn row (dispatch by type)

struct TurnRow: View {
    let turn: UITurn
    let t: Theme
    var onImage: (String) -> Void = { _ in }
    var onAnswer: ((UITurn, Int) -> Void)? = nil
    var onRewind: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil

    var body: some View {
        content
            .padding(.bottom, 14)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// Long-press actions. Copy is always offered; Edit/Rewind only when the
    /// /enclave plugin makes them available (callbacks non-nil).
    @ViewBuilder private var messageMenu: some View {
        Button { UIPasteboard.general.string = turn.text } label: { Label("Copy", systemImage: "doc.on.doc") }
        if let onEdit { Button { onEdit() } label: { Label("Edit", systemImage: "pencil") } }
        if let onRewind { Button(role: .destructive) { onRewind() } label: { Label("Rewind to here", systemImage: "arrow.uturn.backward") } }
    }

    @ViewBuilder private var content: some View {
        switch turn.type {
        case .user: userBubble
        case .agent: agentLine
        case .tool: ToolCard(turn: turn, t: t, onImage: onImage)
        case .advisor: advisorNote
        case .sys: SysChip(turn: turn, t: t)
        case .ask: AskCard(turn: turn, t: t, onSubmit: onAnswer.map { cb in { idx in cb(turn, idx) } })
        case .thinking: ThinkingBlock(turn: turn, t: t)
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let img = turn.image {
                Button { onImage(img) } label: {
                    SrcImage(src: img) { $0.resizable().scaledToFill() } placeholder: { t.line }
                        .frame(width: 180, height: 120).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16)).glass(t, 16)
                }
            }
            Text(turn.text).font(.bodyF(14)).foregroundStyle(t.txt)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .glass(t, 16)
                .contextMenu { messageMenu }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var agentLine: some View {
        // Serif prose with fenced code rendered as scrollable monospace boxes.
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(markdownBlocks(turn.text).enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .prose(let p):
                    if !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(inlineMarkdown(p)).font(.serif(16)).foregroundStyle(t.txt)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .code(let lang, let body):
                    CodeBlock(lang: lang, code: body, t: t)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button { UIPasteboard.general.string = turn.text } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
    }

    private var advisorNote: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(t.cAdvisor).frame(width: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("ADVISOR").font(.labl(9)).tracking(1).foregroundStyle(t.cAdvisor)
                Text(inlineMarkdown(turn.text)).font(.bodyF(13.5)).foregroundStyle(t.txt)
            }.padding(.leading, 11).padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .background(t.glassFill2)
    }
}

// MARK: - Markdown blocks (prose + fenced code)

enum MDBlock { case prose(String); case code(lang: String, body: String) }

/// Split agent text into prose runs and fenced ``` code blocks. Tolerant of an
/// unclosed fence (still streaming): everything after the opener renders as code.
func markdownBlocks(_ s: String) -> [MDBlock] {
    var out: [MDBlock] = []
    var prose: [String] = []
    let lines = s.components(separatedBy: "\n")
    var i = 0
    func flush() { if !prose.isEmpty { out.append(.prose(prose.joined(separator: "\n"))); prose = [] } }
    while i < lines.count {
        if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            flush()
            let lang = String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var body: [String] = []; i += 1
            while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { body.append(lines[i]); i += 1 }
            if i < lines.count { i += 1 }   // consume closing fence
            out.append(.code(lang: lang, body: body.joined(separator: "\n")))
        } else { prose.append(lines[i]); i += 1 }
    }
    flush()
    return out
}

/// A fenced code block: language label + copy button over a scrollable monospace body.
struct CodeBlock: View {
    let lang: String; let code: String; let t: Theme
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(lang.isEmpty ? "CODE" : lang.uppercased()).font(.labl(8.5)).tracking(1.5).foregroundStyle(t.txtMuted)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_400_000_000); copied = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10))
                        Text(copied ? "COPIED" : "COPY").font(.labl(8.5)).tracking(1)
                    }.foregroundStyle(copied ? t.cOk : t.txtMuted)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint), alignment: .bottom)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(t.txtBody)
                    .textSelection(.enabled).padding(12)
            }
        }
        .background(t.bg2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.lineFaint))
    }
}

/// Inline-only markdown so bold/code/italics render but line breaks are kept and
/// partial (still-streaming) text never fails to show.
func inlineMarkdown(_ s: String) -> AttributedString {
    (try? AttributedString(
        markdown: s,
        options: AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)))
    ?? AttributedString(s)
}

// MARK: - Tool card

struct ToolCard: View {
    let turn: UITurn
    let t: Theme
    var onImage: (String) -> Void = { _ in }
    private var c: Color { toolColor(turn.kind, t) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(c).frame(width: 2).cornerRadius(2)
            VStack(alignment: .leading, spacing: turn.lines.isEmpty && turn.image == nil && turn.caption == nil ? 0 : 7) {
                HStack(spacing: 8) {
                    Image(systemName: toolGlyph(turn.kind)).font(.system(size: 13)).foregroundStyle(c)
                    Text(turn.head.uppercased()).font(.labl(10.5)).tracking(0.4).foregroundStyle(c)
                    Text(turn.meta).font(.term(13)).foregroundStyle(t.txtMuted).lineLimit(1)
                    Spacer(minLength: 0)
                    if let a = turn.add {
                        Text("+\(a)").font(.term(13)).foregroundStyle(t.cOk)
                        if let d = turn.del { Text("−\(d)").font(.term(13)).foregroundStyle(t.cAdvisor) }
                    }
                }
                // Compact chip, not an inline image: a browser-heavy session dumps many
                // screenshots, and decoding them all up front is what stalls the view.
                // The full image decodes only when you tap to focus it.
                if let img = turn.image {
                    Button { onImage(img) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "photo").font(.system(size: 12)).foregroundStyle(c)
                            Text("image result").font(.term(13)).foregroundStyle(t.txtBody)
                            Text("tap to view").font(.labl(8.5)).tracking(0.6).foregroundStyle(t.txtMuted)
                            Spacer(minLength: 0)
                            Image(systemName: "eye").font(.system(size: 11)).foregroundStyle(t.txtMuted)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.lineFaint))
                    }
                }
                if let cap = turn.caption { Text(cap).font(.bodyF(13)).foregroundStyle(t.txtBody) }
                if !turn.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(turn.lines.enumerated()), id: \.offset) { _, l in
                            Text(l).font(.term(13)).foregroundStyle(l.hasPrefix("+") ? t.cOk : (l.hasPrefix("−") || l.hasPrefix("-")) ? t.cAdvisor : t.txtMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(t.bg2).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }
}

// MARK: - Sys chip / ask / approval

struct SysChip: View {
    let turn: UITurn; let t: Theme
    private var c: Color {
        switch turn.kind {
        case "paired": t.cOk
        case "rewind", "mode", "notice": t.accent
        case "stop", "ttsr", "error": t.cAdvisor
        default: t.txtMuted
        }
    }
    private var glyph: String {
        switch turn.kind {
        case "compaction": "square.3.layers.3d"; case "retry": "arrow.triangle.2.circlepath"
        case "ttsr": "text.badge.checkmark"; case "stop": "stop.fill"; case "rewind": "arrow.uturn.backward"
        case "paired": "checkmark.seal.fill"; case "error": "exclamationmark.triangle.fill"
        case "mode": "flag.fill"; case "model": "arrow.triangle.swap"; case "note": "text.bubble"; case "notice": "info.circle.fill"
        default: "circle.grid.cross"
        }
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: glyph).font(.system(size: 11)).foregroundStyle(c)
            Text(turn.text).font(.labl(9)).tracking(1.4).foregroundStyle(c)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct AskCard: View {
    let turn: UITurn; let t: Theme
    /// Live host asks pass a submit callback; mock asks leave it nil (display only).
    var onSubmit: ((Int) -> Void)? = nil
    @State private var chosen = 0
    @State private var sent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "questionmark.bubble").font(.system(size: 14)).foregroundStyle(t.accent)
                Text("ASK").font(.labl(9)).foregroundStyle(t.accent)
                Text(turn.question).font(.bodyF(13.5)).foregroundStyle(t.txt)
            }
            ForEach(Array(turn.options.enumerated()), id: \.offset) { i, opt in
                Button { chosen = i } label: {
                    HStack {
                        Text(opt).font(.bodyF(13)).foregroundStyle(chosen == i ? t.accent : t.txtBody)
                        Spacer()
                        if chosen == i { Image(systemName: "checkmark").font(.system(size: 13)).foregroundStyle(t.accent) }
                    }
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(chosen == i ? t.accentLine : t.line))
                    .background(chosen == i ? t.glassFill2 : .clear)
                }
            }
            if let onSubmit, !turn.options.isEmpty {
                Button { sent = true; onSubmit(chosen) } label: {
                    HStack(spacing: 6) { Image(systemName: sent ? "checkmark" : "paperplane.fill"); Text(sent ? "SENT" : "SEND").font(.labl(10.5)) }
                        .foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .glass(t, 16, active: true)
                }.disabled(sent).press()
            }
        }
        .padding(11)
        .glass(t, 16, active: true)
    }
}

// MARK: - misc

/// The thinking state: just the enclave eye, its pupil dilating and closing on a
/// slow breath — no text. Clean, single-glyph, unmistakably Enclave.
struct ThinkingLine: View {
    let t: Theme
    @State private var open: CGFloat = 0.25
    var body: some View {
        LogoMark(t: t, size: 22, color: t.accent, open: open)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) { open = 1.3 }
            }
    }
}

/// The model's reasoning — collapsed by default, tap to expand or collapse.
struct ThinkingBlock: View {
    let turn: UITurn; let t: Theme
    @State private var expanded = false
    private var header: String {
        guard let s = turn.thoughtSeconds else { return "THINKING" }
        return s < 60 ? "THOUGHT FOR \(s)s" : "THOUGHT FOR \(s / 60)m \(s % 60)s"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(header).font(.labl(9)).tracking(1.6).foregroundStyle(t.txtMuted)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(t.txtGhost)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                Text(inlineMarkdown(turn.text)).font(.serif(13.5)).italic().foregroundStyle(t.txtMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8).padding(.leading, 2)
            }
        }
        .padding(.vertical, 1)
    }
}

struct ImageViewer: View {
    @EnvironmentObject var theme: ThemeStore
    let src: String; let label: String; let onClose: () -> Void
    private var t: Theme { theme.t }
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 14) {
                SrcImage(src: src) { $0.resizable().scaledToFit() } placeholder: { t.line }
                    .frame(maxHeight: 480).clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.lineStrong))
                Text(label).font(.term(14)).foregroundStyle(t.lockFg)
                Text("TAP ANYWHERE TO CLOSE").font(.labl(9)).foregroundStyle(t.lockFg.opacity(0.5))
            }.padding(22)
        }
    }
}

/// Renders an image src that may be a `data:` URI (base64, what the guest sends and
/// the host echoes back) OR an http(s) URL. AsyncImage alone can't load data: URIs.
struct SrcImage<Content: View, Placeholder: View>: View {
    let src: String
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    var body: some View {
        if src.hasPrefix("data:"), let ui = Self.decode(src) {
            content(Image(uiImage: ui))
        } else if let url = URL(string: src), url.scheme?.hasPrefix("http") == true {
            AsyncImage(url: url) { content($0) } placeholder: { placeholder() }
        } else {
            placeholder()
        }
    }

    static func decode(_ dataURI: String) -> UIImage? {
        let key = dataURI as NSString
        if let cached = srcImageCache.object(forKey: key) { return cached }
        guard let comma = dataURI.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURI[dataURI.index(after: comma)...])),
              let ui = UIImage(data: data) else { return nil }
        srcImageCache.setObject(ui, forKey: key)
        return ui
    }
}

private let srcImageCache = NSCache<NSString, UIImage>()

// bespoke ring + sealed-slit logomark
struct LogoMark: View {
    let t: Theme; var size: CGFloat = 24; var color: Color; var open: CGFloat = 1
    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: size * 0.075)
            EnclaveSlit(open: open).stroke(color, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round, lineJoin: .round))
        }
        // Inset the mark within its footprint so a circular Liquid Glass toolbar
        // chip doesn't clip the ring at the top and bottom.
        .frame(width: size * 0.82, height: size * 0.82)
        .frame(width: size, height: size)
    }
}
