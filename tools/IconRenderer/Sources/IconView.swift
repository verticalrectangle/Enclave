import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum GlyphMode { case opaque, glass, flatGlass, flatGlassRing }     // how the Enclave mark is rendered
enum GlassMode { case pane, lens }        // frosted pane over backdrop, or exposed backdrop with a glass glyph

struct IconPalette {
    let backdrop: [Color]                                   // top→bottom gradient BEHIND the glass
    let blooms: [(Color, UnitPoint, CGFloat)]               // saturated iridescent blooms (color, center, radiusFrac)
    let glass: Glass                                        // .regular (frosted) or .clear (translucent)
    let tint: Color?                                        // optional .glassEffect tint
    let glassMode: GlassMode
    let glyphMode: GlyphMode
    let ink: Color                                          // mark color (opaque) / caustic shadow tint
    let coreShadow: CGFloat                                 // dark lensing-core radius frac (0 = none; deep-well family)
}

enum IconVariant: String, CaseIterable {
    // Aurora family (multi-color iridescent blooms over a deep backdrop)
    case auroraBloom   = "aurora-bloom"
    case auroraDusk    = "aurora-dusk"
    case auroraVeil    = "aurora-veil"
    case auroraPrism   = "aurora-prism"
    // Jewel family (deep, single-hue, tinted glass)
    case sapphireGlass = "sapphire-glass"
    case emeraldGlass  = "emerald-glass"
    case amethystGlass = "amethyst-glass"
    case topazGlass    = "topaz-glass"
    case rubyGlass     = "ruby-glass"
    // Midnight family (dark, dramatic, maximal refraction contrast)
    case obsidian      = "obsidian"
    case midnightBloom = "midnight-bloom"
    case deepWell      = "deep-well"
    // Frost / light family (minimalist, refined from the originals)
    case frostClear    = "frost-clear"
    case pearlOpal     = "pearl-opal"
    case liquidAero    = "liquid-aero"
    // Warm family
    case goldAmber    = "gold-amber"
    case copperBloom  = "copper-bloom"
    // Copper family (warm, vivid — expanded from the copper-bloom favorite)
    case copperVeil   = "copper-veil"
    case copperLens   = "copper-lens"
    case copperEmber  = "copper-ember"
    case copperGold   = "copper-gold"
    case copperRose   = "copper-rose"
    case copperPrism  = "copper-prism"
    case copperDeep   = "copper-deep"
    case copperGlow   = "copper-glow"
    case copperFrost  = "copper-frost"
    // Copper-glow glass treatments (disc + ring comparison)
    case copperGlowDisc = "copper-glow-disc"
    case copperGlowRing = "copper-glow-ring"
    // Lens / experimental family (glass glyph, no pane)
    case prismCaustic  = "prism-caustic"
    case gemCut        = "gem-cut"

    // Glass family — flat frosted-glass disc logo over a vivid hue backdrop (20-tile spectrum)
    case glassCrimson   = "glass-crimson"
    case glassCoral     = "glass-coral"
    case glassTangerine = "glass-tangerine"
    case glassAmber     = "glass-amber"
    case glassHoney     = "glass-honey"
    case glassCitron    = "glass-citron"
    case glassLime      = "glass-lime"
    case glassJade      = "glass-jade"
    case glassMint      = "glass-mint"
    case glassAqua      = "glass-aqua"
    case glassCyan      = "glass-cyan"
    case glassSky       = "glass-sky"
    case glassAzure     = "glass-azure"
    case glassCobalt    = "glass-cobalt"
    case glassIndigo    = "glass-indigo"
    case glassViolet    = "glass-violet"
    case glassOrchid    = "glass-orchid"
    case glassMagenta   = "glass-magenta"
    case glassRose      = "glass-rose"
    case glassBlush     = "glass-blush"

    // Glass Ring family — flat frosted-glass ring logo over a vivid hue backdrop (20-tile spectrum)
    case glassRingCrimson   = "glass-ring-crimson"
    case glassRingCoral     = "glass-ring-coral"
    case glassRingTangerine = "glass-ring-tangerine"
    case glassRingAmber     = "glass-ring-amber"
    case glassRingHoney     = "glass-ring-honey"
    case glassRingCitron    = "glass-ring-citron"
    case glassRingLime      = "glass-ring-lime"
    case glassRingJade      = "glass-ring-jade"
    case glassRingMint      = "glass-ring-mint"
    case glassRingAqua      = "glass-ring-aqua"
    case glassRingCyan      = "glass-ring-cyan"
    case glassRingSky       = "glass-ring-sky"
    case glassRingAzure     = "glass-ring-azure"
    case glassRingCobalt    = "glass-ring-cobalt"
    case glassRingIndigo    = "glass-ring-indigo"
    case glassRingViolet    = "glass-ring-violet"
    case glassRingOrchid    = "glass-ring-orchid"
    case glassRingMagenta   = "glass-ring-magenta"
    case glassRingRose      = "glass-ring-rose"
    case glassRingBlush     = "glass-ring-blush"

    private static let auroraBloomCols: [(Color, UnitPoint, CGFloat)] = [
        (Color(hex: 0x56B4C9), UnitPoint(x: 0.28, y: 0.30), 0.50),
        (Color(hex: 0x9C7BFF), UnitPoint(x: 0.72, y: 0.66), 0.50),
        (Color(hex: 0xFF6B9D), UnitPoint(x: 0.50, y: 0.16), 0.42),
    ]

    var palette: IconPalette {
        switch self {
        case .auroraBloom:    // LEAD VARIANT — refined favorite
            return .init(backdrop: [Color(hex: 0x1A1838), Color(hex: 0x0E0E22)],
                         blooms: [(Color(hex: 0x56B4C9), UnitPoint(x: 0.28, y: 0.30), 0.58),
                                  (Color(hex: 0x9C7BFF), UnitPoint(x: 0.72, y: 0.66), 0.58),
                                  (Color(hex: 0xFF6B9D), UnitPoint(x: 0.60, y: 0.18), 0.50)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xF4ECFF), coreShadow: 0)
        case .auroraDusk:
            return .init(backdrop: [Color(hex: 0x2A0F33), Color(hex: 0x120419)],
                         blooms: [(Color(hex: 0xFF5C8A), UnitPoint(x: 0.30, y: 0.34), 0.48),
                                  (Color(hex: 0xFFB347), UnitPoint(x: 0.74, y: 0.30), 0.40),
                                  (Color(hex: 0x2EC4B6), UnitPoint(x: 0.62, y: 0.78), 0.42)],
                         glass: .regular, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE9F2), coreShadow: 0)
        case .auroraVeil:
            return .init(backdrop: [Color(hex: 0x3A4A7A), Color(hex: 0x222B4D)],
                         blooms: Self.auroraBloomCols,
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xF4ECFF), coreShadow: 0)
        case .auroraPrism:
            return .init(backdrop: [Color(hex: 0x14122B), Color(hex: 0x0A0A1F)],
                         blooms: Self.auroraBloomCols,
                         glass: .regular, tint: nil, glassMode: .lens, glyphMode: .glass,
                         ink: Color(hex: 0xF4ECFF), coreShadow: 0)
        case .sapphireGlass:
            return .init(backdrop: [Color(hex: 0x0B1E3F), Color(hex: 0x050E22)],
                         blooms: [(Color(hex: 0x3DA9FC), UnitPoint(x: 0.34, y: 0.34), 0.52)],
                         glass: .regular, tint: Color(hex: 0x3DA9FC).opacity(0.30),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xEAF4FF), coreShadow: 0)
        case .emeraldGlass:
            return .init(backdrop: [Color(hex: 0x073D2E), Color(hex: 0x031F17)],
                         blooms: [(Color(hex: 0x2EC4B6), UnitPoint(x: 0.34, y: 0.34), 0.52)],
                         glass: .regular, tint: Color(hex: 0x2EC4B6).opacity(0.30),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xE7FFF8), coreShadow: 0)
        case .amethystGlass:
            return .init(backdrop: [Color(hex: 0x2A1248), Color(hex: 0x150826)],
                         blooms: [(Color(hex: 0x9C7BFF), UnitPoint(x: 0.34, y: 0.34), 0.52)],
                         glass: .regular, tint: Color(hex: 0x9C7BFF).opacity(0.32),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xF1EAFF), coreShadow: 0)
        case .topazGlass:
            return .init(backdrop: [Color(hex: 0x3A2407), Color(hex: 0x1E1203)],
                         blooms: [(Color(hex: 0xFFB347), UnitPoint(x: 0.34, y: 0.34), 0.52)],
                         glass: .regular, tint: Color(hex: 0xFFB347).opacity(0.30),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFF3DC), coreShadow: 0)
        case .rubyGlass:
            return .init(backdrop: [Color(hex: 0x3A0A1A), Color(hex: 0x1C050D)],
                         blooms: [(Color(hex: 0xFF4D6D), UnitPoint(x: 0.34, y: 0.34), 0.52)],
                         glass: .regular, tint: Color(hex: 0xFF4D6D).opacity(0.30),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE6EC), coreShadow: 0)
        case .obsidian:
            return .init(backdrop: [Color(hex: 0x1C1C22), Color(hex: 0x08080C)],
                         blooms: [(Color(hex: 0x3A4A7A), UnitPoint(x: 0.34, y: 0.30), 0.45)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xE6E6F0), coreShadow: 0)
        case .midnightBloom:
            return .init(backdrop: [Color(hex: 0x070611), Color(hex: 0x020206)],
                         blooms: Self.auroraBloomCols,
                         glass: .regular, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xF4ECFF), coreShadow: 0)
        case .deepWell:
            return .init(backdrop: [Color(hex: 0x14122B), Color(hex: 0x0A0A1F)],
                         blooms: Self.auroraBloomCols,
                         glass: .regular, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xF4ECFF), coreShadow: 0.34)
        case .frostClear:
            return .init(backdrop: [Color(hex: 0xFFFAF3), Color(hex: 0xF2EBE0)],
                         blooms: [(Color(hex: 0x56B4C9), UnitPoint(x: 0.30, y: 0.34), 0.40),
                                  (Color(hex: 0x9C7BFF), UnitPoint(x: 0.70, y: 0.66), 0.40)],
                         glass: .regular, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0x575279), coreShadow: 0)
        case .pearlOpal:
            return .init(backdrop: [Color(hex: 0xFFFBF6), Color(hex: 0xF3ECE6)],
                         blooms: [(Color(hex: 0xFFB347), UnitPoint(x: 0.30, y: 0.34), 0.32),
                                  (Color(hex: 0x56B4C9), UnitPoint(x: 0.68, y: 0.38), 0.32),
                                  (Color(hex: 0x9C7BFF), UnitPoint(x: 0.42, y: 0.70), 0.32),
                                  (Color(hex: 0xFF6B9D), UnitPoint(x: 0.70, y: 0.66), 0.32)],
                         glass: .regular, tint: Color(hex: 0x9C7BFF).opacity(0.18),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0x575279), coreShadow: 0)
        case .liquidAero:
            return .init(backdrop: [Color(hex: 0xF0F7FB), Color(hex: 0xDCEAF0)],
                         blooms: [(Color(hex: 0x56B4C9), UnitPoint(x: 0.34, y: 0.34), 0.50)],
                         glass: .clear, tint: Color(hex: 0x56B4C9).opacity(0.22),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0x2C5F70), coreShadow: 0)
        case .goldAmber:
            return .init(backdrop: [Color(hex: 0x3A2407), Color(hex: 0x1E1203)],
                         blooms: [(Color(hex: 0xFFC857), UnitPoint(x: 0.34, y: 0.30), 0.50),
                                  (Color(hex: 0xFF8C42), UnitPoint(x: 0.70, y: 0.70), 0.40)],
                         glass: .regular, tint: Color(hex: 0xFFB347).opacity(0.34),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0x3A1E00), coreShadow: 0)
        case .copperBloom:
            return .init(backdrop: [Color(hex: 0x2E1408), Color(hex: 0x180A04)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.34, y: 0.34), 0.50),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.68, y: 0.30), 0.40)],
                         glass: .regular, tint: Color(hex: 0xE8825A).opacity(0.30),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE9D6), coreShadow: 0)
        case .copperVeil:    // .clear translucent pane — vivid copper shows through
            return .init(backdrop: [Color(hex: 0x2E1408), Color(hex: 0x180A04)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.30, y: 0.32), 0.56),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.72, y: 0.64), 0.50),
                                  (Color(hex: 0xFF8C42), UnitPoint(x: 0.50, y: 0.16), 0.42)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE9D6), coreShadow: 0)
        case .copperLens:    // clear pane — vivid copper refraction (demoted from lens mode; opaque disc flattened)
            return .init(backdrop: [Color(hex: 0x241003), Color(hex: 0x140803)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.30, y: 0.32), 0.54),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.72, y: 0.64), 0.48),
                                  (Color(hex: 0xFF8C42), UnitPoint(x: 0.52, y: 0.18), 0.44)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE9D6), coreShadow: 0)
        case .copperEmber:   // .clear, deep lava/ember — maximal warm contrast
            return .init(backdrop: [Color(hex: 0x3A0F04), Color(hex: 0x1A0602)],
                         blooms: [(Color(hex: 0xFF4D2E), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF8C42), UnitPoint(x: 0.70, y: 0.30), 0.46),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.62, y: 0.78), 0.40)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFEAD8), coreShadow: 0)
        case .copperGold:    // .regular gold-tinted pane — warm metallic luxury
            return .init(backdrop: [Color(hex: 0x3A2407), Color(hex: 0x1E1203)],
                         blooms: [(Color(hex: 0xFFC857), UnitPoint(x: 0.32, y: 0.30), 0.54),
                                  (Color(hex: 0xE8825A), UnitPoint(x: 0.72, y: 0.66), 0.48)],
                         glass: .regular, tint: Color(hex: 0xFFB347).opacity(0.32),
                         glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFF3DC), coreShadow: 0)
        case .copperRose:    // .clear, copper + rose accent
            return .init(backdrop: [Color(hex: 0x33141A), Color(hex: 0x1A080C)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.30, y: 0.34), 0.54),
                                  (Color(hex: 0xFF7A8A), UnitPoint(x: 0.72, y: 0.62), 0.48),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.52, y: 0.16), 0.40)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE9E0), coreShadow: 0)
        case .copperPrism:   // clear pane — copper dispersion blooms pushed to the rim
            return .init(backdrop: [Color(hex: 0x2E1408), Color(hex: 0x140803)],
                         blooms: [(Color(hex: 0xFFC857), UnitPoint(x: 0.78, y: 0.78), 0.42),
                                  (Color(hex: 0xE8825A), UnitPoint(x: 0.82, y: 0.58), 0.36),
                                  (Color(hex: 0xFF7A8A), UnitPoint(x: 0.60, y: 0.82), 0.36)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE9D6), coreShadow: 0)
        case .copperDeep:    // .regular frosted pane with dark lensing core — dramatic well
            return .init(backdrop: [Color(hex: 0x2E1408), Color(hex: 0x140803)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.34, y: 0.34), 0.52),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.68, y: 0.30), 0.42)],
                         glass: .regular, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFE9D6), coreShadow: 0.34)
        case .copperGlow:    // .clear, max-saturation blooms — brightest refraction
            return .init(backdrop: [Color(hex: 0x3A1F0E), Color(hex: 0x1E0F06)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.30, y: 0.30), 0.62),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.72, y: 0.66), 0.56),
                                  (Color(hex: 0xFF8C42), UnitPoint(x: 0.50, y: 0.18), 0.48)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xFFF3DC), coreShadow: 0)
        case .copperFrost:   // light warm/cream backdrop — minimalist, refined from frost-clear
            return .init(backdrop: [Color(hex: 0xF7EEE6), Color(hex: 0xEAD7C4)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.30, y: 0.34), 0.42),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.70, y: 0.66), 0.42)],
                         glass: .regular, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0x5C3A1E), coreShadow: 0)
        case .copperGlowDisc:   // copper-glow palette with frosted glass disc
            return .init(backdrop: [Color(hex: 0x3A1F0E), Color(hex: 0x1E0F06)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.30, y: 0.30), 0.62),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.72, y: 0.66), 0.56),
                                  (Color(hex: 0xFF8C42), UnitPoint(x: 0.50, y: 0.18), 0.48)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .copperGlowRing:   // copper-glow palette with frosted glass ring
            return .init(backdrop: [Color(hex: 0x3A1F0E), Color(hex: 0x1E0F06)],
                         blooms: [(Color(hex: 0xE8825A), UnitPoint(x: 0.30, y: 0.30), 0.62),
                                  (Color(hex: 0xFFC857), UnitPoint(x: 0.72, y: 0.66), 0.56),
                                  (Color(hex: 0xFF8C42), UnitPoint(x: 0.50, y: 0.18), 0.48)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .prismCaustic:
            return .init(backdrop: [Color(hex: 0x14122B), Color(hex: 0x0A0A1F)],
                         blooms: [(Color(hex: 0xFFB347), UnitPoint(x: 0.78, y: 0.78), 0.40),
                                  (Color(hex: 0x56B4C9), UnitPoint(x: 0.82, y: 0.58), 0.34),
                                  (Color(hex: 0x9C7BFF), UnitPoint(x: 0.60, y: 0.82), 0.34)],
                         glass: .regular, tint: nil, glassMode: .pane, glyphMode: .opaque,
                         ink: Color(hex: 0xF4ECFF), coreShadow: 0)
        case .gemCut:
            return .init(backdrop: [Color(hex: 0x14122B), Color(hex: 0x0A0A1F)],
                         blooms: Self.auroraBloomCols,
                         glass: .regular, tint: nil, glassMode: .lens, glyphMode: .glass,
                         ink: Color(hex: 0xF4ECFF), coreShadow: 0)
        case .glassCrimson:
            return .init(backdrop: [Color(hex: 0x360D0D), Color(hex: 0x170303)],
                         blooms: [(Color(hex: 0xF63131), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF38D49), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassCoral:
            return .init(backdrop: [Color(hex: 0x36190D), Color(hex: 0x170903)],
                         blooms: [(Color(hex: 0xF66C31), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3C049), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassTangerine:
            return .init(backdrop: [Color(hex: 0x36250D), Color(hex: 0x170F03)],
                         blooms: [(Color(hex: 0xF6A831), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3F349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassAmber:
            return .init(backdrop: [Color(hex: 0x36320D), Color(hex: 0x171503)],
                         blooms: [(Color(hex: 0xF6E331), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xC0F349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassHoney:
            return .init(backdrop: [Color(hex: 0x2D360D), Color(hex: 0x131703)],
                         blooms: [(Color(hex: 0xCFF631), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x8DF349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassCitron:
            return .init(backdrop: [Color(hex: 0x21360D), Color(hex: 0x0D1703)],
                         blooms: [(Color(hex: 0x94F631), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x5AF349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassLime:
            return .init(backdrop: [Color(hex: 0x15360D), Color(hex: 0x071703)],
                         blooms: [(Color(hex: 0x59F631), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49F36B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassJade:
            return .init(backdrop: [Color(hex: 0x0D3611), Color(hex: 0x031705)],
                         blooms: [(Color(hex: 0x31F645), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49F39E), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMint:
            return .init(backdrop: [Color(hex: 0x0D361D), Color(hex: 0x03170B)],
                         blooms: [(Color(hex: 0x31F680), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49F3D1), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassAqua:
            return .init(backdrop: [Color(hex: 0x0D3629), Color(hex: 0x031711)],
                         blooms: [(Color(hex: 0x31F6BB), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49E2F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassCyan:
            return .init(backdrop: [Color(hex: 0x0D3636), Color(hex: 0x031717)],
                         blooms: [(Color(hex: 0x31F6F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49AFF3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassSky:
            return .init(backdrop: [Color(hex: 0x0D2936), Color(hex: 0x031117)],
                         blooms: [(Color(hex: 0x31BBF6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x497CF3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassAzure:
            return .init(backdrop: [Color(hex: 0x0D1D36), Color(hex: 0x030B17)],
                         blooms: [(Color(hex: 0x3180F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x4949F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassCobalt:
            return .init(backdrop: [Color(hex: 0x0D1136), Color(hex: 0x030517)],
                         blooms: [(Color(hex: 0x3145F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7C49F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassIndigo:
            return .init(backdrop: [Color(hex: 0x150D36), Color(hex: 0x070317)],
                         blooms: [(Color(hex: 0x5931F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xAF49F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassViolet:
            return .init(backdrop: [Color(hex: 0x210D36), Color(hex: 0x0D0317)],
                         blooms: [(Color(hex: 0x9431F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xE249F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassOrchid:
            return .init(backdrop: [Color(hex: 0x2D0D36), Color(hex: 0x130317)],
                         blooms: [(Color(hex: 0xCF31F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF349D1), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMagenta:
            return .init(backdrop: [Color(hex: 0x360D32), Color(hex: 0x170315)],
                         blooms: [(Color(hex: 0xF631E3), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3499E), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassRose:
            return .init(backdrop: [Color(hex: 0x360D25), Color(hex: 0x17030F)],
                         blooms: [(Color(hex: 0xF631A8), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3496B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassBlush:
            return .init(backdrop: [Color(hex: 0x360D19), Color(hex: 0x170309)],
                         blooms: [(Color(hex: 0xF6316C), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF35A49), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassRingCrimson:
            return .init(backdrop: [Color(hex: 0x360D0D), Color(hex: 0x170303)],
                         blooms: [(Color(hex: 0xF63131), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF38D49), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingCoral:
            return .init(backdrop: [Color(hex: 0x36190D), Color(hex: 0x170903)],
                         blooms: [(Color(hex: 0xF66C31), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3C049), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingTangerine:
            return .init(backdrop: [Color(hex: 0x36250D), Color(hex: 0x170F03)],
                         blooms: [(Color(hex: 0xF6A831), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3F349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingAmber:
            return .init(backdrop: [Color(hex: 0x36320D), Color(hex: 0x171503)],
                         blooms: [(Color(hex: 0xF6E331), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xC0F349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingHoney:
            return .init(backdrop: [Color(hex: 0x2D360D), Color(hex: 0x131703)],
                         blooms: [(Color(hex: 0xCFF631), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x8DF349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingCitron:
            return .init(backdrop: [Color(hex: 0x21360D), Color(hex: 0x0D1703)],
                         blooms: [(Color(hex: 0x94F631), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x5AF349), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingLime:
            return .init(backdrop: [Color(hex: 0x15360D), Color(hex: 0x071703)],
                         blooms: [(Color(hex: 0x59F631), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49F36B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingJade:
            return .init(backdrop: [Color(hex: 0x0D3611), Color(hex: 0x031705)],
                         blooms: [(Color(hex: 0x31F645), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49F39E), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingMint:
            return .init(backdrop: [Color(hex: 0x0D361D), Color(hex: 0x03170B)],
                         blooms: [(Color(hex: 0x31F680), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49F3D1), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingAqua:
            return .init(backdrop: [Color(hex: 0x0D3629), Color(hex: 0x031711)],
                         blooms: [(Color(hex: 0x31F6BB), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49E2F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingCyan:
            return .init(backdrop: [Color(hex: 0x0D3636), Color(hex: 0x031717)],
                         blooms: [(Color(hex: 0x31F6F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x49AFF3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingSky:
            return .init(backdrop: [Color(hex: 0x0D2936), Color(hex: 0x031117)],
                         blooms: [(Color(hex: 0x31BBF6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x497CF3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingAzure:
            return .init(backdrop: [Color(hex: 0x0D1D36), Color(hex: 0x030B17)],
                         blooms: [(Color(hex: 0x3180F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x4949F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingCobalt:
            return .init(backdrop: [Color(hex: 0x0D1136), Color(hex: 0x030517)],
                         blooms: [(Color(hex: 0x3145F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7C49F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingIndigo:
            return .init(backdrop: [Color(hex: 0x150D36), Color(hex: 0x070317)],
                         blooms: [(Color(hex: 0x5931F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xAF49F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingViolet:
            return .init(backdrop: [Color(hex: 0x210D36), Color(hex: 0x0D0317)],
                         blooms: [(Color(hex: 0x9431F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xE249F3), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingOrchid:
            return .init(backdrop: [Color(hex: 0x2D0D36), Color(hex: 0x130317)],
                         blooms: [(Color(hex: 0xCF31F6), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF349D1), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingMagenta:
            return .init(backdrop: [Color(hex: 0x360D32), Color(hex: 0x170315)],
                         blooms: [(Color(hex: 0xF631E3), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3499E), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingRose:
            return .init(backdrop: [Color(hex: 0x360D25), Color(hex: 0x17030F)],
                         blooms: [(Color(hex: 0xF631A8), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF3496B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassRingBlush:
            return .init(backdrop: [Color(hex: 0x360D19), Color(hex: 0x170309)],
                         blooms: [(Color(hex: 0xF6316C), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF35A49), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        }
    }
}

struct GlassRing: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.addArc(center: center, radius: outerRadius, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: .zero, endAngle: .degrees(360), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct IconView: View {
    let variant: IconVariant
    private var p: IconPalette { variant.palette }

    var body: some View {
        GeometryReader { geo in
            let S = min(geo.size.width, geo.size.height)
            let shape = RoundedRectangle(cornerRadius: S * 0.2237, style: .continuous)
            ZStack {
                // (A) vivid backdrop — gives the glass real content to refract
                LinearGradient(colors: p.backdrop, startPoint: .top, endPoint: .bottom)
                // (A) saturated iridescent blooms behind the glass
                ForEach(Array(p.blooms.enumerated()), id: \.offset) { _, b in
                    RadialGradient(colors: [b.0.opacity(0.98), .clear],
                                   center: b.1, startRadius: 0, endRadius: S * b.2)
                }
                // optional dark lensing core (deep-well family)
                if p.coreShadow > 0 {
                    RadialGradient(colors: [.black.opacity(0.6), .clear],
                                   center: .center, startRadius: 0, endRadius: S * p.coreShadow)
                }

                if p.glassMode == .pane {
                    // (B) the system glass + (C) optical overlays + glyph on top
                    Rectangle()
                        .fill(.white.opacity(0.001))
                        .glassEffect(p.tint.map { p.glass.tint($0) } ?? p.glass, in: shape)
                        .overlay { opticalOverlays(shape: shape, S: S) }
                        .overlay { markLayer(S: S) }
                } else {
                    // lens mode: no pane; the glyph disc is the only glass element
                    opticalOverlays(shape: shape, S: S)
                    markLayer(S: S)
                }
            }
            .clipShape(shape)
            .frame(width: S, height: S)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func markLayer(S: CGFloat) -> some View {
        switch p.glyphMode {
        case .opaque:
            EnclaveMark(side: S, ink: p.ink)
                .shadow(color: .black.opacity(0.35), radius: S * 0.006,
                        x: S * 0.003, y: S * 0.008)
        case .glass:
            // glass disc lens refracting the backdrop, with the ink mark on top
            ZStack {
                Circle().fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: .circle)
                EnclaveMark(side: S, ink: p.ink)
                    .shadow(color: .black.opacity(0.30), radius: S * 0.005,
                            x: S * 0.003, y: S * 0.007)
            }
            .frame(width: S * 0.82, height: S * 0.82)
        case .flatGlass:
            // flat frosted-glass disc tile (iOS 26 Liquid Glass control); slit as etched seam
            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: .circle)
                    .overlay(alignment: .center) {
                        EnclaveSlit(open: 1)
                            .stroke(Color.white.opacity(0.65),
                                    style: StrokeStyle(lineWidth: S * 0.06,
                                                        lineCap: .round, lineJoin: .round))
                    }
                Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: S * 0.004)
            }
            .frame(width: S * 0.82, height: S * 0.82)
            .shadow(color: .black.opacity(0.22), radius: S * 0.010, x: 0, y: S * 0.006)
        case .flatGlassRing:
            // flat frosted-glass ring tile; thick stroke becomes the glass ring, slit etched in center
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.001), lineWidth: S * 0.16)
                    .glassEffect(.regular, in: .circle)
                    .overlay(alignment: .center) {
                        EnclaveSlit(open: 1)
                            .stroke(Color.white.opacity(0.65),
                                    style: StrokeStyle(lineWidth: S * 0.06,
                                                        lineCap: .round, lineJoin: .round))
                    }
                GlassRing(innerRadius: S * 0.33, outerRadius: S * 0.41)
                    .stroke(Color.white.opacity(0.55), lineWidth: S * 0.004)
            }
            .frame(width: S * 0.82, height: S * 0.82)
            .shadow(color: .black.opacity(0.22), radius: S * 0.010, x: 0, y: S * 0.006)
        }
    }

    // (C) the explicit optical overlays .glassEffect does not give strongly enough
    @ViewBuilder
    private func opticalOverlays(shape: RoundedRectangle, S: CGFloat) -> some View {
        ZStack {
            // iridescent dispersion rim (chromatic aberration at the curved edge)
            shape.stroke(
                AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, Color(hex: 0xFF00FF), .red],
                                center: .center),
                lineWidth: S * 0.018)
                .opacity(0.70)
                .blur(radius: S * 0.0035)
            // bright specular top highlight (the glass glint)
            LinearGradient(colors: [.white.opacity(0.98), .clear],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.18))
                .mask(shape)
            // convex face gloss
            LinearGradient(colors: [.white.opacity(0.28), .clear, .black.opacity(0.15)],
                           startPoint: .top, endPoint: .bottom)
                .mask(shape)
                .blendMode(.overlay)
            // bottom inner depth shadow (glass thickness/volume)
            shape.strokeBorder(
                LinearGradient(colors: [.clear, .black.opacity(0.45)],
                               startPoint: .center, endPoint: .bottom),
                lineWidth: S * 0.024)
        }
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
