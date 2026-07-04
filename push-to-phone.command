#!/bin/bash
#
#  push-to-phone.command  —  build Enclave and run it on your iPhone
#  Double-click in Finder, or run from Terminal.
#
set -euo pipefail

# ── config ───────────────────────────────────────────────────────────
PROJECT_DIR="$HOME/Enclave"
SCHEME="Enclave"
BUNDLE_ID="xyz.epsilver.enclave"
TEAM_ID="8CNGT2JGKC"                 # Apple Development team (William Alexis Toledo Lucio)
DERIVED="$PROJECT_DIR/build-device"
# ─────────────────────────────────────────────────────────────────────

cd "$PROJECT_DIR"
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

if [ -d .git ]; then
  echo "▸ Pulling latest from GitHub …"
  git pull --ff-only || echo "  (skipped: local changes or offline — building what's here)"
fi

echo "▸ Regenerating Xcode project from ./Sources …"
xcodegen generate >/dev/null

echo "▸ Finding a connected iPhone …"
DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
  | awk -F'  +' '/available|connected/ && /iPhone|iPad/ {print $3; exit}')

if [ -z "${DEVICE_ID:-}" ]; then
  echo "✗ No paired iPhone found."
  echo "  Plug it in (or connect over Wi-Fi), unlock it, and tap 'Trust'."
  read -n 1 -s -r -p "Press any key to close…"; echo; exit 1
fi
echo "  → device $DEVICE_ID"

echo "▸ Building & signing for device …"
xcodebuild \
  -project Enclave.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  build | tail -n 3

APP="$DERIVED/Build/Products/Debug-iphoneos/Enclave.app"
[ -d "$APP" ] || { echo "✗ Build produced no app at $APP"; exit 1; }

echo "▸ Installing onto iPhone …"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "▸ Launching …"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null

echo
echo "✓ Enclave is now on your iPhone and opening."
echo "  First run only: if it won't open, trust the developer on-device at"
echo "  Settings › General › VPN & Device Management › Apple Development."
