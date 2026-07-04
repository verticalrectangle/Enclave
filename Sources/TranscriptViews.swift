//  TranscriptViews.swift
//  The pieces that render a transcript turn, matching the prototype 1:1.

import SwiftUI

// MARK: - Turn row (dispatch by type)

struct TurnRow: View {
    let turn: UITurn
    let t: Theme
    var onImage: (String) -> Void = { _ in }
    var onAnswer: ((UITurn, Int) -> Void)? = nil

    var body: some View {
        content
            .padding(.bottom, 14)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder private var content: some View {
        switch turn.type {
        case .user: userBubble
        case .agent: agentLine
        case .tool: ToolCard(turn: turn, t: t, onImage: onImage)
        case .advisor: advisorNote
        case .sys: SysChip(turn: turn, t: t)
        case .ask: AskCard(turn: turn, t: t, onSubmit: onAnswer.map { cb in { idx in cb(turn, idx) } })
        }
    }

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 5) {
            if let img = turn.image {
                Button { onImage(img) } label: {
                    AsyncImage(url: URL(string: img)) { $0.resizable().scaledToFill() } placeholder: { t.line }
                        .frame(width: 180, height: 120).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4)).glass(t, 4)
                }
            }
            Text(turn.text).font(.bodyF(14)).foregroundStyle(t.txt)
                .padding(.horizontal, 13).padding(.vertical, 10)
                .glass(t, 4)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var agentLine: some View {
        HStack(alignment: .top, spacing: 9) {
            LogoMark(t: t, size: 17, color: turn.streaming ? t.accent : t.txtMuted)
            if turn.streaming { TypeText(text: turn.text, t: t) }
            else { Text(turn.text).font(.bodyF(14)).foregroundStyle(t.txtBody) }
            Spacer(minLength: 0)
        }
    }

    private var advisorNote: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(t.cAdvisor).frame(width: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text("ADVISOR").font(.labl(9)).tracking(1).foregroundStyle(t.cAdvisor)
                Text(turn.text).font(.bodyF(13.5)).foregroundStyle(t.txtBody)
            }.padding(.leading, 11).padding(.vertical, 2)
            Spacer(minLength: 0)
        }
        .background(t.glassFill2)
    }
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
            VStack(alignment: .leading, spacing: turn.lines.isEmpty && turn.image == nil ? 0 : 8) {
                HStack(spacing: 8) {
                    Image(systemName: toolGlyph(turn.kind)).font(.system(size: 14)).foregroundStyle(c)
                    Text(turn.head.uppercased()).font(.labl(10.5)).tracking(0.4).foregroundStyle(c)
                    Text(turn.meta).font(.term(13)).foregroundStyle(t.txtMuted).lineLimit(1)
                    Spacer(minLength: 0)
                    if let a = turn.add {
                        Text("+\(a)").font(.term(13)).foregroundStyle(t.cOk)
                        if let d = turn.del { Text("−\(d)").font(.term(13)).foregroundStyle(t.cAdvisor) }
                    }
                }
                if let img = turn.image {
                    Button { onImage(img) } label: {
                        AsyncImage(url: URL(string: img)) { $0.resizable().scaledToFill() } placeholder: { t.line }
                            .frame(maxWidth: .infinity).frame(height: 168).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(alignment: .bottomTrailing) {
                                HStack(spacing: 4) { Image(systemName: "eye").font(.system(size: 11)); Text("TAP TO FOCUS").font(.labl(8)) }
                                    .foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.black.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 4)).padding(6)
                            }
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
                    .background(t.bg2).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(11)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.line))
        .background(t.glassFill2)
    }
}

// MARK: - Sys chip / ask / approval

struct SysChip: View {
    let turn: UITurn; let t: Theme
    private var c: Color { turn.kind == "rewind" ? t.accent : (turn.kind == "stop" || turn.kind == "ttsr") ? t.cAdvisor : t.txtMuted }
    private var glyph: String {
        switch turn.kind { case "compaction": "square.3.layers.3d"; case "retry": "arrow.triangle.2.circlepath"
        case "ttsr": "text.badge.checkmark"; case "stop": "stop.fill"; case "rewind": "arrow.uturn.backward"; default: "circle.grid.cross" }
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
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(chosen == i ? t.accentLine : t.line))
                    .background(chosen == i ? t.glassFill2 : .clear)
                }
            }
            if let onSubmit, !turn.options.isEmpty {
                Button { sent = true; onSubmit(chosen) } label: {
                    HStack(spacing: 6) { Image(systemName: sent ? "checkmark" : "paperplane.fill"); Text(sent ? "SENT" : "SEND").font(.labl(10.5)) }
                        .foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
                }.disabled(sent).press()
            }
        }
        .padding(11)
        .background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
    }
}

// MARK: - misc

struct ThinkingLine: View {
    let t: Theme
    @State private var dots = ""
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 9) {
            LogoMark(t: t, size: 17, color: t.accent)
            Text("thinking\(dots)").font(.term(15)).foregroundStyle(t.accent)
        }
        .onReceive(timer) { _ in dots = dots.count >= 3 ? "" : dots + "." }
    }
}

struct TypeText: View {
    let text: String; let t: Theme
    @State private var shown = ""
    var body: some View {
        (Text(shown).font(.bodyF(14)).foregroundStyle(t.txtBody)
         + Text(shown.count < text.count ? "▍" : "").foregroundStyle(t.accent))
            .task(id: text) {
                shown = ""
                for ch in text {
                    shown.append(ch)
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
            }
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
                AsyncImage(url: URL(string: src)) { $0.resizable().scaledToFit() } placeholder: { t.line }
                    .frame(maxHeight: 480).clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(t.lineStrong))
                Text(label).font(.term(14)).foregroundStyle(t.lockFg)
                Text("TAP ANYWHERE TO CLOSE").font(.labl(9)).foregroundStyle(t.lockFg.opacity(0.5))
            }.padding(22)
        }
    }
}

// bespoke ring + sealed-slit logomark
struct LogoMark: View {
    let t: Theme; var size: CGFloat = 24; var color: Color
    var body: some View {
        ZStack {
            Circle().stroke(color, lineWidth: size * 0.075)
            EnclaveSlit().stroke(color, style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round, lineJoin: .round))
        }
        // Inset the mark within its footprint so a circular Liquid Glass toolbar
        // chip doesn't clip the ring at the top and bottom.
        .frame(width: size * 0.82, height: size * 0.82)
        .frame(width: size, height: size)
    }
}
