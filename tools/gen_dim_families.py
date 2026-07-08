#!/usr/bin/env python3
"""Generate the dimmed-tile variant list and grid.py family block for glass disc/ring variants."""
import re
import sys
from pathlib import Path

GRID_PATH = Path(__file__).with_name("grid.py")
GRID_SRC = GRID_PATH.read_text()

m = re.search(r"FAMILIES = \{(.*?)\n\}", GRID_SRC, re.DOTALL)
if not m:
    print("Could not locate FAMILIES dict in grid.py", file=sys.stderr)
    sys.exit(1)

ns: dict = {}
exec("FAMILIES = {" + m.group(1) + "\n}", ns)
FAMILIES = ns["FAMILIES"]

BASE_FAMILIES = [
    "Glass",
    "Glass Ring",
    "Glass Pastel",
    "Glass Pastel Ring",
    "Glass Neon",
    "Glass Neon Ring",
    "Glass Mono",
    "Glass Mono Ring",
    "Glass · Copper",
]

# 1) space-joined variant list for capture.sh
variants = [slug for name in BASE_FAMILIES for slug in FAMILIES[name]]
print(" ".join(variants))

print("---GRID---")

# 2) grid.py family entries for the three dim strengths
for name in BASE_FAMILIES:
    base = FAMILIES[name]
    for level in (1, 2, 3):
        dimmed = [f"{slug}-d{level}" for slug in base]
        print(f'    "{name} d{level}": {dimmed},')
