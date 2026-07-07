//  EnclaveWidgets.swift
//  The EnclaveWidgets app-extension: the omp session Live Activity, rendered on
//  the lock screen and in the Dynamic Island from EnclaveActivityAttributes.
//  Vertical-Rectangle voice: near-black, amber accent, mono-ish system.

import WidgetKit
import SwiftUI
import ActivityKit

@main
struct EnclaveWidgets: WidgetBundle {
    var body: some Widget { EnclaveLiveActivity() }
}

private let amber = Color(red: 1.0, green: 0.72, blue: 0.31)   // 0xFFB850
private let love  = Color(red: 0.91, green: 0.57, blue: 0.62)  // waiting/alert

private func statusColor(_ s: EnclaveActivityAttributes.ContentState) -> Color {
    s.waiting ? love : (s.working ? amber : .white.opacity(0.5))
}

struct EnclaveLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: EnclaveActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.92))
                .activitySystemActionForegroundColor(amber)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RingMark().foregroundStyle(statusColor(s)).frame(width: 30, height: 30).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(s.tokens.isEmpty ? " " : s.tokens).font(.caption2).monospaced().foregroundStyle(.white.opacity(0.6))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title.isEmpty ? "session" : s.title).font(.footnote).bold().foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 6) {
                            Circle().fill(statusColor(s)).frame(width: 6, height: 6)
                            Text(s.action.isEmpty ? "live" : s.action).font(.caption).foregroundStyle(statusColor(s)).lineLimit(1)
                            Spacer(minLength: 8)
                            if !s.model.isEmpty { Text(s.model).font(.caption2).foregroundStyle(.white.opacity(0.45)).lineLimit(1) }
                        }
                    }.padding(.top, 2)
                }
            } compactLeading: {
                RingMark().foregroundStyle(statusColor(s)).frame(width: 18, height: 18)
            } compactTrailing: {
                if s.waiting { Text("ask").font(.caption2).bold().foregroundStyle(love) }
                else if s.working { Circle().fill(amber).frame(width: 7, height: 7) }
            } minimal: {
                RingMark().foregroundStyle(statusColor(s)).frame(width: 18, height: 18)
            }
            .keylineTint(amber)
        }
    }
}

private struct LockScreenView: View {
    let state: EnclaveActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            RingMark().foregroundStyle(statusColor(state)).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title).font(.subheadline).bold().foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    Circle().fill(statusColor(state)).frame(width: 6, height: 6)
                    Text(state.action).font(.caption).foregroundStyle(statusColor(state)).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(state.tokens).font(.caption).monospaced().foregroundStyle(.white.opacity(0.7))
                Text(state.model).font(.caption2).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
        }
        .padding(16)
    }
}

// The Enclave ring + sealed-slit mark.
private struct RingMark: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height) * 0.9   // inset so the ring stroke isn't clipped
            ZStack {
                Circle().stroke(lineWidth: s * 0.08)
                EnclaveSlit().stroke(style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round, lineJoin: .round))
            }
            .frame(width: s, height: s)
            .frame(width: g.size.width, height: g.size.height)   // center within the frame
        }
    }
}
