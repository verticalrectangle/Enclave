//  TrustView.swift
//  Zero-trust surface: host spec grid, model routing (→ ModelSheet), paired
//  devices with fingerprints, appearance toggle.

import SwiftUI

struct TrustView: View {
    @EnvironmentObject var theme: ThemeStore
    @State private var showModels = false
    private var t: Theme { theme.t }

    private let devices: [(String, Bool, String, String)] = [
        ("iPhone 16 Pro", true, "read-write", "7E08 BB19"),
        ("studio-mini", false, "host", "A3F2 91C4"),
        ("MacBook Pro", false, "read-write", "5D6A 2F31"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Trust").font(.disp(40)).foregroundStyle(t.txt).textCase(.uppercase)
                        .padding(.horizontal, 16).padding(.bottom, 14)

                    // host
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 9) {
                            LiveDot(t: t)
                            Text(Sample.host.name).font(.disp(16)).foregroundStyle(t.txt).textCase(.uppercase)
                            Spacer()
                            Chip(t: t, text: "host", on: true)
                        }.padding(.bottom, 12)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                            SpecCell(t: t, k: "OS", v: Sample.host.os)
                            SpecCell(t: t, k: "Harness", v: Sample.host.omp)
                            SpecCell(t: t, k: "Relay", v: Sample.host.relay)
                            SpecCell(t: t, k: "Paired", v: Sample.host.paired)
                            SpecCell(t: t, k: "Surface", v: Sample.host.surface)
                            SpecCell(t: t, k: "Core", v: Sample.host.core)
                        }
                    }.padding(14).glass(t, 4).padding(.horizontal, 16).padding(.bottom, 20)

                    // model routing
                    HStack {
                        Text("MODEL ROUTING").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted)
                        Spacer()
                        Button { showModels = true } label: { Text("Configure ›").font(.labl(10)).foregroundStyle(t.accent) }
                    }.padding(.horizontal, 20).padding(.bottom, 10)
                    VStack(spacing: 0) {
                        ForEach(Array(Sample.roles.prefix(5).enumerated()), id: \.offset) { n, r in
                            Button { showModels = true } label: {
                                HStack(spacing: 10) {
                                    Text(r.role).font(.labl(10)).foregroundStyle(t.txtLabel).frame(width: 58, alignment: .leading)
                                    Text(Sample.modelName(r.model)).font(.term(14)).foregroundStyle(t.txt).lineLimit(1)
                                    Spacer()
                                    Chip(t: t, text: r.thinking, on: true)
                                }.padding(.horizontal, 13).padding(.vertical, 10)
                                .overlay(n > 0 ? Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint) : nil, alignment: .top)
                            }
                        }
                    }.glass(t, 4).padding(.horizontal, 16).padding(.bottom, 20)

                    // devices
                    Text("PAIRED DEVICES").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted)
                        .padding(.horizontal, 20).padding(.bottom, 10)
                    VStack(spacing: 8) {
                        ForEach(Array(devices.enumerated()), id: \.offset) { _, d in
                            HStack(spacing: 10) {
                                Image(systemName: d.2 == "host" ? "desktopcomputer" : "iphone").font(.system(size: 17)).foregroundStyle(d.1 ? t.accent : t.txtMuted)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(d.0).font(.disp(14)).foregroundStyle(t.txt).textCase(.uppercase)
                                        if d.1 { Text("· this device").font(.term(12)).foregroundStyle(t.accent) }
                                    }
                                    Text("\(d.3) · \(d.2)").font(.term(12)).foregroundStyle(t.txtMuted)
                                }
                                Spacer()
                                if !d.1 { Text("REVOKE").font(.labl(9)).foregroundStyle(t.cAdvisor) }
                            }
                            .padding(.horizontal, 13).padding(.vertical, 11).glass(t, 4, flat: true)
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 20)
                }.padding(.bottom, 20)
            }
            .background(t.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarLeading) { Text("ZERO-TRUST · SEALED RELAY").font(.labl(9)).tracking(1.6).foregroundStyle(t.txtLabel) } }
            .toolbarBackground(t.bg, for: .navigationBar)
            .sheet(isPresented: $showModels) { ModelSheet().environmentObject(theme) }
        }
        .tint(t.accent)
    }
}

// MARK: - ModelSheet (role → model → thinking)

struct ModelSheet: View {
    @EnvironmentObject var theme: ThemeStore
    @Environment(\.dismiss) var dismiss
    @State private var roles = Sample.roles
    @State private var open: String? = "default"
    private var t: Theme { theme.t }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Each role routes to its own model and thinking budget. Tap a role to choose the model and set how hard it thinks.")
                        .font(.bodyF(13.5)).foregroundStyle(t.txtBody).padding(.bottom, 6)
                    ForEach($roles) { $r in
                        let isOpen = open == r.role
                        VStack(spacing: 0) {
                            Button { withAnimation(.easeInOut(duration: 0.2)) { open = isOpen ? nil : r.role } } label: {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.role).font(.disp(14)).foregroundStyle(isOpen ? t.accent : t.txt)
                                        Text(r.note).font(.bodyF(10.5)).foregroundStyle(t.txtLabel)
                                    }.frame(width: 74, alignment: .leading)
                                    Spacer()
                                    Text(Sample.modelName(r.model)).font(.term(14)).foregroundStyle(t.txt).lineLimit(1)
                                    Chip(t: t, text: r.thinking, on: true)
                                }.padding(12)
                            }
                            if isOpen {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("MODEL").font(.labl(9)).tracking(1.4).foregroundStyle(t.txtMuted).padding(.bottom, 3)
                                    ForEach(Sample.catalog) { m in
                                        Button { r.model = m.modelId } label: {
                                            HStack(spacing: 9) {
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text(m.name).font(.disp(13)).foregroundStyle(r.model == m.modelId ? t.accent : t.txt)
                                                    Text(m.modelId).font(.term(12)).foregroundStyle(t.txtMuted).lineLimit(1)
                                                }
                                                Spacer()
                                                MetaChip(t: t, text: m.prov)
                                                if r.model == m.modelId { Image(systemName: "checkmark").font(.system(size: 14)).foregroundStyle(t.accent) }
                                            }
                                            .padding(.horizontal, 10).padding(.vertical, 9)
                                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(r.model == m.modelId ? t.accentLine : t.line))
                                            .background(r.model == m.modelId ? t.accentDim : .clear)
                                        }
                                    }
                                    Text("THINKING").font(.labl(9)).tracking(1.4).foregroundStyle(t.txtMuted).padding(.top, 10).padding(.bottom, 3)
                                    HStack(spacing: 5) {
                                        ForEach(Sample.thinkingLevels, id: \.self) { lvl in
                                            Button { r.thinking = lvl } label: {
                                                Text(lvl).font(.labl(9)).foregroundStyle(r.thinking == lvl ? t.accent : t.txtMuted)
                                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(r.thinking == lvl ? t.accentLine : t.line))
                                                    .background(r.thinking == lvl ? t.accentDim : .clear)
                                            }
                                        }
                                    }
                                }.padding(12).overlay(Rectangle().frame(height: 0.5).foregroundStyle(t.lineFaint), alignment: .top)
                            }
                        }
                        .glass(t, 4, active: isOpen)
                    }
                }.padding(16)
            }
            .background(t.bg.ignoresSafeArea())
            .navigationTitle("Models").navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(t.txt) } } }
            .toolbarBackground(t.bg, for: .navigationBar)
        }
        .tint(t.accent).preferredColorScheme(theme.mode == .dark ? .dark : .light)
    }
}
