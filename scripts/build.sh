#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
APP="$PWD/build/FenJing.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
rm -f "$APP/Contents/Resources/Start.html"
xcrun clang -fobjc-arc -mmacosx-version-min=13.0 -c Sources/BrowserBridge.m -o build/Browser.o
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path build/module-cache \
  Sources/Core.swift Sources/App.swift build/Browser.o \
  -framework AppKit -framework SwiftUI -framework CoreServices -framework CoreLocation -framework SystemConfiguration \
  -o "$APP/Contents/MacOS/FenJing"
cp licenses/CCBaga-MIT.txt "$APP/Contents/Resources/LICENSE.CCBaga.txt"
cp licenses/Fingerprint-Chromium-BSD.txt "$APP/Contents/Resources/LICENSE.fingerprint-chromium.txt"
xcrun swift -module-cache-path build/module-cache scripts/make-icon.swift build/FenJing.iconset
iconutil -c icns build/FenJing.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FenJing</string>
<key>CFBundleIdentifier</key><string>local.fenjing.browser-manager</string>
<key>CFBundleName</key><string>FenJing</string>
<key>CFBundleDisplayName</key><string>分境</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright (c) 2026 lynn. caused by codex. See ThirdPartyNotices.txt.</string>
</dict></plist>
PLIST
python3 scripts/package-engine.py "$APP"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
