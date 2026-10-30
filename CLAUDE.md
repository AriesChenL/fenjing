# FenJing / 分境

Independent macOS 13+ arm64 application with SwiftUI frosted-glass UI and a bundled Fingerprint Chromium engine. No upstream app is required at runtime.

- `Sources/Core.swift`: private catalog, validation, default Google, per-environment proxy and independent lifecycle; no user-controlled shell execution.
- `Sources/App.swift`: native graphical manager, NSVisualEffectView background, rounded workspace and cards, HTTP-default shared proxy form, asynchronous operations and live status adoption.
- `Sources/BrowserBridge.m`: MIT adaptation of upstream macOS ownership checks, narrowed to `local.fenjing.engine`; no legacy application IDs.
- `Sources/EngineLauncher.c`: own launcher; direct opening routes to our manager and never an upstream host.
- `scripts/build.sh`, `make-icon.swift`, `package-engine.py`, `fetch-engine.py`: own blue icon, local build, embedded engine and ordered local signing. Pinned upstream Browser.app is a build input; it is included in the delivered app.
- `Tests/`: private storage, argument validation and real browser isolation/proxy integration using disposable directories and a local test site. Debug ports exist only in the integration harness.
- `README.md`: product usage, development and limits.
- `build/`: ignored generated artifacts.

Profiles live in Application Support/FenJing/profiles/<UUID>. Default homepage is Google. Each environment has exactly one optional proxy host/port; HTTP is the default type, HTTPS/SOCKS5 reuse the form. Credentials in proxy URLs are rejected; no proxy passwords are persisted or injected. No Claude credential access, system-setting changes, network deployment, update service or SDD. Removing a row retains its browser data. Running/unknown environments cannot be edited/removed/rotated. Quitting/reopening the manager preserves and adopts browser processes. Required third-party copyright/license files remain in the app; no upstream product logos are used.

0.1.1: behind-window sidebar material lives in a native GlassRootView below a non-opaque NSHostingView; tint must not cover the blur. Browser and manager have deliberately different icons. Optional legacy-compatible http1Only applies --disable-http2 only to explicitly selected HTTP/HTTPS profiles; it is off by default and never disables TLS verification. Tests/proxy-network-smoke.mjs is an explicit opt-in external check against a supplied proxy; do not auto-run it in CI or record user IPs/cookies/bodies.
