//  ComposerParts.swift
//  Cycling slash hints, the full slash palette, the attach menu, and shared chips.

import SwiftUI

struct SlashHints: View {
    let t: Theme
    var onPick: (String) -> Void
    var onOpen: () -> Void
    @State private var i = 0
    let timer = Timer.publish(every: 2.6, on: .main, in: .common).autoconnect()

    var body: some View {
        let cmd = Sample.slashCommands[i]
        return HStack(spacing: 9) {
            Button(action: onOpen) {
                Text("/").font(.term(16)).foregroundStyle(t.accent)
                    .frame(width: 27, height: 23).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.line))
            }
            Button { onPick(cmd.0 + " ") } label: {
                HStack(spacing: 8) {
                    Text(cmd.0).font(.term(15)).foregroundStyle(t.accent)
                    Text(cmd.1).font(.bodyF(12)).foregroundStyle(t.txtMuted).lineLimit(1)
                    Spacer(minLength: 0)
                }.id(i).transition(.opacity)
            }
        }
        .padding(.horizontal, 9).padding(.top, 7).padding(.bottom, 8)
        .overlay(Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint), alignment: .top)
        .onReceive(timer) { _ in withAnimation(.easeInOut(duration: 0.3)) { i = (i + 1) % Sample.slashCommands.count } }
    }
}

struct SlashPalette: View {
    let t: Theme
    var onPick: (String) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SLASH COMMANDS").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted)
                Spacer()
            }.padding(.horizontal, 13).padding(.vertical, 11)
            .overlay(Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint), alignment: .bottom)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Sample.slashCommands, id: \.0) { cmd in
                        Button { onPick(cmd.0 + " ") } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(cmd.0).font(.term(15)).foregroundStyle(t.accent).frame(width: 84, alignment: .leading)
                                Text(cmd.1).font(.bodyF(13)).foregroundStyle(t.txtBody)
                                Spacer()
                            }.padding(.horizontal, 12).padding(.vertical, 9)
                        }
                    }
                }.padding(6)
            }
            .frame(maxHeight: 300)
        }
        .glass(t, 4, panel: true)
    }
}

struct AttachMenu: View {
    let t: Theme
    var onPick: () -> Void
    private let opts: [(String, String)] = [("photo", "Photo library"), ("camera", "Camera"), ("doc", "File"), ("camera.viewfinder", "Screenshot")]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(opts.enumerated()), id: \.offset) { n, o in
                Button(action: onPick) {
                    HStack(spacing: 11) {
                        Image(systemName: o.0).font(.system(size: 18)).foregroundStyle(t.txtBody).frame(width: 22)
                        Text(o.1).font(.labl(11)).foregroundStyle(t.txt)
                        Spacer()
                    }.padding(.horizontal, 14).padding(.vertical, 12)
                    .overlay(n > 0 ? Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint) : nil, alignment: .top)
                }
            }
        }
        .frame(width: 210)
        .glass(t, 4, panel: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// shared

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
