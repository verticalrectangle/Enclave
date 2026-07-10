#!/bin/bash
# capture_combos.sh — render 8 material combos × 3 UI palettes = 24 tiles.
# Each combo toggles glossy ball-style RadialGradient + specular on/off
# per element (disc, ring, glyph) over the existing Liquid Glass base.
set -euo pipefail
cd "$(dirname "$0")"
CAPTURE_UDID="${CAPTURE_UDID:-B943CA0E-37E4-4F27-BA2E-9D38C145A74F}"
BUNDLE=tools.enclave.IconRenderer

# 3 representative palettes
PALETTES="ui-iris ui-gold-dark ui-pine"
ENCLAVE_SPLIT="${ENCLAVE_SPLIT:-0.066}"

# 8 combos: disc ring glyph (0=glass, 1=glossy)
COMBOS=(
  "000"  # all glass (baseline)
  "001"  # glyph only glossy
  "010"  # ring only glossy
  "011"  # ring + glyph glossy
  "100"  # disc only glossy
  "101"  # disc + glyph glossy
  "110"  # disc + ring glossy
  "111"  # all glossy
)

xcodegen generate
xcodebuild -scheme IconRenderer -destination "id=$CAPTURE_UDID" -derivedDataPath build -quiet build
xcrun simctl boot "$CAPTURE_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$CAPTURE_UDID" 2>/dev/null || true
xcrun simctl install "$CAPTURE_UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
mkdir -p out

for v in $PALETTES; do
  for combo in "${COMBOS[@]}"; do
    gd="${combo:0:1}"
    gr="${combo:1:1}"
    gg="${combo:2:1}"
    tag="combo-${v}-${combo}-split"
    out_path="out/enclave-icon-${tag}-1024.png"
    if [[ -f "$out_path" ]]; then echo "skip $tag"; continue; fi
    xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
    SIMCTL_CHILD_ENCLAVE_VARIANT="$v" \
    SIMCTL_CHILD_ENCLAVE_GLOSSY_DISC="$gd" \
    SIMCTL_CHILD_ENCLAVE_GLOSSY_RING="$gr" \
    SIMCTL_CHILD_ENCLAVE_GLOSSY_GLYPH="$gg" \
    SIMCTL_CHILD_ENCLAVE_SPLIT="$ENCLAVE_SPLIT" \
    xcrun simctl launch "$CAPTURE_UDID" "$BUNDLE" >/dev/null
    sleep 5
    xcrun simctl io "$CAPTURE_UDID" screenshot "shot-${tag}.png" >/dev/null
    xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
    W=$(sips -g pixelWidth  "shot-${tag}.png" | awk '{print $2}')
    H=$(sips -g pixelHeight "shot-${tag}.png" | awk '{print $2}')
    SIDE=$(( W < H ? W : H ))
    sips -c "$SIDE" "$SIDE" "shot-${tag}.png" --out "crop-${tag}.png" >/dev/null
    sips -z 1024 1024 "crop-${tag}.png" --out "$out_path" >/dev/null
    rm -f "shot-${tag}.png" "crop-${tag}.png"
    echo "captured: $tag"
  done
done

echo "combo tiles captured: $(ls out/enclave-icon-combo-*split-1024.png 2>/dev/null | wc -l | tr -d ' ')"
