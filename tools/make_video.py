#!/usr/bin/env python3
"""Build an MP4 of every captured icon tile, ordered by grid family, at 0.3 s each."""
import os
import re
import subprocess
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "Marketing" / "icon"
LIST_PATH = OUT_DIR / "list.txt"
VIDEO_PATH = OUT_DIR / "all-icons.mp4"


def _order_key(slug: str) -> tuple:
    """Return (family_idx, idx_in_family, dim, tint, slit) for stable ordering."""
    # Strip trailing axis suffixes to recover the base slug for FAMILIES lookup.
    base = re.sub(r"-(?:d[123]|t[123]|s\d)+$", "", slug)
    d = int((m := re.search(r"-d(\d)", slug)) and m.group(1) or "0")
    t = int((m := re.search(r"-t(\d)", slug)) and m.group(1) or "0")
    s = int((m := re.search(r"-s(\d)", slug)) and m.group(1) or "0")
    # locate base in grid families
    from grid import FAMILIES

    family_names = list(FAMILIES.keys())
    for fidx, name in enumerate(family_names):
        if base in FAMILIES[name]:
            return (fidx, FAMILIES[name].index(base), d, t, s)
    # unlisted tiles fall to "More" section, sorted alphabetically within
    return (len(family_names), slug, d, t, s)


def main() -> int:
    tiles = sorted(OUT_DIR.glob("enclave-icon-*-1024.png"))
    if not tiles:
        print(f"No tiles found in {OUT_DIR}", file=sys.stderr)
        return 1

    # strip filename prefix/suffix to get slug
    slugs = [p.name[len("enclave-icon-") : -len("-1024.png")] for p in tiles]
    ordered = sorted(zip(tiles, slugs), key=lambda item: _order_key(item[1]))

    with LIST_PATH.open("w") as f:
        for path, _ in ordered:
            f.write(f"file '{path.resolve()}'\n")
            f.write("duration 0.3\n")
        # concat demuxer requires the last file to be repeated without duration
        f.write(f"file '{ordered[-1][0].resolve()}'\n")

    print(f"Concat list: {LIST_PATH} ({len(ordered)} tiles)")
    cmd = [
        "ffmpeg",
        "-y",
        "-f",
        "concat",
        "-safe",
        "0",
        "-i",
        str(LIST_PATH),
        "-vf",
        "pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p",
        "-vsync",
        "vfr",
        str(VIDEO_PATH),
    ]
    subprocess.run(cmd, check=True)
    print(f"Video: {VIDEO_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
