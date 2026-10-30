#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun clang -fobjc-arc -mmacosx-version-min=13.0 -c Sources/BrowserBridge.m -o build/BrowserTests.o
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -module-cache-path build/module-cache \
  Sources/Core.swift Tests/CoreTests.swift build/BrowserTests.o \
  -framework AppKit -framework CoreServices -framework CoreLocation -framework SystemConfiguration \
  -o build/CoreTests
build/CoreTests
