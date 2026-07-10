#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
CAPTURE_UDID="${CAPTURE_UDID:-B943CA0E-37E4-4F27-BA2E-9D38C145A74F}"   # iPad Pro 13" (M5) — big framebuffer
QA_UDID="${QA_UDID:-}"                                                   # empty = skip QA for split run
BUNDLE=tools.enclave.IconRenderer

# Split-almond run: all UI-color variants (liquidMark) + curated flat-glass variants (flatGlass/flatGlassRing)
VARIANTS="${VARIANTS:-ui-iris ui-foam ui-gold ui-pine ui-rose ui-love ui-muted \
          ui-iris-dark ui-foam-dark ui-gold-dark ui-pine-dark ui-rose-dark ui-love-dark ui-muted-dark \
          ui-accent \
          fg-ocean fg-grape fg-ember fg-jade fg-cobalt fg-magenta fg-bronze \
          fg-ocean-dark fg-grape-dark fg-ember-dark fg-jade-dark fg-cobalt-dark fg-magenta-dark fg-bronze-dark \
          fg-ocean-ring fg-grape-ring fg-ember-ring fg-jade-ring fg-cobalt-ring fg-magenta-ring fg-bronze-ring \
          fg-ocean-ring-dark fg-grape-ring-dark fg-ember-ring-dark fg-jade-ring-dark fg-cobalt-ring-dark fg-magenta-ring-dark fg-bronze-ring-dark}"
ENCLAVE_SPLIT="${ENCLAVE_SPLIT:-1}"
QA_PICKS="${QA_PICKS:-}"

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
        SIMCTL_CHILD_ENCLAVE_SPLIT="$ENCLAVE_SPLIT" \
        xcrun simctl launch "$CAPTURE_UDID" "$BUNDLE" >/dev/null
        sleep 2.5
        tag="$v"
        [[ "$d" != "0" ]] && tag="$tag-d$d"
        [[ "$t" != "0" ]] && tag="$tag-t$t"
        [[ "$s" != "0" ]] && tag="$tag-s$s"
        [[ "$ENCLAVE_SPLIT" != "0" ]] && tag="$tag-split"
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

# Phone-scale QA on iPhone 17 Pro (set QA_UDID + QA_PICKS to enable)
if [[ -n "${QA_UDID:-}" && -n "${QA_PICKS:-}" ]]; then
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
          SIMCTL_CHILD_ENCLAVE_SPLIT="$ENCLAVE_SPLIT" \
          xcrun simctl launch "$QA_UDID" "$BUNDLE" >/dev/null
          sleep 2
          tag="$v"
          [[ "$d" != "0" ]] && tag="$tag-d$d"
          [[ "$t" != "0" ]] && tag="$tag-t$t"
          [[ "$s" != "0" ]] && tag="$tag-s$s"
          [[ "$ENCLAVE_SPLIT" != "0" ]] && tag="$tag-split"
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
