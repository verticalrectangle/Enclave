#!/usr/bin/env python3
"""Flatten captured Liquid Glass tiles to opaque sRGB and build a family-grouped contact sheet."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import os, shutil, subprocess, sys

OUT_DIR = Path("Marketing/icon")
BG = (0xFA, 0xF4, 0xED)
INK = (0x57, 0x52, 0x79)
# family label → variant slugs (order = sheet order). Tiles not listed land in "More".
FAMILIES = {
    "Aurora":      ["aurora-bloom", "aurora-dusk", "aurora-veil", "aurora-prism"],
    "Jewel":       ["sapphire-glass", "emerald-glass", "amethyst-glass", "topaz-glass", "ruby-glass"],
    "Midnight":    ["obsidian", "midnight-bloom", "deep-well"],
    "Frost / light": ["frost-clear", "pearl-opal", "liquid-aero"],
    "Warm":        ["gold-amber"],
    "Copper":      ["copper-bloom", "copper-veil", "copper-lens", "copper-ember",
                    "copper-gold", "copper-rose", "copper-prism", "copper-deep", "copper-glow", "copper-frost"],
    "Lens":        ["prism-caustic", "gem-cut"],
    "Glass":       ["glass-crimson", "glass-coral", "glass-tangerine", "glass-amber", "glass-honey",
                    "glass-citron", "glass-lime", "glass-jade", "glass-mint", "glass-aqua",
                    "glass-cyan", "glass-sky", "glass-azure", "glass-cobalt", "glass-indigo",
                    "glass-violet", "glass-orchid", "glass-magenta", "glass-rose", "glass-blush"],
    "Glass Ring":  ["glass-ring-crimson", "glass-ring-coral", "glass-ring-tangerine", "glass-ring-amber", "glass-ring-honey",
                    "glass-ring-citron", "glass-ring-lime", "glass-ring-jade", "glass-ring-mint", "glass-ring-aqua",
                    "glass-ring-cyan", "glass-ring-sky", "glass-ring-azure", "glass-ring-cobalt", "glass-ring-indigo",
                    "glass-ring-violet", "glass-ring-orchid", "glass-ring-magenta", "glass-ring-rose", "glass-ring-blush"],
    "Glass · Copper": ["copper-glow-disc", "copper-glow-ring"],
    "Glass Pastel": ["glass-pastel-lavender", "glass-pastel-mint", "glass-pastel-peach", "glass-pastel-sky", "glass-pastel-lemon", "glass-pastel-rose", "glass-pastel-lilac", "glass-pastel-aqua"],
    "Glass Pastel Ring": ["glass-pastel-lavender-ring", "glass-pastel-mint-ring", "glass-pastel-peach-ring", "glass-pastel-sky-ring", "glass-pastel-lemon-ring", "glass-pastel-rose-ring", "glass-pastel-lilac-ring", "glass-pastel-aqua-ring"],
    "Glass Neon": ["glass-neon-magenta", "glass-neon-lime", "glass-neon-cyan", "glass-neon-yellow", "glass-neon-orange", "glass-neon-purple", "glass-neon-green", "glass-neon-pink"],
    "Glass Neon Ring": ["glass-neon-magenta-ring", "glass-neon-lime-ring", "glass-neon-cyan-ring", "glass-neon-yellow-ring", "glass-neon-orange-ring", "glass-neon-purple-ring", "glass-neon-green-ring", "glass-neon-pink-ring"],
    "Glass Mono": ["glass-mono-obsidian", "glass-mono-charcoal", "glass-mono-slate", "glass-mono-silver", "glass-mono-ivory", "glass-mono-fog", "glass-mono-ink", "glass-mono-mist"],
    "Glass Mono Ring": ["glass-mono-obsidian-ring", "glass-mono-charcoal-ring", "glass-mono-slate-ring", "glass-mono-silver-ring", "glass-mono-ivory-ring", "glass-mono-fog-ring", "glass-mono-ink-ring", "glass-mono-mist-ring"],
}


def main() -> int:
    for p in sorted(OUT_DIR.glob("enclave-icon-*-1024.png")):
        Image.open(p).convert("RGB").save(p, format="PNG")   # flatten alpha → opaque app-icon
    _make_grid()
    return 0


def _ordered() -> list[str]:
    listed = [v for vs in FAMILIES.values() for v in vs]
    extra = [p.name[len("enclave-icon-"):-len("-1024.png")]
             for p in sorted(OUT_DIR.glob("enclave-icon-*-1024.png"))]
    return listed + [v for v in extra if v not in listed]


def _make_grid() -> None:
    grid_path = OUT_DIR / "icon-grid.png"
    variants = _ordered()
    thumb, pad, label_h = 512, 16, 28
    cols = 5
    rows = (len(variants) + cols - 1) // cols
    grid_w = thumb * cols + pad * (cols + 1)
    grid_h = thumb * rows + pad * (rows + 1) + label_h * rows
    grid = Image.new("RGB", (grid_w, grid_h), BG)
    gd = ImageDraw.Draw(grid)
    font = None
    for fp in ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
               "/usr/share/fonts/TTF/DejaVuSans.ttf",
               "/usr/share/fonts/dejavu/DejaVuSans.ttf"]:
        if os.path.exists(fp):
            font = ImageFont.truetype(fp, 24); break
    font = font or ImageFont.load_default()
    for i, v in enumerate(variants):
        src = OUT_DIR / f"enclave-icon-{v}-1024.png"
        if not src.exists(): continue
        img = Image.open(src).convert("RGB").resize((thumb, thumb), Image.Resampling.LANCZOS)
        x = pad + (i % cols) * (thumb + pad)
        y = pad + (i // cols) * (thumb + pad + label_h)
        grid.paste(img, (x, y))
        fam = next((k for k, vs in FAMILIES.items() if v in vs), "More")
        label = f"{fam} · {v}"
        bbox = gd.textbbox((0, 0), label, font=font)
        gd.text((x + (thumb - (bbox[2] - bbox[0])) // 2, y + thumb + 4), label, fill=INK, font=font)
    grid.save(grid_path)


if __name__ == "__main__":
    sys.exit(main())
