#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."                          # repo root
MAC=alexis@macbookpro.local
REMOTE=/tmp/enclave-icon-render

echo ">> sync renderer to Mac"
rsync -az --delete --exclude out --exclude build tools/IconRenderer/ "$MAC:$REMOTE/"

echo ">> build + capture on Mac (real Liquid Glass)"
ssh "$MAC" "cd $REMOTE && bash capture.sh"

echo ">> pull tiles"
mkdir -p Marketing/icon
scp "$MAC:$REMOTE/out/enclave-icon-"*"-1024.png" Marketing/icon/

echo ">> flatten to opaque sRGB + build grid"
python3 tools/grid.py

echo ">> swap app icon (ui-gold-dark baseline)"
cp Marketing/icon/enclave-icon-ui-gold-dark-1024.png \
   Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

echo "done. inspect Marketing/icon/icon-grid.png"
