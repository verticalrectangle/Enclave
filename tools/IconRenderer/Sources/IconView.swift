import SwiftUI
import UIKit

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Glossy 3D ball shading (ported from PopMakerOrbs.swift)
extension Color {
    /// Brightness-scaled shade for sphere shading. f>1 → lighter + desaturated
    /// (the lit highlight side); f<1 → darker + more saturated (the shadow side).
    func shade(_ f: Double) -> Color {
        let u = UIColor(self); var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h),
                     saturation: Double(max(0, min(1, s * (f > 1 ? 0.62 : 1.18)))),
                     brightness: Double(max(0, min(1, b * f))),
                     opacity: Double(a))
    }
}

enum GlyphMode { case opaque, glass, flatGlass, flatGlassRing, liquidMark }     // how the Enclave mark is rendered
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
    let shimmer: Bool                                       // false = suppress optical overlays (rainbow rim + specular/gloss)

    init(backdrop: [Color], blooms: [(Color, UnitPoint, CGFloat)], glass: Glass, tint: Color?, glassMode: GlassMode, glyphMode: GlyphMode, ink: Color, coreShadow: CGFloat, shimmer: Bool = true) {
        self.backdrop = backdrop
        self.blooms = blooms
        self.glass = glass
        self.tint = tint
        self.glassMode = glassMode
        self.glyphMode = glyphMode
        self.ink = ink
        self.coreShadow = coreShadow
        self.shimmer = shimmer
    }
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

    // Pastel glass family — pastel
    case glassPastelLavender = "glass-pastel-lavender"
    case glassPastelLavenderRing = "glass-pastel-lavender-ring"
    case glassPastelMint = "glass-pastel-mint"
    case glassPastelMintRing = "glass-pastel-mint-ring"
    case glassPastelPeach = "glass-pastel-peach"
    case glassPastelPeachRing = "glass-pastel-peach-ring"
    case glassPastelSky = "glass-pastel-sky"
    case glassPastelSkyRing = "glass-pastel-sky-ring"
    case glassPastelLemon = "glass-pastel-lemon"
    case glassPastelLemonRing = "glass-pastel-lemon-ring"
    case glassPastelRose = "glass-pastel-rose"
    case glassPastelRoseRing = "glass-pastel-rose-ring"
    case glassPastelLilac = "glass-pastel-lilac"
    case glassPastelLilacRing = "glass-pastel-lilac-ring"
    case glassPastelAqua = "glass-pastel-aqua"
    case glassPastelAquaRing = "glass-pastel-aqua-ring"
    // Neon glass family — neon
    case glassNeonMagenta = "glass-neon-magenta"
    case glassNeonMagentaRing = "glass-neon-magenta-ring"
    case glassNeonLime = "glass-neon-lime"
    case glassNeonLimeRing = "glass-neon-lime-ring"
    case glassNeonCyan = "glass-neon-cyan"
    case glassNeonCyanRing = "glass-neon-cyan-ring"
    case glassNeonYellow = "glass-neon-yellow"
    case glassNeonYellowRing = "glass-neon-yellow-ring"
    case glassNeonOrange = "glass-neon-orange"
    case glassNeonOrangeRing = "glass-neon-orange-ring"
    case glassNeonPurple = "glass-neon-purple"
    case glassNeonPurpleRing = "glass-neon-purple-ring"
    case glassNeonGreen = "glass-neon-green"
    case glassNeonGreenRing = "glass-neon-green-ring"
    case glassNeonPink = "glass-neon-pink"
    case glassNeonPinkRing = "glass-neon-pink-ring"
    // Mono glass family — mono
    case glassMonoObsidian = "glass-mono-obsidian"
    case glassMonoObsidianRing = "glass-mono-obsidian-ring"
    case glassMonoCharcoal = "glass-mono-charcoal"
    case glassMonoCharcoalRing = "glass-mono-charcoal-ring"
    case glassMonoSlate = "glass-mono-slate"
    case glassMonoSlateRing = "glass-mono-slate-ring"
    case glassMonoSilver = "glass-mono-silver"
    case glassMonoSilverRing = "glass-mono-silver-ring"
    case glassMonoIvory = "glass-mono-ivory"
    case glassMonoIvoryRing = "glass-mono-ivory-ring"
    case glassMonoFog = "glass-mono-fog"
    case glassMonoFogRing = "glass-mono-fog-ring"
    case glassMonoInk = "glass-mono-ink"
    case glassMonoInkRing = "glass-mono-ink-ring"
    case glassMonoMist = "glass-mono-mist"
    case glassMonoMistRing = "glass-mono-mist-ring"
    // UI-color variants — solid Rosé Pine backdrop, liquid-glass mark, no shimmer
    case uiIris       = "ui-iris"
    case uiFoam       = "ui-foam"
    case uiGold       = "ui-gold"
    case uiPine       = "ui-pine"
    case uiRose       = "ui-rose"
    case uiLove       = "ui-love"
    case uiMuted      = "ui-muted"
    case uiIrisDark   = "ui-iris-dark"
    case uiFoamDark   = "ui-foam-dark"
    case uiGoldDark   = "ui-gold-dark"
    case uiPineDark   = "ui-pine-dark"
    case uiRoseDark   = "ui-rose-dark"
    case uiLoveDark   = "ui-love-dark"
    case uiMutedDark  = "ui-muted-dark"
    case uiAccent     = "ui-accent"
    // Curated flat-glass variants — solid vivid backdrop, flat frosted-glass mark, no shimmer
    case fgOcean           = "fg-ocean"
    case fgGrape           = "fg-grape"
    case fgEmber           = "fg-ember"
    case fgJade            = "fg-jade"
    case fgCobalt          = "fg-cobalt"
    case fgMagenta         = "fg-magenta"
    case fgBronze          = "fg-bronze"
    case fgOceanDark       = "fg-ocean-dark"
    case fgGrapeDark       = "fg-grape-dark"
    case fgEmberDark       = "fg-ember-dark"
    case fgJadeDark        = "fg-jade-dark"
    case fgCobaltDark      = "fg-cobalt-dark"
    case fgMagentaDark     = "fg-magenta-dark"
    case fgBronzeDark      = "fg-bronze-dark"
    case fgOceanRing       = "fg-ocean-ring"
    case fgGrapeRing       = "fg-grape-ring"
    case fgEmberRing       = "fg-ember-ring"
    case fgJadeRing        = "fg-jade-ring"
    case fgCobaltRing      = "fg-cobalt-ring"
    case fgMagentaRing     = "fg-magenta-ring"
    case fgBronzeRing      = "fg-bronze-ring"
    case fgOceanRingDark   = "fg-ocean-ring-dark"
    case fgGrapeRingDark   = "fg-grape-ring-dark"
    case fgEmberRingDark   = "fg-ember-ring-dark"
    case fgJadeRingDark    = "fg-jade-ring-dark"
    case fgCobaltRingDark  = "fg-cobalt-ring-dark"
    case fgMagentaRingDark = "fg-magenta-ring-dark"
    case fgBronzeRingDark  = "fg-bronze-ring-dark"

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
        // Pastel glass family — pastel
        case .glassPastelLavender:
            return .init(backdrop: [Color(hex: 0x2D1F3A), Color(hex: 0x1A1221)],
                         blooms: [(Color(hex: 0xD4B8FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x9B7BFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelLavenderRing:
            return .init(backdrop: [Color(hex: 0x2D1F3A), Color(hex: 0x1A1221)],
                         blooms: [(Color(hex: 0xD4B8FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x9B7BFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassPastelMint:
            return .init(backdrop: [Color(hex: 0x1F3A2D), Color(hex: 0x122116)],
                         blooms: [(Color(hex: 0xB8FFD4), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7BFF9B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelMintRing:
            return .init(backdrop: [Color(hex: 0x1F3A2D), Color(hex: 0x122116)],
                         blooms: [(Color(hex: 0xB8FFD4), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7BFF9B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassPastelPeach:
            return .init(backdrop: [Color(hex: 0x3A2A1F), Color(hex: 0x211612)],
                         blooms: [(Color(hex: 0xFFD4B8), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF9B7B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelPeachRing:
            return .init(backdrop: [Color(hex: 0x3A2A1F), Color(hex: 0x211612)],
                         blooms: [(Color(hex: 0xFFD4B8), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF9B7B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassPastelSky:
            return .init(backdrop: [Color(hex: 0x1F2A3A), Color(hex: 0x121621)],
                         blooms: [(Color(hex: 0xB8E4FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7BB8FF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelSkyRing:
            return .init(backdrop: [Color(hex: 0x1F2A3A), Color(hex: 0x121621)],
                         blooms: [(Color(hex: 0xB8E4FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7BB8FF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassPastelLemon:
            return .init(backdrop: [Color(hex: 0x3A3A1F), Color(hex: 0x212112)],
                         blooms: [(Color(hex: 0xFFFFB8), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFFFF7B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelLemonRing:
            return .init(backdrop: [Color(hex: 0x3A3A1F), Color(hex: 0x212112)],
                         blooms: [(Color(hex: 0xFFFFB8), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFFFF7B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassPastelRose:
            return .init(backdrop: [Color(hex: 0x3A1F2A), Color(hex: 0x211216)],
                         blooms: [(Color(hex: 0xFFB8D4), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF7B9B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelRoseRing:
            return .init(backdrop: [Color(hex: 0x3A1F2A), Color(hex: 0x211216)],
                         blooms: [(Color(hex: 0xFFB8D4), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF7B9B), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassPastelLilac:
            return .init(backdrop: [Color(hex: 0x2A1F3A), Color(hex: 0x161221)],
                         blooms: [(Color(hex: 0xE4B8FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xB87BFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelLilacRing:
            return .init(backdrop: [Color(hex: 0x2A1F3A), Color(hex: 0x161221)],
                         blooms: [(Color(hex: 0xE4B8FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xB87BFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassPastelAqua:
            return .init(backdrop: [Color(hex: 0x1F3A3A), Color(hex: 0x122121)],
                         blooms: [(Color(hex: 0xB8FFFF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7BFFFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassPastelAquaRing:
            return .init(backdrop: [Color(hex: 0x1F3A3A), Color(hex: 0x122121)],
                         blooms: [(Color(hex: 0xB8FFFF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x7BFFFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        // Neon glass family — neon
        case .glassNeonMagenta:
            return .init(backdrop: [Color(hex: 0x360D32), Color(hex: 0x170315)],
                         blooms: [(Color(hex: 0xFF00FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF33CC), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonMagentaRing:
            return .init(backdrop: [Color(hex: 0x360D32), Color(hex: 0x170315)],
                         blooms: [(Color(hex: 0xFF00FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF33CC), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassNeonLime:
            return .init(backdrop: [Color(hex: 0x15360D), Color(hex: 0x071703)],
                         blooms: [(Color(hex: 0xCCFF00), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x66FF00), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonLimeRing:
            return .init(backdrop: [Color(hex: 0x15360D), Color(hex: 0x071703)],
                         blooms: [(Color(hex: 0xCCFF00), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x66FF00), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassNeonCyan:
            return .init(backdrop: [Color(hex: 0x0D3636), Color(hex: 0x031717)],
                         blooms: [(Color(hex: 0x00FFFF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x33CCFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonCyanRing:
            return .init(backdrop: [Color(hex: 0x0D3636), Color(hex: 0x031717)],
                         blooms: [(Color(hex: 0x00FFFF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x33CCFF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassNeonYellow:
            return .init(backdrop: [Color(hex: 0x36320D), Color(hex: 0x171503)],
                         blooms: [(Color(hex: 0xFFFF00), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFFCC00), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonYellowRing:
            return .init(backdrop: [Color(hex: 0x36320D), Color(hex: 0x171503)],
                         blooms: [(Color(hex: 0xFFFF00), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFFCC00), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassNeonOrange:
            return .init(backdrop: [Color(hex: 0x36250D), Color(hex: 0x170F03)],
                         blooms: [(Color(hex: 0xFF6600), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF9900), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonOrangeRing:
            return .init(backdrop: [Color(hex: 0x36250D), Color(hex: 0x170F03)],
                         blooms: [(Color(hex: 0xFF6600), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF9900), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassNeonPurple:
            return .init(backdrop: [Color(hex: 0x210D36), Color(hex: 0x0D0317)],
                         blooms: [(Color(hex: 0x9900FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xCC33FF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonPurpleRing:
            return .init(backdrop: [Color(hex: 0x210D36), Color(hex: 0x0D0317)],
                         blooms: [(Color(hex: 0x9900FF), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xCC33FF), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassNeonGreen:
            return .init(backdrop: [Color(hex: 0x0D3611), Color(hex: 0x031705)],
                         blooms: [(Color(hex: 0x00FF66), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x33FF99), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonGreenRing:
            return .init(backdrop: [Color(hex: 0x0D3611), Color(hex: 0x031705)],
                         blooms: [(Color(hex: 0x00FF66), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x33FF99), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassNeonPink:
            return .init(backdrop: [Color(hex: 0x360D25), Color(hex: 0x17030F)],
                         blooms: [(Color(hex: 0xFF3399), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF66B2), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassNeonPinkRing:
            return .init(backdrop: [Color(hex: 0x360D25), Color(hex: 0x17030F)],
                         blooms: [(Color(hex: 0xFF3399), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xFF66B2), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        // Mono glass family — mono
        case .glassMonoObsidian:
            return .init(backdrop: [Color(hex: 0x0A0A0A), Color(hex: 0x050505)],
                         blooms: [(Color(hex: 0x333333), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x555555), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoObsidianRing:
            return .init(backdrop: [Color(hex: 0x0A0A0A), Color(hex: 0x050505)],
                         blooms: [(Color(hex: 0x333333), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x555555), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassMonoCharcoal:
            return .init(backdrop: [Color(hex: 0x1A1A1A), Color(hex: 0x0F0F0F)],
                         blooms: [(Color(hex: 0x555555), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x777777), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoCharcoalRing:
            return .init(backdrop: [Color(hex: 0x1A1A1A), Color(hex: 0x0F0F0F)],
                         blooms: [(Color(hex: 0x555555), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x777777), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassMonoSlate:
            return .init(backdrop: [Color(hex: 0x2A2A2A), Color(hex: 0x1A1A1A)],
                         blooms: [(Color(hex: 0x777777), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x999999), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoSlateRing:
            return .init(backdrop: [Color(hex: 0x2A2A2A), Color(hex: 0x1A1A1A)],
                         blooms: [(Color(hex: 0x777777), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x999999), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassMonoSilver:
            return .init(backdrop: [Color(hex: 0x3A3A3A), Color(hex: 0x252525)],
                         blooms: [(Color(hex: 0xAAAAAA), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xCCCCCC), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoSilverRing:
            return .init(backdrop: [Color(hex: 0x3A3A3A), Color(hex: 0x252525)],
                         blooms: [(Color(hex: 0xAAAAAA), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xCCCCCC), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassMonoIvory:
            return .init(backdrop: [Color(hex: 0x4A4A4A), Color(hex: 0x353535)],
                         blooms: [(Color(hex: 0xDDDDDD), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF0F0F0), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoIvoryRing:
            return .init(backdrop: [Color(hex: 0x4A4A4A), Color(hex: 0x353535)],
                         blooms: [(Color(hex: 0xDDDDDD), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xF0F0F0), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassMonoFog:
            return .init(backdrop: [Color(hex: 0x3A3A3A), Color(hex: 0x252525)],
                         blooms: [(Color(hex: 0xBBBBBB), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xDDDDDD), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoFogRing:
            return .init(backdrop: [Color(hex: 0x3A3A3A), Color(hex: 0x252525)],
                         blooms: [(Color(hex: 0xBBBBBB), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xDDDDDD), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassMonoInk:
            return .init(backdrop: [Color(hex: 0x050505), Color(hex: 0x020202)],
                         blooms: [(Color(hex: 0x222222), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x444444), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoInkRing:
            return .init(backdrop: [Color(hex: 0x050505), Color(hex: 0x020202)],
                         blooms: [(Color(hex: 0x222222), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x444444), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        case .glassMonoMist:
            return .init(backdrop: [Color(hex: 0x2A2A2A), Color(hex: 0x1A1A1A)],
                         blooms: [(Color(hex: 0x888888), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xAAAAAA), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .glassMonoMistRing:
            return .init(backdrop: [Color(hex: 0x2A2A2A), Color(hex: 0x1A1A1A)],
                         blooms: [(Color(hex: 0x888888), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0xAAAAAA), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)
        // ── UI-color variants: solid Rosé Pine backdrop, liquid-glass mark, no shimmer ──
        case .uiIris:
            return .init(backdrop: [Color(hex: 0x907AA9), Color(hex: 0x907AA9)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiFoam:
            return .init(backdrop: [Color(hex: 0x56949F), Color(hex: 0x56949F)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiGold:
            return .init(backdrop: [Color(hex: 0xEA9D34), Color(hex: 0xEA9D34)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiPine:
            return .init(backdrop: [Color(hex: 0x286983), Color(hex: 0x286983)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiRose:
            return .init(backdrop: [Color(hex: 0xD7827E), Color(hex: 0xD7827E)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiLove:
            return .init(backdrop: [Color(hex: 0xB4637A), Color(hex: 0xB4637A)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiMuted:
            return .init(backdrop: [Color(hex: 0x9893A5), Color(hex: 0x9893A5)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiIrisDark:
            return .init(backdrop: [Color(hex: 0xC4A7E7), Color(hex: 0xC4A7E7)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiFoamDark:
            return .init(backdrop: [Color(hex: 0x9CCFD8), Color(hex: 0x9CCFD8)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiGoldDark:
            return .init(backdrop: [Color(hex: 0xF6C177), Color(hex: 0xF6C177)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiPineDark:
            return .init(backdrop: [Color(hex: 0x3E8FB0), Color(hex: 0x3E8FB0)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiRoseDark:
            return .init(backdrop: [Color(hex: 0xEBBCBA), Color(hex: 0xEBBCBA)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiLoveDark:
            return .init(backdrop: [Color(hex: 0xE8919F), Color(hex: 0xE8919F)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiMutedDark:
            return .init(backdrop: [Color(hex: 0x6E6A86), Color(hex: 0x6E6A86)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        case .uiAccent:
            return .init(backdrop: [Color(hex: 0xC8D6E5), Color(hex: 0xC8D6E5)],
                         blooms: [], glass: .clear, tint: nil, glassMode: .lens,
                         glyphMode: .liquidMark, ink: .white, coreShadow: 0, shimmer: false)
        // ── Curated flat-glass variants: solid vivid backdrop, flat frosted disc/ring mark ──
        case .fgOcean:      return fg(hex: 0x1A6E8C)
        case .fgGrape:      return fg(hex: 0x6B3FA0)
        case .fgEmber:      return fg(hex: 0xC0452C)
        case .fgJade:       return fg(hex: 0x2A7553)
        case .fgCobalt:     return fg(hex: 0x2A45C7)
        case .fgMagenta:    return fg(hex: 0xB03370)
        case .fgBronze:     return fg(hex: 0x946018)
        case .fgOceanDark:  return fg(hex: 0x4DB8D4)
        case .fgGrapeDark:  return fg(hex: 0xA880DC)
        case .fgEmberDark:  return fg(hex: 0xE97550)
        case .fgJadeDark:   return fg(hex: 0x5DBA8E)
        case .fgCobaltDark: return fg(hex: 0x6B85E8)
        case .fgMagentaDark:return fg(hex: 0xE06BA8)
        case .fgBronzeDark: return fg(hex: 0xCC9038)
        case .fgOceanRing:      return fgRing(hex: 0x1A6E8C)
        case .fgGrapeRing:      return fgRing(hex: 0x6B3FA0)
        case .fgEmberRing:      return fgRing(hex: 0xC0452C)
        case .fgJadeRing:       return fgRing(hex: 0x2A7553)
        case .fgCobaltRing:     return fgRing(hex: 0x2A45C7)
        case .fgMagentaRing:    return fgRing(hex: 0xB03370)
        case .fgBronzeRing:     return fgRing(hex: 0x946018)
        case .fgOceanRingDark:  return fgRing(hex: 0x4DB8D4)
        case .fgGrapeRingDark:  return fgRing(hex: 0xA880DC)
        case .fgEmberRingDark:  return fgRing(hex: 0xE97550)
        case .fgJadeRingDark:   return fgRing(hex: 0x5DBA8E)
        case .fgCobaltRingDark: return fgRing(hex: 0x6B85E8)
        case .fgMagentaRingDark:return fgRing(hex: 0xE06BA8)
        case .fgBronzeRingDark: return fgRing(hex: 0xCC9038)
        }
    }
    private func fg(hex: UInt) -> IconPalette {
        .init(backdrop: [Color(hex: hex), Color(hex: hex)], blooms: [], glass: .clear,
              tint: nil, glassMode: .lens, glyphMode: .flatGlass, ink: .white, coreShadow: 0, shimmer: false)
    }
    private func fgRing(hex: UInt) -> IconPalette {
        .init(backdrop: [Color(hex: hex), Color(hex: hex)], blooms: [], glass: .clear,
              tint: nil, glassMode: .lens, glyphMode: .flatGlassRing, ink: .white, coreShadow: 0, shimmer: false)
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
    private let dim: Int = {
        Int(ProcessInfo.processInfo.environment["ENCLAVE_DIM"] ?? "0") ?? 0
    }()
    private let tint: Int = {
        Int(ProcessInfo.processInfo.environment["ENCLAVE_TINT"] ?? "0") ?? 0
    }()
    private let slit: Int = {
        Int(ProcessInfo.processInfo.environment["ENCLAVE_SLIT"] ?? "0") ?? 0
    }()
    private let split: CGFloat = {
        CGFloat(Double(ProcessInfo.processInfo.environment["ENCLAVE_SPLIT"] ?? "0") ?? 0)
    }()
    private let glossyDisc: Bool = {
        ProcessInfo.processInfo.environment["ENCLAVE_GLOSSY_DISC"] == "1"
    }()
    private let glossyRing: Bool = {
        ProcessInfo.processInfo.environment["ENCLAVE_GLOSSY_RING"] == "1"
    }()
    private let glossyGlyph: Bool = {
        ProcessInfo.processInfo.environment["ENCLAVE_GLOSSY_GLYPH"] == "1"
    }()

    var body: some View {
        GeometryReader { geo in
            let S = min(geo.size.width, geo.size.height)
            let shape = RoundedRectangle(cornerRadius: S * 0.2237, style: .continuous)
            let tintOps: [Double] = [0.40, 0.55, 0.70]
            let paneTint: Color? = tint > 0 ? p.blooms.first?.0.opacity(tintOps[tint - 1]) : p.tint
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
                // center dim for glass disc/ring — tames bright blooms so the slit reads (ENCLAVE_DIM axis)
                if dim > 0 && (p.glyphMode == .flatGlass || p.glyphMode == .flatGlassRing) {
                    let dr:  [CGFloat] = [0.20, 0.24, 0.28]   // dim radius as fraction of S
                    let dop: [Double]  = [0.55, 0.65, 0.75]   // dim black opacity
                    RadialGradient(colors: [.black.opacity(dop[dim - 1]), .clear],
                                   center: .center, startRadius: 0, endRadius: S * dr[dim - 1])
                }

                if p.glassMode == .pane {
                    // (B) the system glass + (C) optical overlays + glyph on top
                    Rectangle()
                        .fill(.white.opacity(0.001))
                        .glassEffect(paneTint.map { p.glass.tint($0) } ?? p.glass, in: shape)
                        .overlay { if p.shimmer { opticalOverlays(shape: shape, S: S) } }
                        .overlay { markLayer(S: S) }
                } else {
                    // lens mode: no pane; the glyph disc is the only glass element
                    if p.shimmer { opticalOverlays(shape: shape, S: S) }
                    markLayer(S: S)
                }
            }
            .clipShape(shape)
            .frame(width: S, height: S)
            .background(LinearGradient(colors: p.backdrop, startPoint: .top, endPoint: .bottom))
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
                // glass ring annulus + split almond halves (independent glass pieces)
                if split > 0 {
                    GlassRing(innerRadius: S * 0.285, outerRadius: S * 0.355)
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular, in: GlassRing(innerRadius: S * 0.285, outerRadius: S * 0.355))
                    splitAlmondGlass()
                } else {
                    EnclaveSlit(open: 1)
                        .stroke(slitStroke(),
                                style: StrokeStyle(lineWidth: S * 0.06,
                                                    lineCap: .round, lineJoin: .round))
                }
                Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: S * 0.004)
            }
            .frame(width: S * 0.82, height: S * 0.82)
            .shadow(color: .black.opacity(0.22), radius: S * 0.010, x: 0, y: S * 0.006)
        case .flatGlassRing:
            // flat frosted-glass "disk on top of disk" ring-mold; slit etched on the inner disk
            ZStack {
                // outer frosted glass disc
                Circle()
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: .circle)
                // inner frosted glass disc on top, slightly smaller
                Circle()
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: .circle)
                    .frame(width: S * 0.66, height: S * 0.66)
                // glass ring annulus + split almond halves (independent glass pieces)
                if split > 0 {
                    GlassRing(innerRadius: S * 0.285, outerRadius: S * 0.355)
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular, in: GlassRing(innerRadius: S * 0.285, outerRadius: S * 0.355))
                    splitAlmondGlass()
                } else {
                    EnclaveSlit(open: 1)
                        .stroke(slitStroke(),
                                style: StrokeStyle(lineWidth: S * 0.06,
                                                    lineCap: .round, lineJoin: .round))
                }
                // rims for both disks
                Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: S * 0.004)
                Circle().strokeBorder(Color.white.opacity(0.55), lineWidth: S * 0.004)
                    .frame(width: S * 0.66, height: S * 0.66)
            }
            .frame(width: S * 0.82, height: S * 0.82)
            .shadow(color: .black.opacity(0.22), radius: S * 0.010, x: 0, y: S * 0.006)
        case .liquidMark:
            // iOS 26 Liquid Glass: the Enclave form (ring + almond) sculpted from the
            // same glass material as the disc. Per-element glossy ball-style overlays
            // (RadialGradient + specular from PopMakerOrbs.ball()) controlled by
            // ENCLAVE_GLOSSY_DISC / ENCLAVE_GLOSSY_RING / ENCLAVE_GLOSSY_GLYPH.
            ZStack {
                // (1) Glass disc
                Rectangle()
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: .circle)
                if glossyDisc {
                    glossyDiscOverlay(S: S)
                }
                // (2) Glass ring
                GlassRing(innerRadius: S * 0.285, outerRadius: S * 0.355)
                    .fill(.white.opacity(0.001))
                    .glassEffect(.regular, in: GlassRing(innerRadius: S * 0.285, outerRadius: S * 0.355))
                if glossyRing {
                    glossyRingOverlay(S: S)
                }
                // (3) Glass glyph (almond)
                if glossyGlyph {
                    if split > 0 {
                        splitAlmondGlossy(S: S)
                    } else {
                        glossyAlmond(S: S)
                    }
                } else if split > 0 {
                    splitAlmondGlass()
                } else {
                    EnclaveSlit(open: 1)
                        .fill(.white.opacity(0.001))
                        .glassEffect(.regular, in: EnclaveSlit(open: 1))
                }
            }
            .frame(width: S * 0.82, height: S * 0.82)
            .shadow(color: .black.opacity(0.22), radius: S * 0.010, x: 0, y: S * 0.006)
        }
    }

    // MARK: - Glossy 3D ball-style overlays (exact ball() params, semi-transparent over Liquid Glass)

    @ViewBuilder
    private func glossyDiscOverlay(S: CGFloat) -> some View {
        let size = S * 0.82
        let c = p.backdrop[0]
        Circle()
            .fill(RadialGradient(
                colors: [c.shade(1.7), c, c.shade(0.45)],
                center: UnitPoint(x: 0.36, y: 0.30),
                startRadius: size * 0.02, endRadius: size * 0.62))
            .opacity(0.7)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.12))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .offset(x: size * 0.14, y: size * 0.10)
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func glossyRingOverlay(S: CGFloat) -> some View {
        let size = S * 0.82
        let c = p.backdrop[0].shade(1.5)
        GlassRing(innerRadius: S * 0.285, outerRadius: S * 0.355)
            .fill(RadialGradient(
                colors: [c.shade(1.7), c, c.shade(0.45)],
                center: UnitPoint(x: 0.36, y: 0.30),
                startRadius: size * 0.02, endRadius: size * 0.62))
            .opacity(0.7)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.12))
                    .frame(width: size * 0.32, height: size * 0.32)
                    .offset(x: size * 0.14, y: size * 0.10)
            }
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func glossyAlmond(S: CGFloat) -> some View {
        let markSize = S * 0.82
        let gc = p.backdrop[0].shade(1.3)
        // Glass underneath
        EnclaveSlit(open: 1)
            .fill(.white.opacity(0.001))
            .glassEffect(.regular, in: EnclaveSlit(open: 1))
        // Glossy ball overlay — exact ball() params, specular clipped to almond
        EnclaveSlit(open: 1)
            .fill(RadialGradient(
                colors: [gc.shade(1.7), gc, gc.shade(0.45)],
                center: UnitPoint(x: 0.36, y: 0.30),
                startRadius: markSize * 0.02, endRadius: markSize * 0.62))
            .opacity(0.7)
            .overlay {
                Rectangle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                         center: UnitPoint(x: 0.36, y: 0.30),
                                         startRadius: 0, endRadius: markSize * 0.12))
                    .frame(width: markSize * 0.32, height: markSize * 0.32)
                    .position(x: markSize * (0.36 + 0.14), y: markSize * (0.30 + 0.10))
            }
            .clipShape(EnclaveSlit(open: 1))
            .frame(width: markSize, height: markSize)
            .shadow(color: .black.opacity(0.20), radius: S * 0.006, x: 0, y: S * 0.004)
    }

    @ViewBuilder
    private func splitAlmondGlossy(S: CGFloat) -> some View {
        let markSize = S * 0.82
        let gc = p.backdrop[0].shade(1.3)
        let grad = RadialGradient(
            colors: [gc.shade(1.7), gc, gc.shade(0.45)],
            center: UnitPoint(x: 0.36, y: 0.30),
            startRadius: markSize * 0.02, endRadius: markSize * 0.62)
        // Top half: glass + glossy overlay
        EnclaveSlit(open: 1, split: split, splitHalf: .top)
            .fill(.white.opacity(0.001))
            .glassEffect(.regular, in: EnclaveSlit(open: 1, split: split, splitHalf: .top))
        EnclaveSlit(open: 1, split: split, splitHalf: .top)
            .fill(grad)
            .opacity(0.7)
            .overlay {
                Rectangle()
                    .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                         center: UnitPoint(x: 0.36, y: 0.30),
                                         startRadius: 0, endRadius: markSize * 0.12))
                    .frame(width: markSize * 0.32, height: markSize * 0.32)
                    .position(x: markSize * (0.36 + 0.14), y: markSize * (0.30 + 0.10))
            }
            .clipShape(EnclaveSlit(open: 1, split: split, splitHalf: .top))
            .frame(width: markSize, height: markSize)
            .shadow(color: .black.opacity(0.20), radius: S * 0.006, x: 0, y: S * 0.004)
        // Bottom half: glass + glossy overlay
        EnclaveSlit(open: 1, split: split, splitHalf: .bottom)
            .fill(.white.opacity(0.001))
            .glassEffect(.regular, in: EnclaveSlit(open: 1, split: split, splitHalf: .bottom))
        EnclaveSlit(open: 1, split: split, splitHalf: .bottom)
            .fill(grad)
            .opacity(0.7)
            .frame(width: markSize, height: markSize)
            .shadow(color: .black.opacity(0.20), radius: S * 0.006, x: 0, y: S * 0.004)
    }
    @ViewBuilder
    private func splitAlmondGlass() -> some View {
        EnclaveSlit(open: 1, split: split, splitHalf: .top)
            .fill(.white.opacity(0.001))
            .glassEffect(.regular, in: EnclaveSlit(open: 1, split: split, splitHalf: .top))
        EnclaveSlit(open: 1, split: split, splitHalf: .bottom)
            .fill(.white.opacity(0.001))
            .glassEffect(.regular, in: EnclaveSlit(open: 1, split: split, splitHalf: .bottom))
    }

    private func slitStroke() -> Color {
        guard slit > 0, let c = p.blooms.first?.0 else { return .white.opacity(0.65) }
        return (Self.luminance(of: c) > 0.55 ? Color(hex: 0x141414) : .white).opacity(0.65)
    }
    private static func luminance(of color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
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
