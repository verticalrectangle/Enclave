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

SS = 2                          # supersample factor
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

VARIANTS = ["etched-frost", "liquid-aero", "aurora-dawn", "gem-cut"]
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
    return img.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)


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

    # Slit geometry.
    b = 0.09
    s = 0.055
    # Almond: two cubic curves forming a closed lens.
    p0 = mapu(0.50, 0.28)
    p1 = mapu(0.50 - b, 0.40)
    p2 = mapu(0.50 - b, 0.60)
    p3 = mapu(0.50, 0.72)
    p4 = mapu(0.50 + b, 0.60)
    p5 = mapu(0.50 + b, 0.40)
    almond = cubic(p0, p1, p2, p3, n=96) + cubic(p3, p4, p5, p0, n=96)
    draw.polygon(almond, fill=ink)

    # Seal: horizontal line across the centre.
    seal_a = mapu(0.50 - s, 0.50)
    seal_b = mapu(0.50 + s, 0.50)
    draw.line([seal_a, seal_b], fill=ink, width=SLIT_WIDTH, joint="curve")

    return layer


# ---------------------------------------------------------------------------
# Variants
# ---------------------------------------------------------------------------

def render_etched_frost() -> Image.Image:
    """Restrained etched-glass baseline: the logo die-stamped into frosted glass."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))

    # Ground vertical gradient bg2 -> bg.
    grad = lgrad(H, [(0, BG2 + (255,)), (1, BG + (255,))])
    canvas.alpha_composite(grad)

    # Frosted-glass noise: very subtle low-contrast grain.
    rng = __import__("random").Random(7)
    noise = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    nd = ImageDraw.Draw(noise)
    for _ in range(8000):
        x = rng.randint(0, W - 1)
        y = rng.randint(0, H - 1)
        v = rng.randint(-8, 8)
        base = 0xFA + v
        nd.point((x, y), fill=(base, base, base, 25))
    noise = blur(noise, 0.8)
    canvas.alpha_composite(noise)

    # Soft top sheen: white 0.55 -> 0 over top half.
    sheen = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y in range(H // 2):
        a = int(255 * 0.55 * (1 - y / (H // 2)))
        sheen.paste((255, 255, 255, a), (0, y, W, y + 1))
    canvas.alpha_composite(sheen)

    # Subtle frosted vignette.
    vig = rgrad(W, CX, CY, [(0, (255, 255, 255, 0)), (0.75, (255, 255, 255, 0)), (1, (255, 255, 255, 70))])
    canvas.alpha_composite(vig)

    # Logo stamped into the glass via intaglio.
    logo = draw_logo()
    logo = intaglio(logo, strength=1.4)
    canvas.alpha_composite(logo)

    return downscale(canvas)


def render_liquid_aero() -> Image.Image:
    """Wet glossy Frutiger-Aero: translucent disk, Aero orb, gold rim-light."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))

    # Ground radial frost: bg2 centre -> warm gold-tinted edge.
    bg = rgrad(W, CX, CY, [(0, BG2 + (255,)), (0.85, (0xF8, 0xE9, 0xD4, 255)), (1, (0xF2, 0xDF, 0xC2, 255))])
    canvas.alpha_composite(bg)

    # Translucent glass disk behind the logo.
    disk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disk)
    disk_r = int(LOGO_BOX * 1.05)
    # Convex top-white -> bottom-dark gradient for the disk.
    disk_grad = lgrad(disk_r * 2, [(0, (255, 255, 255, 70)), (0.5, (255, 255, 255, 35)), (1, (0, 0, 0, 25))])
    disk.paste(disk_grad, (CX - disk_r, CY - disk_r))
    # Mask to circle.
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse((CX - disk_r, CY - disk_r, CX + disk_r, CY + disk_r), fill=255)
    disk.putalpha(mask)
    canvas.alpha_composite(disk)

    # Bottom contact shadow for the disk.
    shadow = specular(W, CX, CY + LOGO_BOX * 0.55, LOGO_BOX * 0.55, LOGO_BOX * 0.12, 0.18, 35)
    canvas.alpha_composite(shadow)

    # Gold rim-light: thin concentric circle stroke just behind the ring.
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.ellipse(
        (CX - RING_OUTER // 2 - 4, CY - RING_OUTER // 2 - 4, CX + RING_OUTER // 2 + 4, CY + RING_OUTER // 2 + 4),
        outline=GOLD + (int(255 * 0.7),),
        width=8,
    )
    rim = blur(rim, 3)
    canvas.alpha_composite(rim)

    # Logo ink.
    logo = draw_logo()
    canvas.alpha_composite(logo)

    # Big Aero specular (top-left, ~26% of canvas).
    orb = specular(W, CX - W * 0.22, CY - H * 0.22, W * 0.26, H * 0.18, 0.45, 70)
    canvas.alpha_composite(orb)

    # Pinpoint secondary specular.
    pin = specular(W, CX - W * 0.08, CY - H * 0.30, W * 0.06, H * 0.04, 0.65, 18)
    canvas.alpha_composite(pin)

    return downscale(canvas)


def render_aurora_dawn() -> Image.Image:
    """Dreamy dawn wash with gold/foam/iris blooms and micro-sparkle."""
    canvas = Image.new("RGBA", (W, H), BG + (255,))

    # Diagonal wash: smooth bg -> warm corner via a 1D gradient mapped by (x+y).
    wash_grad = []
    n = W + H
    for i in range(n + 1):
        t = i / n
        # Base warm shift.
        r = int(lerp(0xFA, 0xF8, t))
        g = int(lerp(0xF4, 0xE5, t))
        b = int(lerp(0xED, 0xC4, t))
        # Faint gold band in the middle.
        gold_t = max(0.0, 1.0 - abs(t - 0.5) * 5.0) * 0.12
        r = int(lerp(r, 0xEA, gold_t))
        g = int(lerp(g, 0x9D, gold_t))
        b = int(lerp(b, 0x34, gold_t))
        wash_grad.append((r, g, b, 255))
    wash = Image.new("RGBA", (W, H))
    for y in range(H):
        for x in range(W):
            wash.putpixel((x, y), wash_grad[x + y])
    canvas.alpha_composite(wash)

    # Soft translucent frosted disk behind the logo.
    disk = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(disk)
    disk_r = int(LOGO_BOX * 1.08)
    disk_grad = lgrad(disk_r * 2, [(0, (255, 255, 255, 60)), (0.5, (255, 255, 255, 30)), (1, (255, 255, 255, 10))])
    disk.paste(disk_grad, (CX - disk_r, CY - disk_r))
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.ellipse((CX - disk_r, CY - disk_r, CX + disk_r, CY + disk_r), fill=255)
    disk.putalpha(mask)
    canvas.alpha_composite(disk)

    # Soft foam/iris blooms (large, airy light leaks).
    bloom1 = specular(W, CX - LOGO_BOX * 0.40, CY - LOGO_BOX * 0.30, LOGO_BOX * 0.55, LOGO_BOX * 0.45, 0.14, 120)
    bloom1 = Image.blend(bloom1, Image.new("RGBA", (W, H), FOAM + (255,)), 0.35)
    canvas.alpha_composite(bloom1)

    bloom2 = specular(W, CX + LOGO_BOX * 0.35, CY + LOGO_BOX * 0.25, LOGO_BOX * 0.50, LOGO_BOX * 0.40, 0.14, 115)
    bloom2 = Image.blend(bloom2, Image.new("RGBA", (W, H), IRIS + (255,)), 0.35)
    canvas.alpha_composite(bloom2)

    bloom3 = specular(W, CX + LOGO_BOX * 0.15, CY - LOGO_BOX * 0.45, LOGO_BOX * 0.40, LOGO_BOX * 0.30, 0.10, 100)
    bloom3 = Image.blend(bloom3, Image.new("RGBA", (W, H), GOLD + (255,)), 0.25)
    canvas.alpha_composite(bloom3)

    # Gold inner glow behind the ring.
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse(
        (CX - RING_OUTER // 2 - 20, CY - RING_OUTER // 2 - 20, CX + RING_OUTER // 2 + 20, CY + RING_OUTER // 2 + 20),
        outline=GOLD + (int(255 * 0.45),),
        width=28,
    )
    glow = blur(glow, 20)
    canvas.alpha_composite(glow)

    # Logo ink.
    logo = draw_logo()
    canvas.alpha_composite(logo)

    # Soft top sheen.
    sheen = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for y in range(H // 2):
        a = int(255 * 0.35 * (1 - y / (H // 2)))
        sheen.paste((255, 255, 255, a), (0, y, W, y + 1))
    canvas.alpha_composite(sheen)

    # Micro-sparkle dots.
    rng = __import__("random").Random(42)
    spark = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(spark)
    for _ in range(60):
        sx = rng.randint(0, W - 1)
        sy = rng.randint(0, H - 1)
        if ((sx - CX) ** 2 + (sy - CY) ** 2) ** 0.5 < LOGO_BOX * 0.65:
            continue
        r = rng.choice([2, 3])
        col = rng.choice([GOLD, FOAM, IRIS])
        sd.ellipse((sx - r, sy - r, sx + r, sy + r), fill=col + (int(255 * 0.6),))
    spark = blur(spark, 2)
    canvas.alpha_composite(spark)

    return downscale(canvas)


def render_gem_cut() -> Image.Image:
    """Crystal / faceted disk with sharp seams, bright highlights, and a carved well."""
    canvas = Image.new("RGBA", (W, H), BG2 + (255,))

    # Facet background: 8 radial slices with alternating warm/cool crystal tints.
    n_facets = 8
    base_tints = [
        (0xFF, 0xFA, 0xF3), (0xF4, 0xED, 0xE8), (0xFF, 0xFA, 0xF3), (0xF6, 0xEE, 0xE4),
        (0xFA, 0xF4, 0xED), (0xF4, 0xED, 0xE8), (0xFF, 0xFA, 0xF3), (0xF9, 0xF2, 0xE9),
    ]
    for i in range(n_facets):
        a0 = i * 360 / n_facets
        a1 = (i + 1) * 360 / n_facets
        poly = [(CX, CY)]
        for step in range(0, 21):
            a = a0 + (a1 - a0) * step / 20
            rad = W * 0.8
            x = CX + rad * __import__("math").cos(__import__("math").radians(a))
            y = CY + rad * __import__("math").sin(__import__("math").radians(a))
            poly.append((x, y))
        d = ImageDraw.Draw(canvas)
        d.polygon(poly, fill=base_tints[i])

    # Sharp crystalline seams: bright top edge + dark bottom edge.
    seams = new_layer()
    sd = ImageDraw.Draw(seams)
    for i in range(n_facets):
        a = i * 360 / n_facets
        rad = W * 0.8
        x = CX + rad * __import__("math").cos(__import__("math").radians(a))
        y = CY + rad * __import__("math").sin(__import__("math").radians(a))
        # Dark seam.
        sd.line([(CX, CY), (x, y)], fill=(0, 0, 0, 55), width=8)
        # Bright highlight slightly offset.
        hx = CX + 5 * __import__("math").cos(__import__("math").radians(a + 90))
        hy = CY + 5 * __import__("math").sin(__import__("math").radians(a + 90))
        sd.line([(hx, hy), (x + hx - CX, y + hy - CY)], fill=(255, 255, 255, 120), width=5)
    seams = blur(seams, 3)
    canvas.alpha_composite(seams)

    # Carved well: radial dark gradient behind the ring, lighter at center.
    well = rgrad(W, CX, CY, [(0, (255, 255, 255, 30)), (0.45, (0, 0, 0, 0)), (0.75, (0, 0, 0, 50)), (1, (0, 0, 0, 90))])
    canvas.alpha_composite(well)

    # Drop shadow for the logo so it sits in the well.
    shadow = draw_logo((0, 0, 0, int(255 * 0.25)))
    shadow = shadow.transform((W, H), Image.Transform.AFFINE, (1, 0, 12, 0, 1, 12))
    shadow = blur(shadow, 12)
    canvas.alpha_composite(shadow)

    # Gold refraction line along the lower-right ring.
    refract = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(refract)
    rd.arc(
        (CX - RING_OUTER // 2 - 2, CY - RING_OUTER // 2 - 2, CX + RING_OUTER // 2 + 2, CY + RING_OUTER // 2 + 2),
        start=-50,
        end=40,
        fill=GOLD + (int(255 * 0.85),),
        width=12,
    )
    refract = blur(refract, 5)
    canvas.alpha_composite(refract)

    # Logo ink on top of the refraction.
    logo = draw_logo()
    canvas.alpha_composite(logo)

    return downscale(canvas)


# ---------------------------------------------------------------------------
# Grid / contact sheet
# ---------------------------------------------------------------------------

def make_grid(out_dir: Path) -> Path:
    """Build a 2x2 contact sheet with filename labels."""
    grid_path = out_dir / "icon-grid.png"

    # Try ImageMagick montage first.
    magick = shutil.which("magick")
    if magick:
        files = [str(out_dir / f"enclave-icon-{v}-1024.png") for v in VARIANTS]
        cmd = [
            magick, "montage",
        ] + files + [
            "-tile", "2x2",
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
    grid_w = grid_h = thumb * 2 + pad * 3
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
        x = pad + (i % 2) * (thumb + pad)
        y = pad + (i // 2) * (thumb + pad)
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
        "etched-frost": render_etched_frost,
        "liquid-aero": render_liquid_aero,
        "aurora-dawn": render_aurora_dawn,
        "gem-cut": render_gem_cut,
    }

    variants = VARIANTS if args.variant == "all" else [args.variant]

    paths = []
    for v in variants:
        img = renderers[v]()
        path = OUT_DIR / f"enclave-icon-{v}-1024.png"
        flatten(img, BG).save(path, "PNG")
        paths.append(path)
        print(path)

    if (args.variant == "all" and args.grid) or (args.variant == "all" and not args.grid):
        # Default behavior for 'all' is to also build the grid.
        grid_path = make_grid(OUT_DIR)
        print(grid_path)

    return 0


if __name__ == "__main__":
    sys.exit(main())
