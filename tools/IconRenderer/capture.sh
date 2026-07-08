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
          prism-caustic gem-cut \
          ui-iris ui-foam ui-gold ui-pine ui-rose ui-love ui-muted \
          ui-iris-dark ui-foam-dark ui-gold-dark ui-pine-dark ui-rose-dark ui-love-dark ui-muted-dark \
          ui-accent}"
QA_PICKS="${QA_PICKS:-copper-lens copper-prism copper-bloom copper-veil copper-glow}"

xcodegen generate
xcodebuild -scheme IconRenderer -destination "id=$CAPTURE_UDID" -derivedDataPath build -quiet build
xcrun simctl boot "$CAPTURE_UDID" 2>/dev/null || true
open -a Simulator
sleep 3
xcrun simctl install "$CAPTURE_UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
mkdir -p out
DIM_LEVELS="${DIM_LEVELS:-0}"
TINT_LEVELS="${TINT_LEVELS:-0}"
SLIT_LEVELS="${SLIT_LEVELS:-0}"
for v in $VARIANTS; do
  for d in $DIM_LEVELS; do
    for t in $TINT_LEVELS; do
      for s in $SLIT_LEVELS; do
        xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
        SIMCTL_CHILD_ENCLAVE_VARIANT="$v" SIMCTL_CHILD_ENCLAVE_DIM="$d" \
        SIMCTL_CHILD_ENCLAVE_TINT="$t" SIMCTL_CHILD_ENCLAVE_SLIT="$s" \
        xcrun simctl launch "$CAPTURE_UDID" "$BUNDLE" >/dev/null
        sleep 2.5
        tag="$v"
        [[ "$d" != "0" ]] && tag="$tag-d$d"
        [[ "$t" != "0" ]] && tag="$tag-t$t"
        [[ "$s" != "0" ]] && tag="$tag-s$s"
        out_path="out/enclave-icon-$tag-1024.png"
        if [[ -f "$out_path" ]]; then
          echo "skip $tag"
          rm -f "shot-$tag.png" "crop-$tag.png"
          continue
        fi
        xcrun simctl io "$CAPTURE_UDID" screenshot "shot-$tag.png" >/dev/null
        xcrun simctl terminate "$CAPTURE_UDID" "$BUNDLE" 2>/dev/null || true
        W=$(sips -g pixelWidth  "shot-$tag.png" | awk '{print $2}')
        H=$(sips -g pixelHeight "shot-$tag.png" | awk '{print $2}')
        SIDE=$(( W < H ? W : H ))
        sips -c "$SIDE" "$SIDE" "shot-$tag.png" --out "crop-$tag.png" >/dev/null
        sips -z 1024 1024 "crop-$tag.png" --out "$out_path" >/dev/null
        rm -f "shot-$tag.png" "crop-$tag.png"
      done
    done
  done
done
echo "captured: $(ls out | wc -l) tiles"

# Phone-scale QA on iPhone 17 Pro (set QA_UDID= to skip)
if [[ -n "${QA_UDID:-}" ]]; then
  xcrun simctl boot "$QA_UDID" 2>/dev/null || true
  xcrun simctl install "$QA_UDID" build/Build/Products/Debug-iphonesimulator/IconRenderer.app
  mkdir -p out/qa
  for v in $QA_PICKS; do
    for d in $DIM_LEVELS; do
      for t in $TINT_LEVELS; do
        for s in $SLIT_LEVELS; do
          xcrun simctl terminate "$QA_UDID" "$BUNDLE" 2>/dev/null || true
          SIMCTL_CHILD_ENCLAVE_VARIANT="$v" SIMCTL_CHILD_ENCLAVE_DIM="$d" \
          SIMCTL_CHILD_ENCLAVE_TINT="$t" SIMCTL_CHILD_ENCLAVE_SLIT="$s" \
          xcrun simctl launch "$QA_UDID" "$BUNDLE" >/dev/null
          sleep 2
          tag="$v"
          [[ "$d" != "0" ]] && tag="$tag-d$d"
          [[ "$t" != "0" ]] && tag="$tag-t$t"
          [[ "$s" != "0" ]] && tag="$tag-s$s"
          qa_path="out/qa/iphone17pro-$tag.png"
          if [[ -f "$qa_path" ]]; then
            echo "skip qa $tag"
            continue
          fi
          xcrun simctl io "$QA_UDID" screenshot "$qa_path" >/dev/null
          xcrun simctl terminate "$QA_UDID" "$BUNDLE" 2>/dev/null || true
        done
      done
    done
  done
  echo "qa shots: $(ls out/qa)"
fi
