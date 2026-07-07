#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
CAPTURE_UDID="${CAPTURE_UDID:-B943CA0E-37E4-4F27-BA2E-9D38C145A74F}"   # iPad Pro 13" (M5) — big framebuffer
QA_UDID="${QA_UDID:-B6A14236-A690-4845-BB83-E3297731AF5F}"             # iPhone 17 Pro — home-screen-scale QA
BUNDLE=tools.enclave.IconRenderer
VARIANTS="${VARIANTS:-aurora-bloom aurora-dusk aurora-veil aurora-prism \
          sapphire-glass emerald-glass amethyst-glass topaz-glass ruby-glass \
          obsidian midnight-bloom deep-well \
          frost-clear pearl-opal liquid-aero \
          gold-amber copper-bloom copper-veil copper-lens copper-ember copper-gold \
          copper-rose copper-prism copper-deep copper-glow copper-frost \
          prism-caustic gem-cut}"
QA_PICKS="${QA_PICKS:-copper-lens copper-prism copper-bloom copper-veil copper-glow}"

xcodegen generate
xcodebuild -scheme IconRenderer -destination "id=$CAPTURE_UDID" -derivedDataPath build -quiet build
xcrun simctl boot "$CAPTURE_UDID" 2>/dev/null || true
open -a Simulator
sleep 3
xcrun simctl install "$CAPTURE_UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
mkdir -p out
for v in $VARIANTS; do
  xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_ENCLAVE_VARIANT="$v" xcrun simctl launch "$CAPTURE_UDID" "$BUNDLE" >/dev/null
  sleep 2.5
  xcrun simctl io "$CAPTURE_UDID" screenshot "shot-$v.png" >/dev/null
  xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
  W=$(sips -g pixelWidth  "shot-$v.png" | awk '{print $2}')
  H=$(sips -g pixelHeight "shot-$v.png" | awk '{print $2}')
  SIDE=$(( W < H ? W : H ))
  sips -c "$SIDE" "$SIDE" "shot-$v.png" --out "crop-$v.png" >/dev/null
  sips -z 1024 1024 "crop-$v.png" --out "out/enclave-icon-$v-1024.png" >/dev/null
done
echo "captured: $(ls out | wc -l) tiles"

# Phone-scale QA on iPhone 17 Pro (set QA_UDID= to skip)
if [[ -n "${QA_UDID:-}" ]]; then
  xcrun simctl boot "$QA_UDID" 2>/dev/null || true
  xcrun simctl install "$QA_UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
  mkdir -p out/qa
  for v in $QA_PICKS; do
    xcrun simctl terminate "$QA_UDID" "$BUNDLE" 2>/dev/null || true
    SIMCTL_CHILD_ENCLAVE_VARIANT="$v" xcrun simctl launch "$QA_UDID" "$BUNDLE" >/dev/null
    sleep 2
    xcrun simctl io "$QA_UDID" screenshot "out/qa/iphone17pro-$v.png" >/dev/null
    xcrun simctl terminate "$QA_UDID" "$BUNDLE" 2>/dev/null || true
  done
  echo "qa shots: $(ls out/qa)"
fi
