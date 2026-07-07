#!/usr/bin/env python3
"""Generate IconView enum cases, palette branches, and grid.py families for new glass families."""

families = {
    "Pastel": [
        ("lavender", 0x2D1F3A, 0x1A1221, 0xD4B8FF, 0x9B7BFF),
        ("mint",     0x1F3A2D, 0x122116, 0xB8FFD4, 0x7BFF9B),
        ("peach",    0x3A2A1F, 0x211612, 0xFFD4B8, 0xFF9B7B),
        ("sky",      0x1F2A3A, 0x121621, 0xB8E4FF, 0x7BB8FF),
        ("lemon",    0x3A3A1F, 0x212112, 0xFFFFB8, 0xFFFF7B),
        ("rose",     0x3A1F2A, 0x211216, 0xFFB8D4, 0xFF7B9B),
        ("lilac",    0x2A1F3A, 0x161221, 0xE4B8FF, 0xB87BFF),
        ("aqua",     0x1F3A3A, 0x122121, 0xB8FFFF, 0x7BFFFF),
    ],
    "Neon": [
        ("magenta", 0x360D32, 0x170315, 0xFF00FF, 0xFF33CC),
        ("lime",    0x15360D, 0x071703, 0xCCFF00, 0x66FF00),
        ("cyan",    0x0D3636, 0x031717, 0x00FFFF, 0x33CCFF),
        ("yellow",  0x36320D, 0x171503, 0xFFFF00, 0xFFCC00),
        ("orange",  0x36250D, 0x170F03, 0xFF6600, 0xFF9900),
        ("purple",  0x210D36, 0x0D0317, 0x9900FF, 0xCC33FF),
        ("green",   0x0D3611, 0x031705, 0x00FF66, 0x33FF99),
        ("pink",    0x360D25, 0x17030F, 0xFF3399, 0xFF66B2),
    ],
    "Mono": [
        ("obsidian", 0x0A0A0A, 0x050505, 0x333333, 0x555555),
        ("charcoal", 0x1A1A1A, 0x0F0F0F, 0x555555, 0x777777),
        ("slate",    0x2A2A2A, 0x1A1A1A, 0x777777, 0x999999),
        ("silver",   0x3A3A3A, 0x252525, 0xAAAAAA, 0xCCCCCC),
        ("ivory",    0x4A4A4A, 0x353535, 0xDDDDDD, 0xF0F0F0),
        ("fog",      0x3A3A3A, 0x252525, 0xBBBBBB, 0xDDDDDD),
        ("ink",      0x050505, 0x020202, 0x222222, 0x444444),
        ("mist",     0x2A2A2A, 0x1A1A1A, 0x888888, 0xAAAAAA),
    ],
}

cases = []
palettes = []
grid_families = {}

for fam_name, colors in families.items():
    slug = fam_name.lower()
    disc_slugs = []
    ring_slugs = []
    cases.append(f"    // {fam_name} glass family — {slug}")
    for c in colors:
        name, bg1, bg2, b1, b2 = c
        case_disc = f"glass{fam_name}{name.capitalize()}"
        cases.append(f'    case {case_disc} = "glass-{slug}-{name}"')
        cases.append(f'    case {case_disc}Ring = "glass-{slug}-{name}-ring"')
        disc_slugs.append(f'"glass-{slug}-{name}"')
        ring_slugs.append(f'"glass-{slug}-{name}-ring"')
        palettes.append(f"""        case .{case_disc}:
            return .init(backdrop: [Color(hex: 0x{bg1:06X}), Color(hex: 0x{bg2:06X})],
                         blooms: [(Color(hex: 0x{b1:06X}), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x{b2:06X}), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlass,
                         ink: .white, coreShadow: 0)
        case .{case_disc}Ring:
            return .init(backdrop: [Color(hex: 0x{bg1:06X}), Color(hex: 0x{bg2:06X})],
                         blooms: [(Color(hex: 0x{b1:06X}), UnitPoint(x: 0.32, y: 0.34), 0.54),
                                  (Color(hex: 0x{b2:06X}), UnitPoint(x: 0.70, y: 0.66), 0.46)],
                         glass: .clear, tint: nil, glassMode: .pane, glyphMode: .flatGlassRing,
                         ink: .white, coreShadow: 0)""")
    grid_families[f"Glass {fam_name}"] = disc_slugs
    grid_families[f"Glass {fam_name} Ring"] = ring_slugs

print("\n".join(cases))
print("\n---PALETTES---\n")
print("\n".join(palettes))
print("\n---GRID---\n")
print("\n".join([f'    "{k}": [{', '.join(v)}],' for k, v in grid_families.items()]))
