#!/usr/bin/env python3
"""
Enclave app icon generator.

Renders the in-app LogoMark (hairline ring + sealed vertical slit) as four
light-mode etched-glass / Frutiger-Aero variants at 1024x1024, then builds a
2x2 contact sheet so the user can pick one to drop into the iOS asset catalog.

Usage:
    python3 tools/render-icons.py [--variant NAME] [--grid]

Defaults to rendering all four variants plus the grid.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ---------------------------------------------------------------------------
# Geometry & palette
# ---------------------------------------------------------------------------

SS = 3                          # supersample factor
CANVAS = 1024
W = H = CANVAS * SS
CX = CY = CANVAS // 2 * SS      # 1024 at SS=2
LOGO_BOX = 824 * SS             # square box that carries the mark

INK = (0x57, 0x52, 0x79)
GOLD = (0xEA, 0x9D, 0x34)
BG = (0xFA, 0xF4, 0xED)
BG2 = (0xFF, 0xFA, 0xF3)
BODY = (0x6E, 0x6A, 0x8A)
MUTED = (0x79, 0x75, 0x93)
GHOST = (0xB6, 0xB1, 0xC0)
LINE_FAINT = (0xF4, 0xED, 0xE8)
LINE = (0xDF, 0xDA, 0xD9)
LINE_STRONG = (0xCE, 0xCA, 0xCD)
FOAM = (0x56, 0x94, 0x9F)
IRIS = (0x90, 0x7A, 0xA9)
PINE = (0x28, 0x69, 0x83)
LOVE = (0xB4, 0x63, 0x7A)

# Ring: SwiftUI draws Circle().stroke(lineWidth: 0.075*size) on a diameter of
# 0.82*size.  In our icon box that means a stroke width of 75 px centered on a
# path of diameter 824 px, so outer = 899 px and inner = 749 px.
RING_OUTER = int(LOGO_BOX + 75 * SS)    # 899 px at SS=2
RING_INNER = int(LOGO_BOX - 75 * SS)    # 749 px at SS=2
RING_WIDTH = 75 * SS

# Slit: stroke width 60 px (0.06/0.82*824), round caps/joins.
SLIT_WIDTH = 60 * SS

VARIANTS = ["frost-clear", "gold-amber", "deep-well", "aurora-bloom", "prism-caustic", "pearl-opal"]
OUT_DIR = Path("Marketing/icon")


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def hex(c: str, alpha: float = 1.0) -> Tuple[int, int, int, int]:
    c = c.lstrip("#")
    r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    return (r, g, b, int(255 * alpha))


def rgba(rgb: Tuple[int, ...], alpha: float = 1.0) -> Tuple[int, int, int, int]:
    return (rgb[0], rgb[1], rgb[2], int(255 * alpha))


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_rgb(a: Tuple[int, int, int], b: Tuple[int, int, int], t: float) -> Tuple[int, int, int]:
    return (int(lerp(a[0], b[0], t)), int(lerp(a[1], b[1], t)), int(lerp(a[2], b[2], t)))


def cubic(p0, p1, p2, p3, n=96) -> List[Tuple[float, float]]:
    """Sample a cubic Bezier at n+1 points from t=0 to t=1."""
    pts = []
    for i in range(n + 1):
        t = i / n
        t2 = t * t
        t3 = t2 * t
        u = 1 - t
        u2 = u * u
        u3 = u2 * u
        x = u3 * p0[0] + 3 * u2 * t * p1[0] + 3 * u * t2 * p2[0] + t3 * p3[0]
        y = u3 * p0[1] + 3 * u2 * t * p1[1] + 3 * u * t2 * p2[1] + t3 * p3[1]
        pts.append((x, y))
    return pts


def mapu(ux: float, uy: float) -> Tuple[float, float]:
    """Map a unit (0..1) point into the centered LOGO_BOX."""
    return (CX + (ux - 0.5) * LOGO_BOX, CY + (uy - 0.5) * LOGO_BOX)


def new_layer() -> Image.Image:
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def downscale(img: Image.Image) -> Image.Image:
    out = img.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=0.8, percent=80, threshold=2))


def flatten(img: Image.Image, bg: Tuple[int, int, int]) -> Image.Image:
    """Alpha-composite img onto an opaque bg and return RGB."""
    base = Image.new("RGBA", img.size, bg + (255,))
    base.alpha_composite(img)
    return base.convert("RGB")


def blur(img: Image.Image, r: float) -> Image.Image:
    return img.filter(ImageFilter.GaussianBlur(radius=r))


def lgrad(size: int, stops: List[Tuple[float, Tuple[int, int, int, int]]]) -> Image.Image:
    """Vertical linear gradient (top->bottom) with color stops."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    stops = sorted(stops, key=lambda s: s[0])
    for y in range(size):
        t = y / (size - 1) if size > 1 else 0.0
        # find segment
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                seg_t = (t - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                a = stops[i][1]
                b = stops[i + 1][1]
                col = tuple(int(lerp(a[j], b[j], seg_t)) for j in range(4))
                break
        else:
            col = stops[-1][1]
        draw.line([(0, y), (size, y)], fill=col)
    return img


def rgrad(size: int, cx: float, cy: float, stops: List[Tuple[float, Tuple[int, int, int, int]]]) -> Image.Image:
    """Radial gradient from center with color stops."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    max_r = ((max(cx, size - cx)) ** 2 + (max(cy, size - cy)) ** 2) ** 0.5
    stops = sorted(stops, key=lambda s: s[0])
    for y in range(size):
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / max_r
            for i in range(len(stops) - 1):
                if stops[i][0] <= d <= stops[i + 1][0]:
                    seg_t = (d - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                    a = stops[i][1]
                    b = stops[i + 1][1]
                    col = tuple(int(lerp(a[j], b[j], seg_t)) for j in range(4))
                    break
            else:
                col = stops[-1][1]
            img.putpixel((x, y), col)
    return img


def specular(size: int, cx: float, cy: float, rx: float, ry: float, alpha: float, blur_r: float) -> Image.Image:
    """Soft blurred white ellipse on transparent."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(255, 255, 255, int(255 * alpha)))
    return img.filter(ImageFilter.GaussianBlur(radius=blur_r))


def sheen(alpha: float = 0.30, frac: float = 0.60) -> Image.Image:
    """White vertical gloss: alpha at top -> 0 over top `frac` of canvas."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    end = int(H * frac)
    for y in range(end):
        a = int(255 * alpha * (1.0 - y / end))
        layer.paste((255, 255, 255, a), (0, y, W, y + 1))
    return layer


def rim_light(inset1: int, radius1: int, width1: int, color, alpha: float, blur1: float) -> Image.Image:
    """Bright rounded-rect stroke `inset1` (1x) px from edge, blurred."""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ins, rad, wd = inset1 * SS, radius1 * SS, width1 * SS
    d.rounded_rectangle((ins, ins, W - ins, H - ins), radius=rad,
                        outline=color + (int(255 * alpha),), width=wd)
    return blur(layer, blur1 * SS)


def raised_logo(canvas: Image.Image, sh_a: int = 60, sh_off1=(4, 5), sh_blur1: float = 3, hl_a: int = 40) -> Image.Image:
    """Drop-shadow + crisp ink logo + top catch-light. Offsets are 1x px."""
    ox, oy = sh_off1[0] * SS, sh_off1[1] * SS
    shadow = draw_logo((0, 0, 0, sh_a))
    shadow = shadow.transform((W, H), Image.Transform.AFFINE, (1, 0, ox, 0, 1, oy))
    canvas.alpha_composite(blur(shadow, sh_blur1 * SS))
    canvas.alpha_composite(draw_logo())                              # crisp ink, no blur
    hl = draw_logo((255, 255, 255, hl_a))
    hl = hl.transform((W, H), Image.Transform.AFFINE, (1, 0, int(-ox * 0.5), 0, 1, int(-oy * 0.5)))
    canvas.alpha_composite(blur(hl, 4 * SS))
    return canvas


def intaglio(layer: Image.Image, strength: float = 1.0) -> Image.Image:
    """
    EtchedBG intaglio: overlay a blurred dark stroke on the upper-left inside
    edge and a blurred bright stroke on the lower-right inside edge of the
    shape.  Higher `strength` deepens the carve.
    """
    alpha = layer.split()[-1]
    offset = int(18 * strength)
    blur_r = 14 * strength
    dark_opa = int(255 * min(0.45 * strength, 0.7))
    light_opa = int(255 * min(0.65 * strength, 0.9))

    # Dark shadow on the upper-left edge.
    up_left = alpha.transform(layer.size, Image.Transform.AFFINE, (1, 0, offset, 0, 1, offset))
    up_left = up_left.filter(ImageFilter.GaussianBlur(radius=blur_r))
    dark = Image.new("RGBA", layer.size, (0, 0, 0, dark_opa))
    dark.putalpha(up_left)

    # Light highlight on the lower-right edge.
    down_right = alpha.transform(layer.size, Image.Transform.AFFINE, (1, 0, -offset, 0, 1, -offset))
    down_right = down_right.filter(ImageFilter.GaussianBlur(radius=blur_r))
    light = Image.new("RGBA", layer.size, (255, 255, 255, light_opa))
    light.putalpha(down_right)

    out = layer.copy()
    out.alpha_composite(dark)
    out.alpha_composite(light)
    return out


# ---------------------------------------------------------------------------
# Logo mark
# ---------------------------------------------------------------------------

def draw_logo(ink: Tuple[int, int, int, int] = INK + (255,)) -> Image.Image:
    """Render the ring + sealed slit mark on a transparent layer."""
    layer = new_layer()
    draw = ImageDraw.Draw(layer)

    # Ring as a filled ring (matches SwiftUI stroke width centred on diameter).
    draw.ellipse(
        (CX - RING_OUTER // 2, CY - RING_OUTER // 2, CX + RING_OUTER // 2, CY + RING_OUTER // 2),
        fill=ink,
    )
    draw.ellipse(
        (CX - RING_INNER // 2, CY - RING_INNER // 2, CX + RING_INNER // 2, CY + RING_INNER // 2),
        fill=(0, 0, 0, 0),
    )

    # Slit geometry: an open almond-shaped stroke sealed by a horizontal bar.
    b = 0.09
    s = 0.055
    # Outer almond: two cubic curves forming a closed lens.
    p0 = mapu(0.50, 0.28)
    p1 = mapu(0.50 - b, 0.40)
    p2 = mapu(0.50 - b, 0.60)
    p3 = mapu(0.50, 0.72)
    p4 = mapu(0.50 + b, 0.60)
    p5 = mapu(0.50 + b, 0.40)
    almond = cubic(p0, p1, p2, p3, n=96) + cubic(p3, p4, p5, p0, n=96)
    draw.line(almond, fill=ink, width=SLIT_WIDTH, joint="curve")

    # Seal: horizontal line across the centre of the transparent slit.
    seal_a = mapu(0.50 - s, 0.50)
    seal_b = mapu(0.50 + s, 0.50)
    draw.line([seal_a, seal_b], fill=ink, width=SLIT_WIDTH, joint="curve")

    return layer


# ---------------------------------------------------------------------------
# Variants
# ---------------------------------------------------------------------------

def render_frost_clear() -> Image.Image:
    """Clear neutral Liquid Glass baseline."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    canvas.alpha_composite(lgrad(H, [(0, BG2 + (255,)), (1, BG + (255,))]))
    canvas.alpha_composite(sheen(0.30, 0.60))
    canvas.alpha_composite(specular(W, CX - W * 0.20, CY - H * 0.22, W * 0.24, H * 0.16, 0.32, 35 * SS))  # dome
    canvas.alpha_composite(specular(W, CX - W * 0.06, CY - H * 0.30, W * 0.05, H * 0.03, 0.55, 8 * SS))   # pinpoint
    canvas.alpha_composite(rim_light(28, 210, 10, (255, 255, 255), 0.40, 5))
    raised_logo(canvas)
    return downscale(canvas)


def render_gold_amber() -> Image.Image:
    """Warm gold-tinted glass with a gold rim behind the ring."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    canvas.alpha_composite(lgrad(H, [(0, (0xFF, 0xFA, 0xF3, 255)), (0.5, (0xFB, 0xF0, 0xDC, 255)), (1, (0xF6, 0xE7, 0xC8, 255))]))
    canvas.alpha_composite(sheen(0.26, 0.60))
    canvas.alpha_composite(specular(W, CX - W * 0.20, CY - H * 0.22, W * 0.24, H * 0.16, 0.40, 35 * SS))
    canvas.alpha_composite(specular(W, CX - W * 0.06, CY - H * 0.30, W * 0.05, H * 0.03, 0.55, 8 * SS))
    canvas.alpha_composite(rim_light(28, 210, 10, GOLD, 0.45, 5))
    gr = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gr)
    gd.ellipse(
        (CX - RING_OUTER // 2 - 6 * SS, CY - RING_OUTER // 2 - 6 * SS, CX + RING_OUTER // 2 + 6 * SS, CY + RING_OUTER // 2 + 6 * SS),
        outline=GOLD + (int(255 * 0.55),),
        width=10 * SS,
    )
    canvas.alpha_composite(blur(gr, 6 * SS))
    raised_logo(canvas)
    return downscale(canvas)


def render_deep_well() -> Image.Image:
    """Deeply recessed carved crystal with a bright outer bevel and dark well."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    canvas.alpha_composite(lgrad(H, [(0, BG2 + (255,)), (1, BG + (255,))]))
    canvas.alpha_composite(sheen(0.22, 0.55))
    canvas.alpha_composite(rim_light(24, 215, 14, (255, 255, 255), 0.55, 3))   # bright outer bevel
    canvas.alpha_composite(rim_light(44, 196, 8, (0, 0, 0), 0.16, 5))          # soft inner recess
    well = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(well)
    wd.ellipse(
        (CX - RING_OUTER // 2 - 50 * SS, CY - RING_OUTER // 2 - 50 * SS, CX + RING_OUTER // 2 + 50 * SS, CY + RING_OUTER // 2 + 50 * SS),
        fill=(0, 0, 0, int(255 * 0.10)),
    )
    canvas.alpha_composite(blur(well, 70 * SS))                               # lensing-dark well
    canvas.alpha_composite(specular(W, CX - W * 0.20, CY - H * 0.22, W * 0.24, H * 0.16, 0.28, 35 * SS))  # dome
    canvas.alpha_composite(specular(W, CX - W * 0.06, CY - H * 0.30, W * 0.05, H * 0.03, 0.50, 8 * SS))   # pinpoint
    raised_logo(canvas, sh_a=85, sh_off1=(5, 7), sh_blur1=5)
    return downscale(canvas)


def render_aurora_bloom() -> Image.Image:
    """Dawn-tinted glossy glass with foam/iris/rose blooms and micro-sparkle."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    canvas.alpha_composite(lgrad(H, [(0, (0xFF, 0xF5, 0xED, 255)), (0.5, (0xFF, 0xFA, 0xF3, 255)), (1, (0xFA, 0xF4, 0xED, 255))]))
    b1 = specular(W, CX - LOGO_BOX * 0.40, CY - LOGO_BOX * 0.30, LOGO_BOX * 0.55, LOGO_BOX * 0.45, 0.26, 50 * SS)
    b1 = Image.blend(b1, Image.new("RGBA", (W, H), FOAM + (255,)), 0.50)
    canvas.alpha_composite(b1)
    b2 = specular(W, CX + LOGO_BOX * 0.35, CY + LOGO_BOX * 0.25, LOGO_BOX * 0.50, LOGO_BOX * 0.40, 0.26, 48 * SS)
    b2 = Image.blend(b2, Image.new("RGBA", (W, H), IRIS + (255,)), 0.50)
    canvas.alpha_composite(b2)
    b3 = specular(W, CX - LOGO_BOX * 0.05, CY - LOGO_BOX * 0.45, LOGO_BOX * 0.45, LOGO_BOX * 0.35, 0.22, 42 * SS)
    b3 = Image.blend(b3, Image.new("RGBA", (W, H), LOVE + (255,)), 0.45)
    canvas.alpha_composite(b3)
    canvas.alpha_composite(sheen(0.32, 0.60))
    canvas.alpha_composite(specular(W, CX - W * 0.20, CY - H * 0.22, W * 0.24, H * 0.16, 0.40, 35 * SS))
    canvas.alpha_composite(specular(W, CX - W * 0.06, CY - H * 0.30, W * 0.05, H * 0.03, 0.55, 8 * SS))
    canvas.alpha_composite(rim_light(28, 210, 10, (255, 255, 255), 0.38, 5))
    raised_logo(canvas)
    rng = __import__("random").Random(42)
    sp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sp)
    for _ in range(140):
        sx, sy = rng.randint(0, W - 1), rng.randint(0, H - 1)
        if ((sx - CX) ** 2 + (sy - CY) ** 2) ** 0.5 < LOGO_BOX * 0.6:
            continue
        rr = rng.choice([2, 3, 4])
        c = rng.choice([GOLD, FOAM, IRIS, LOVE])
        sd.ellipse((sx - rr, sy - rr, sx + rr, sy + rr), fill=c + (int(255 * 0.9),))
    canvas.alpha_composite(blur(sp, 1.5 * SS))
    return downscale(canvas)


def render_prism_caustic() -> Image.Image:
    """Refractive jewel with chromatic rim and caustic light streaks."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    canvas.alpha_composite(lgrad(H, [(0, BG2 + (255,)), (1, BG + (255,))]))
    canvas.alpha_composite(sheen(0.30, 0.60))
    canvas.alpha_composite(rim_light(22, 216, 10, GOLD, 0.65, 3))
    canvas.alpha_composite(rim_light(28, 210, 10, FOAM, 0.55, 3))
    canvas.alpha_composite(rim_light(34, 204, 10, IRIS, 0.55, 3))
    canvas.alpha_composite(rim_light(40, 198, 8, (255, 255, 255), 0.35, 3))
    canvas.alpha_composite(specular(W, CX - W * 0.22, CY - H * 0.24, W * 0.10, H * 0.07, 0.45, 15 * SS))  # facet spec
    canvas.alpha_composite(specular(W, CX + W * 0.18, CY + H * 0.20, W * 0.08, H * 0.06, 0.30, 12 * SS))
    streak = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    st = ImageDraw.Draw(streak)
    st.line(
        [(CX - W * 0.35, CY + H * 0.10), (CX + W * 0.35, CY - H * 0.10)],
        fill=(255, 255, 255, int(255 * 0.60)),
        width=7 * SS,
    )
    canvas.alpha_composite(blur(streak, 4 * SS))
    raised_logo(canvas)
    return downscale(canvas)


def render_pearl_opal() -> Image.Image:
    """Milky iridescent opal glass with soft color blooms."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))
    canvas.alpha_composite(lgrad(H, [(0, (0xFF, 0xFB, 0xF6, 255)), (1, (0xF8, 0xF2, 0xEC, 255))]))
    for col, bx, by in [
        (GOLD, CX - LOGO_BOX * 0.30, CY - LOGO_BOX * 0.25),
        (FOAM, CX + LOGO_BOX * 0.28, CY - LOGO_BOX * 0.20),
        (IRIS, CX - LOGO_BOX * 0.15, CY + LOGO_BOX * 0.30),
        (LOVE, CX + LOGO_BOX * 0.25, CY + LOGO_BOX * 0.28),
    ]:
        b = specular(W, bx, by, LOGO_BOX * 0.45, LOGO_BOX * 0.40, 0.14, 45 * SS)
        b = Image.blend(b, Image.new("RGBA", (W, H), col + (255,)), 0.40)
        canvas.alpha_composite(b)
    canvas.alpha_composite(sheen(0.38, 0.62))
    canvas.alpha_composite(specular(W, CX - W * 0.20, CY - H * 0.22, W * 0.24, H * 0.16, 0.30, 35 * SS))
    canvas.alpha_composite(rim_light(28, 210, 8, (255, 255, 255), 0.42, 5))
    raised_logo(canvas)
    return downscale(canvas)


# ---------------------------------------------------------------------------
# Grid / contact sheet
# ---------------------------------------------------------------------------

def make_grid(out_dir: Path) -> Path:
    """Build a contact sheet with filename labels."""
    grid_path = out_dir / "icon-grid.png"
    cols = (len(VARIANTS) + 1) // 2
    rows = (len(VARIANTS) + cols - 1) // cols

    # Try ImageMagick montage first.
    magick = shutil.which("magick")
    if magick:
        files = [str(out_dir / f"enclave-icon-{v}-1024.png") for v in VARIANTS]
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
            return grid_path
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
        img = Image.open(out_dir / f"enclave-icon-{v}-1024.png").convert("RGBA")
        img = img.resize((thumb, thumb), Image.Resampling.LANCZOS)
        x = pad + (i % cols) * (thumb + pad)
        y = pad + (i // cols) * (thumb + pad)
        grid.paste(img, (x, y))
        label = f"enclave-icon-{v}-1024"
        bbox = gd.textbbox((0, 0), label, font=font)
        lw = bbox[2] - bbox[0]
        gd.text((x + (thumb - lw) // 2, y + thumb + 4), label, fill=INK, font=font)

    grid.convert("RGB").save(grid_path)
    return grid_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Render Enclave app icon variants.")
    parser.add_argument("--variant", choices=VARIANTS + ["all"], default="all")
    parser.add_argument("--grid", action="store_true", help="Build contact sheet after rendering")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    renderers = {
        "frost-clear": render_frost_clear,
        "gold-amber": render_gold_amber,
        "deep-well": render_deep_well,
        "aurora-bloom": render_aurora_bloom,
        "prism-caustic": render_prism_caustic,
        "pearl-opal": render_pearl_opal,
    }

    variants = VARIANTS if args.variant == "all" else [args.variant]

    paths = []
    for v in variants:
        img = renderers[v]()
        path = OUT_DIR / f"enclave-icon-{v}-1024.png"
        flatten(img, BG).save(path, "PNG")
        paths.append(path)
        print(path)

    if args.variant == "all":
        # Default behavior for 'all' is to also build the grid.
        grid_path = make_grid(OUT_DIR)
        print(grid_path)

    return 0


if __name__ == "__main__":
    sys.exit(main())
