//  ComposerParts.swift
//  Shared chips + the cycling composer hint strip. (The slash palette lives with
//  the /enclave plugin, where commands can actually run; these tips only ever
//  point at things a guest can really do.)

import SwiftUI

/// A quiet, slowly-cycling hint under the composer. Every tip is a real action
/// the guest can take — no fictional slash commands.
struct ComposerTips: View {
    let t: Theme
    @State private var i = 0
    private let tips: [(icon: String, text: String)] = [
        ("mic", "dictate instead of typing"),
        ("paperclip", "attach an image to your message"),
        ("text.bubble", "type while it's running to steer the turn"),
        ("questionmark.bubble", "answer the agent's asks right here"),
        ("stop.fill", "tap stop to interrupt a running turn"),
    ]
    private let timer = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    var body: some View {
        let tip = tips[i]
        HStack(spacing: 8) {
            Image(systemName: tip.icon).font(.system(size: 12)).foregroundStyle(t.txtGhost).frame(width: 15)
            Text(tip.text).font(.bodyF(12)).foregroundStyle(t.txtMuted).lineLimit(1)
            Spacer(minLength: 0)
        }
        .id(i)
        .transition(.opacity)
        .padding(.horizontal, 10).padding(.top, 7).padding(.bottom, 8)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint), alignment: .top)
        .onReceive(timer) { _ in withAnimation(.easeInOut(duration: 0.35)) { i = (i + 1) % tips.count } }
    }
}

struct Chip: View {
    let t: Theme; let text: String; var on = false
    var body: some View {
        Text(text).font(.labl(10)).tracking(1)
            .foregroundStyle(on ? t.accent : t.txtMuted)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(on ? t.accentDim : .clear)
            .overlay(Capsule().stroke(on ? t.accentLine : t.line))
            .clipShape(Capsule())
    }
}

struct MetaChip: View {
    let t: Theme; let text: String
    var body: some View {
        Text(text).font(.labl(9)).tracking(1).foregroundStyle(t.txtMuted)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().stroke(t.line))
    }
}
