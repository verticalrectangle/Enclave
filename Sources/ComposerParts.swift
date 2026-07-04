//  ComposerParts.swift
//  Shared chips. (Slash commands and the attach menu were host-side / mock-only
//  affordances the collab guest can't drive, so they're gone — the composer just
//  prompts, steers, and stops.)

import SwiftUI

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
