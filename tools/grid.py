#!/usr/bin/env python3
"""Flatten the 6 captured Liquid Glass tiles to opaque sRGB and build icon-grid.png."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import os, shutil, subprocess, sys

VARIANTS = ["frost-clear", "gold-amber", "deep-well", "aurora-bloom", "prism-caustic", "pearl-opal"]
OUT_DIR = Path("Marketing/icon")

BG = (0xFA, 0xF4, 0xED)
INK = (0x57, 0x52, 0x79)


def main() -> int:
    for v in VARIANTS:
        p = OUT_DIR / f"enclave-icon-{v}-1024.png"
        im = Image.open(p).convert("RGB")          # flatten alpha → opaque app-icon
        im.save(p, format="PNG")
    _make_grid()
    return 0


def _make_grid() -> None:
    """Build a contact sheet with filename labels."""
    grid_path = OUT_DIR / "icon-grid.png"
    cols = (len(VARIANTS) + 1) // 2
    rows = (len(VARIANTS) + cols - 1) // cols

    # Try ImageMagick montage first.
    magick = shutil.which("magick")
    if magick:
        files = [str(OUT_DIR / f"enclave-icon-{v}-1024.png") for v in VARIANTS]
        cmd = [
            magick, "montage",
        ] + files + [
            "-tile", f"{cols}x{rows}",
            "-geometry", "512x512+16+16",
            "-background", "#FAF4ED",
            "-fill", "#575279",
            "-pointsize", "28",
            "-label", "%t",
            str(grid_path),
        ]
        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            return
        except subprocess.CalledProcessError as e:
            print(f"magick montage failed: {e.stderr}", file=sys.stderr)

    # Pillow fallback.
    thumb = 512
    pad = 16
    grid_w = thumb * cols + pad * (cols + 1)
    grid_h = thumb * rows + pad * (rows + 1) + 28 * rows
    grid = Image.new("RGBA", (grid_w, grid_h), BG + (255,))
    gd = ImageDraw.Draw(grid)

    font = None
    font_paths = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/dejavu/DejaVuSans.ttf",
    ]
    for fp in font_paths:
        if os.path.exists(fp):
            font = ImageFont.truetype(fp, 28)
            break
    if font is None:
        font = ImageFont.load_default()

    for i, v in enumerate(VARIANTS):
        img = Image.open(OUT_DIR / f"enclave-icon-{v}-1024.png").convert("RGBA")
        img = img.resize((thumb, thumb), Image.Resampling.LANCZOS)
        x = pad + (i % cols) * (thumb + pad)
        y = pad + (i // cols) * (thumb + pad)
        grid.paste(img, (x, y))
        label = f"enclave-icon-{v}-1024"
        bbox = gd.textbbox((0, 0), label, font=font)
        lw = bbox[2] - bbox[0]
        gd.text((x + (thumb - lw) // 2, y + thumb + 4), label, fill=INK, font=font)

    grid.convert("RGB").save(grid_path)


if __name__ == "__main__":
    sys.exit(main())
