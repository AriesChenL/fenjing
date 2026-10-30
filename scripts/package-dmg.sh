#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/FenJing.app"
OUT="$PWD/dist"
test -d "$APP" || { echo 'Build FenJing.app first.' >&2; exit 1; }
mkdir -p "$OUT"
test ! -e "$OUT/FenJing-macOS-arm64.dmg" || { echo 'Output already exists; refusing to overwrite it.' >&2; exit 1; }
python3 scripts/verify-bundle.py "$APP"
STAGING=$(mktemp -d "$PWD/build/installer.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/FenJing.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname FenJing -srcfolder "$STAGING" -format UDZO "$OUT/FenJing-macOS-arm64.dmg"
hdiutil verify "$OUT/FenJing-macOS-arm64.dmg"
cd "$OUT"
shasum -a256 FenJing-macOS-arm64.dmg > SHA256SUMS.txt
