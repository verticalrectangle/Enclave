import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

enum IconVariant: String, CaseIterable {
    case frostClear = "frost-clear", goldAmber = "gold-amber", deepWell = "deep-well"
    case auroraBloom = "aurora-bloom", prismCaustic = "prism-caustic", pearlOpal = "pearl-opal"

    var backdrop: [Color] { switch self {
        case .frostClear:   [Color(hex: 0xFFFAF3), Color(hex: 0xFAF4ED)]
        case .goldAmber:    [Color(hex: 0xFFFAF3), Color(hex: 0xFBF0DC), Color(hex: 0xF6E7C8)]
        case .deepWell:     [Color(hex: 0xFFFAF3), Color(hex: 0xFAF4ED)]
        case .auroraBloom:  [Color(hex: 0xFFF5ED), Color(hex: 0xFFFAF3), Color(hex: 0xFAF4ED)]
        case .prismCaustic: [Color(hex: 0xFFFAF3), Color(hex: 0xFAF4ED)]
        case .pearlOpal:    [Color(hex: 0xFFFBF6), Color(hex: 0xF8F2EC)]
    }}
    var tint: Color? { switch self {            // nil → untinted .regular
        case .frostClear, .auroraBloom, .deepWell: nil
        case .goldAmber:    Color(hex: 0xEA9D34, alpha: 0.55)
        case .prismCaustic: Color(hex: 0xEA9D34, alpha: 0.40)
        case .pearlOpal:    Color(hex: 0x907AA9, alpha: 0.45)
    }}
    var blooms: [(Color, UnitPoint, CGFloat)] { switch self {   // behind-glass iridescence (x,y,radiusFrac)
        case .frostClear, .goldAmber, .deepWell: []
        case .auroraBloom:  [(Color(hex: 0x56949F), UnitPoint(x: 0.30, y: 0.35), 0.45),
                             (Color(hex: 0x907AA9), UnitPoint(x: 0.70, y: 0.65), 0.45),
                             (Color(hex: 0xB4637A), UnitPoint(x: 0.50, y: 0.20), 0.40)]
        case .prismCaustic: [(Color(hex: 0xEA9D34), UnitPoint(x: 0.78, y: 0.78), 0.38),
                             (Color(hex: 0x56949F), UnitPoint(x: 0.82, y: 0.58), 0.32),
                             (Color(hex: 0x907AA9), UnitPoint(x: 0.60, y: 0.82), 0.32)]
        case .pearlOpal:    [(Color(hex: 0xEA9D34), UnitPoint(x: 0.30, y: 0.35), 0.35),
                             (Color(hex: 0x56949F), UnitPoint(x: 0.68, y: 0.38), 0.35),
                             (Color(hex: 0x907AA9), UnitPoint(x: 0.42, y: 0.70), 0.35),
                             (Color(hex: 0xB4637A), UnitPoint(x: 0.70, y: 0.66), 0.35)]
    }}
}

struct IconView: View {
    let variant: IconVariant
    var body: some View {
        GeometryReader { geo in
            let S = min(geo.size.width, geo.size.height)
            let shape = RoundedRectangle(cornerRadius: S * 0.2237, style: .continuous)
            ZStack {
                LinearGradient(colors: variant.backdrop, startPoint: .top, endPoint: .bottom)
                ForEach(Array(variant.blooms.enumerated()), id: \.offset) { _, b in
                    RadialGradient(colors: [b.0.opacity(0.55), .clear], center: b.1,
                                   startRadius: 0, endRadius: S * b.2)
                }
                if variant == .deepWell {                                   // dark lensing core
                    RadialGradient(colors: [.black.opacity(0.55), .clear], center: .center,
                                   startRadius: 0, endRadius: S * 0.32)
                }
                shape.fill(.white.opacity(0.001))
                    .glassEffect(variant.tint.map { .regular.tint($0) } ?? .regular, in: shape)
                    .overlay {
                        EnclaveMark(side: S, ink: Color(hex: 0x575279))
                            .shadow(color: .black.opacity(0.28), radius: S * 0.005,
                                    x: S * 0.003, y: S * 0.005)
                    }
            }
            .frame(width: S, height: S)
            .frame(width: geo.size.width, height: geo.size.height)           // center the square
        }
        .ignoresSafeArea()
    }
}

struct EnclaveMark: View {                                                   // canonical mark, matches the app
    let side: CGFloat; let ink: Color
    var body: some View {
        ZStack {
            Circle().stroke(ink, lineWidth: side * 0.075)
            EnclaveSlit(open: 1).stroke(ink, style: StrokeStyle(lineWidth: side * 0.06,
                                                                 lineCap: .round, lineJoin: .round))
        }
        .frame(width: side * 0.82, height: side * 0.82)
    }
}
