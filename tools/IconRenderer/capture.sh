#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
UDID=B943CA0E-37E4-4F27-BA2E-9D38C145A74F
BUNDLE=tools.enclave.IconRenderer
VARIANTS="frost-clear gold-amber deep-well aurora-bloom prism-caustic pearl-opal"

xcodegen generate
xcodebuild -scheme IconRenderer -destination "id=$UDID" \
  -derivedDataPath build -quiet build
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator
sleep 3
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl install "$UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
mkdir -p out

for v in $VARIANTS; do
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  SIMCTL_CHILD_ENCLAVE_VARIANT="$v" xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  sleep 2.5
  xcrun simctl io "$UDID" screenshot "shot-$v.png" >/dev/null
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  W=$(sips -g pixelWidth  "shot-$v.png" | awk '{print $2}')
  H=$(sips -g pixelHeight "shot-$v.png" | awk '{print $2}')
  SIDE=$(( W < H ? W : H ))                       # square = screen width (portrait iPad)
  sips -c "$SIDE" "$SIDE" "shot-$v.png" --out "crop-$v.png" >/dev/null
  sips -z 1024 1024 "crop-$v.png" --out "out/enclave-icon-$v-1024.png" >/dev/null
done
echo "captured: $(ls out)"
