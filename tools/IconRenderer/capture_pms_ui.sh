#!/bin/bash
# capture_pms_ui.sh — render PopMaker-style UI icons (play-triangle glyph, split).
# Same UI palette backdrops as the existing ui-* variants, but with PopMakerGlyph
# (play triangle) instead of EnclaveSlit. No orbs. Split blade-cut enabled.
set -euo pipefail
cd "$(dirname "$0")"
CAPTURE_UDID="${CAPTURE_UDID:-B943CA0E-37E4-4F27-BA2E-9D38C145A74F}"   # iPad Pro 13" (M5)
BUNDLE=tools.enclave.IconRenderer

# 15 UI variants: 7 base + 7 dark + 1 accent
VARIANTS="ui-iris ui-foam ui-gold ui-pine ui-rose ui-love ui-muted \
          ui-iris-dark ui-foam-dark ui-gold-dark ui-pine-dark ui-rose-dark ui-love-dark ui-muted-dark \
          ui-accent"
ENCLAVE_SPLIT="${ENCLAVE_SPLIT:-0.066}"

xcodegen generate
xcodebuild -scheme IconRenderer -destination "id=$CAPTURE_UDID" -derivedDataPath build -quiet build
xcrun simctl boot "$CAPTURE_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$CAPTURE_UDID" 2>/dev/null || true
xcrun simctl install "$CAPTURE_UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
mkdir -p out

for v in $VARIANTS; do
  tag="pms-${v}-split"
  out_path="out/enclave-icon-${tag}-1024.png"
  if [[ -f "$out_path" ]]; then echo "skip $tag"; continue; fi
  xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_ENCLAVE_VARIANT="$v" \
  SIMCTL_CHILD_ENCLAVE_PM_GLYPH="1" \
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
  echo "captured: $tag -> $out_path"
done

echo "pms-ui icons captured: $(ls out/enclave-icon-pms-ui-*-split-1024.png 2>/dev/null | wc -l | tr -d ' ')"
