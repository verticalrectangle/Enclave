//  Screens.swift
//  ActivityView (jobs/subagent fan-out), PairView (my.omp.sh join + access +
//  fingerprint verify), LockScreenView (Live Activity, on-the-go approve).

import SwiftUI
import UIKit

// MARK: - Activity

struct ActivityView: View {
    @EnvironmentObject var theme: ThemeStore
    private var t: Theme { theme.t }
    private let jobs: [(String, String, String, String, Double, String)] = [
        ("task", "reconnect-fuzz", "enclave-app", "5 worktrees · schema-validated", 0.6, "running"),
        ("bash", "swift test", "enclave-app", "128 / 214 passed", 0.6, "running"),
        ("debug", "lldb · attach", "silvertune-web", "frame 4 · shifter_simd.c:88", 1.0, "paused"),
        ("task", "strict-ts-migration", "silvertune-web", "3 worktrees · done", 1.0, "done"),
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    Text("Activity").font(.disp(40)).foregroundStyle(t.txt).textCase(.uppercase).padding(.bottom, 3)
                    ForEach(Array(jobs.enumerated()), id: \.offset) { _, j in
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 9) {
                                Image(systemName: toolGlyph(j.0)).font(.system(size: 17)).foregroundStyle(toolColor(j.0, t))
                                Text(j.1).font(.disp(15)).foregroundStyle(t.txt).textCase(.uppercase)
                                Spacer()
                                if j.5 == "running" { LiveDot(t: t) }
                                else { Text(j.5).font(.labl(9)).foregroundStyle(j.5 == "done" ? t.cOk : t.txtMuted) }
                            }.padding(.bottom, 10)
                            Text(j.3).font(.term(13)).foregroundStyle(t.txtMuted).padding(.bottom, 10)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(t.line).frame(height: 3)
                                    Rectangle().fill(j.5 == "done" ? t.cOk : t.accent).frame(width: g.size.width * j.4, height: 3)
                                }
                            }.frame(height: 3).padding(.bottom, 8)
                            Text(j.2).font(.labl(9)).foregroundStyle(t.txtGhost)
                        }.padding(13).glass(t, 4)
                    }
                }.padding(16)
            }
            .background(t.bg.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarLeading) { Text("LIVE ACROSS ALL SESSIONS").font(.labl(9)).tracking(1.6).foregroundStyle(t.txtLabel) } }
            .toolbarBackground(t.bg, for: .navigationBar)
        }.tint(t.accent)
    }
}

// MARK: - Pair

struct PairView: View {
    @EnvironmentObject var theme: ThemeStore
    let onClose: () -> Void
    var onConnect: (LiveSession) -> Void = { _ in }
    @State private var access = "control"
    @State private var link = ""
    @State private var connectError: String?
    private var t: Theme { theme.t }

    private func connect() {
        let clean = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reason = GuestClient.validate(clean) { connectError = reason; return }
        guard let client = GuestClient(link: clean, name: UIDevice.current.name) else {
            connectError = "That link didn't parse."; return
        }
        connectError = nil
        let seed = Session(id: "live", repo: "connecting…", branch: "collab", dir: "~", model: "—",
                           role: "default", status: .waiting, lastSeen: "live", action: "CONNECTING…",
                           tokens: "—", cost: "—", turns: [])
        onConnect(LiveSession(client: client, seed: seed))
    }

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("PAIR DEVICE").font(.labl(10)).tracking(2).foregroundStyle(t.txtLabel)
                        Spacer()
                        Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 20)).foregroundStyle(t.txt) }
                    }.padding(.bottom, 18)

                    Text("Scan to\nenclave.").font(.disp(34)).foregroundStyle(t.txt).textCase(.uppercase).padding(.bottom, 10)
                    (Text("Run ").foregroundStyle(t.txtBody) + Text("omp /collab").font(.term(15)).foregroundStyle(t.accent) + Text(" on the box. Frames are sealed on-device — the relay never sees your keys.").foregroundStyle(t.txtBody))
                        .font(.bodyF(14)).padding(.bottom, 18)

                    // ── live connect: paste the /collab link ──────────────────
                    Text("PASTE COLLAB LINK").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted).padding(.bottom, 8)
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 15)).foregroundStyle(t.txtMuted)
                        TextField("", text: $link, prompt: Text("my.omp.sh link or ws://…").foregroundStyle(t.txtMuted))
                            .font(.term(14)).foregroundStyle(t.txt).tint(t.accent)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .onSubmit(connect)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11).glass(t, 4, flat: true).padding(.bottom, 8)
                    Button(action: connect) {
                        HStack(spacing: 8) { Image(systemName: "bolt.fill"); Text("CONNECT LIVE").font(.labl(11)) }
                            .foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
                    }.press().disabled(link.trimmingCharacters(in: .whitespaces).isEmpty).padding(.bottom, connectError == nil ? 22 : 6)
                    if let err = connectError {
                        Text(err).font(.term(12)).foregroundStyle(t.cAdvisor).padding(.bottom, 18)
                    }

                    QRPlaceholder(t: t).frame(width: 200, height: 200).frame(maxWidth: .infinity).padding(18).glass(t, 4).padding(.bottom, 8)
                    Text("my.omp.sh/j/8F2K-A3F2").font(.term(15)).foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.bottom, 4)
                    (Text("or run ").foregroundStyle(t.txtMuted) + Text("omp join 8F2K-A3F2").font(.term(14)).foregroundStyle(t.accent))
                        .font(.bodyF(12)).frame(maxWidth: .infinity).padding(.bottom, 20)

                    Text("ACCESS").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted).padding(.bottom, 8)
                    HStack(spacing: 6) {
                        accessCard("control", "Control", "read-write")
                        accessCard("watch", "Watch", "read-only")
                    }.padding(.bottom, 20)

                    Text("HOST KEY FINGERPRINT").font(.labl(9)).tracking(2).foregroundStyle(t.txtMuted).padding(.bottom, 8)
                    HStack(spacing: 10) {
                        Image(systemName: "key").font(.system(size: 17)).foregroundStyle(t.accent)
                        Text(Sample.host.fingerprint).font(.term(15)).foregroundStyle(t.txt)
                    }.padding(.horizontal, 13).padding(.vertical, 12).glass(t, 4, flat: true).padding(.bottom, 8)
                    Text("Verify this matches the fingerprint printed in your terminal before you trust the session.")
                        .font(.bodyF(12.5)).foregroundStyle(t.txtMuted).padding(.bottom, 22)

                    Button(action: onClose) {
                        HStack(spacing: 8) { Image(systemName: "checkmark"); Text("FINGERPRINTS MATCH · TRUST").font(.labl(11)) }
                            .foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
                    }.press().padding(.bottom, 10)
                    Button(action: onClose) { Text("They don't match").font(.labl(10)).foregroundStyle(t.txtMuted).frame(maxWidth: .infinity) }
                }.padding(22)
            }
        }
        .preferredColorScheme(theme.mode == .dark ? .dark : .light)
    }

    private func accessCard(_ id: String, _ label: String, _ sub: String) -> some View {
        Button { access = id } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.disp(14)).foregroundStyle(access == id ? t.accent : t.txt)
                Text(sub).font(.term(13)).foregroundStyle(t.txtMuted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(access == id ? t.accentLine : t.line))
            .background(access == id ? t.accentDim : .clear)
        }
    }
}

struct QRPlaceholder: View {
    let t: Theme
    var body: some View {
        GeometryReader { g in
            let n = 21, cell = g.size.width / CGFloat(n)
            ZStack(alignment: .topLeading) {
                t.bg2
                ForEach(0..<(n*n), id: \.self) { i in
                    let r = i / n, c = i % n
                    let finder = (r < 7 && c < 7) || (r < 7 && c > 13) || (r > 13 && c < 7)
                    let on = finder ? ((r == 0 || r == 6 || c == 0 || c == 6 || (r >= 2 && r <= 4 && c >= 2 && c <= 4)) ? true : false)
                                    : (sin(Double(i) * 12.9898).truncatingRemainder(dividingBy: 1) > 0.1)
                    if on { Rectangle().fill(t.ink).frame(width: cell, height: cell).offset(x: CGFloat(c) * cell, y: CGFloat(r) * cell) }
                }
            }
        }.padding(8)
    }
}

// MARK: - Lock Screen (Live Activity)

struct LockScreenView: View {
    @EnvironmentObject var theme: ThemeStore
    let onClose: () -> Void
    private var t: Theme { theme.t }
    private var s: Session { Sample.sessions.first { $0.status == .waiting } ?? Sample.sessions[0] }

    var body: some View {
        ZStack {
            LinearGradient(colors: theme.mode == .dark ? [Color(hex: 0x14141C), Color(hex: 0x000000)] : [Color(hex: 0xFBF5EC), Color(hex: 0xE6D8C8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                // dynamic island live activity
                HStack(spacing: 9) {
                    LogoMark(t: t, size: 18, color: t.accent)
                    Text("▶ \(s.action)").font(.term(14)).foregroundStyle(t.accent).lineLimit(1)
                    Spacer()
                    Circle().fill(t.cAdvisor).frame(width: 8, height: 8)
                }
                .padding(.horizontal, 16).frame(width: 320, height: 44).background(.black, in: Capsule()).padding(.top, 12)

                VStack(spacing: 0) {
                    Text("Thursday, July 4").font(.system(size: 15, weight: .semibold)).foregroundStyle(t.lockFg.opacity(0.8))
                    Text("9:41").font(.system(size: 82, weight: .bold)).foregroundStyle(t.lockFg)
                }.padding(.top, 40)

                Spacer()

                // live activity card
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 9) {
                        LogoMark(t: t, size: 19, color: t.txt)
                        Text("Enclave · \(s.repo)").font(.disp(14)).foregroundStyle(t.txt).textCase(.uppercase)
                        Spacer()
                        Text(s.lastSeen).font(.term(13)).foregroundStyle(t.txtMuted)
                    }.padding(.bottom, 12)
                    HStack(spacing: 8) {
                        Circle().fill(t.cAdvisor).frame(width: 7, height: 7)
                        Text("WAITING · APPROVE EDIT").font(.term(15)).foregroundStyle(t.cAdvisor)
                        Spacer()
                        Text("\(s.tokens) · \(s.cost)").font(.term(13)).foregroundStyle(t.txtMuted)
                    }.padding(.bottom, 12)
                    HStack(spacing: 8) {
                        Button(action: onClose) {
                            HStack(spacing: 6) { Image(systemName: "checkmark"); Text("APPROVE").font(.labl(11)) }
                                .foregroundStyle(t.accent).frame(maxWidth: .infinity).padding(.vertical, 11)
                                .background(t.accentDim).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.accentLine))
                        }
                        Button(action: onClose) { Text("OPEN").font(.labl(11)).foregroundStyle(t.txt).padding(.horizontal, 16).padding(.vertical, 11).overlay(RoundedRectangle(cornerRadius: 4).stroke(t.lineStrong)) }
                    }
                }.padding(14).glass(t, 4, panel: true).padding(.horizontal, 14)

                Text("SWIPE TO OPEN ENCLAVE").font(.labl(9)).foregroundStyle(t.lockFg.opacity(0.5)).padding(.vertical, 18)
            }
        }
        .onTapGesture(perform: onClose)
        .preferredColorScheme(theme.mode == .dark ? .dark : .light)
    }
}
