// [INPUT]: Profile configuration, bundled Fingerprint Chromium, macOS process bridge.
// [OUTPUT]: Private persistent profiles and independently owned browser lifecycles.
// [POS]: FenJing native core. Startup flags/preferences adapted from CCBaga 6db5ad5.
import AppKit
import Foundation
import Darwin
import CoreServices

@_silgen_name("rf_browser_running") private func nativeRunning(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("rf_browser_quit") private func nativeQuit(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct BrowserProfile: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name = "新环境"
    var seed: UInt32 = UInt32.random(in: 1...UInt32.max)
    var language = "en-US"
    var timezone = "America/Los_Angeles"
    var proxy = ""
    var startURL = "https://www.google.com/"
    var notes = ""
    var color = 0
    var created = Date()
    static let languages = ["en-US", "en-GB", "en-CA", "en-SG", "en-AU", "zh-CN", "zh-TW", "ja-JP", "ko-KR", "de-DE", "fr-FR"]
    var key: String { id.uuidString.lowercased() }
    var networkLabel: String { proxy.isEmpty ? "系统网络 / TUN" : proxy }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80 else { throw AppFailure("环境名称需为 1–80 个字符。") }
        guard seed > 0 else { throw AppFailure("指纹种子必须为 1–4294967295。") }
        guard Self.languages.contains(language), TimeZone.knownTimeZoneIdentifiers.contains(timezone) else { throw AppFailure("请选择有效的语言和时区。") }
        guard notes.count <= 2000, (0..<6).contains(color) else { throw AppFailure("备注过长或环境颜色无效。") }
        if !startURL.isEmpty {
            guard startURL.count <= 2048, let url = URLComponents(string: startURL), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false, url.user == nil, url.password == nil else { throw AppFailure("起始页留空打开 Google，或填写不含账号密码的 HTTP / HTTPS 地址。") }
        }
        _ = try Self.proxyURL(proxy)
    }
    static func proxyURL(_ value: String) throws -> URLComponents? {
        if value.isEmpty { return nil }
        guard value.count <= 2048, !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              let u = URLComponents(string: value), ["http", "https", "socks5", "socks5h"].contains(u.scheme ?? ""),
              let host = u.host, !host.isEmpty, host.range(of: "^[A-Za-z0-9.\\[\\]:-]+$", options: .regularExpression) != nil,
              let port = u.port, (1...65535).contains(port), u.user == nil, u.password == nil,
              u.query == nil, u.fragment == nil, ["", "/"].contains(u.path)
        else { throw AppFailure("代理格式应为 socks5://主机:端口 或 http://主机:端口。带密码的代理请先交给本机代理客户端。") }
        return u
    }
}

struct Catalog: Codable {
    var version = 1
    var profiles: [BrowserProfile] = []
}

enum PrivateFiles {
    static func check(_ path: URL, beneath root: URL) throws {
        guard path.path == root.path || path.path.hasPrefix(root.path + "/") else { throw AppFailure("拒绝访问环境目录以外的资料。") }
        var cursor = root
        let parts = path.path.dropFirst(root.path.count).split(separator: "/")
        for part in [""] + parts.map(String.init) {
            if !part.isEmpty { cursor.appendPathComponent(part) }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: cursor.path), attrs[.type] as? FileAttributeType == .typeSymbolicLink { throw AppFailure("资料路径含符号链接，已停止操作。") }
        }
    }
    static func directory(_ url: URL) throws {
        if let a = try? FileManager.default.attributesOfItem(atPath: url.path) {
            guard a[.type] as? FileAttributeType == .typeDirectory, (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw AppFailure("资料目录类型或所有者无效。") }
        } else { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    static func write(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".write-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw AppFailure("无法创建私有配置文件。") }
        defer { try? FileManager.default.removeItem(at: temp) }
        let handle = try FileHandle(forWritingTo: temp)
        try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        guard rename(temp.path, url.path) == 0 else { throw AppFailure("配置保存失败，原文件已保留。") }
    }
}

final class ProfileRepository {
    let root: URL
    private var lockFD: Int32 = -1
    init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try PrivateFiles.directory(self.root)
        let lock = self.root.appendingPathComponent("manager.lock")
        try PrivateFiles.check(lock, beneath: self.root)
        lockFD = Darwin.open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { if lockFD >= 0 { close(lockFD); lockFD = -1 }; throw AppFailure("另一个分境实例正在管理这个资料目录，请回到已打开的窗口。") }
    }
    deinit { if lockFD >= 0 { flock(lockFD, LOCK_UN); close(lockFD) } }
    func load() throws -> Catalog {
        let path = root.appendingPathComponent("environments.json")
        try PrivateFiles.check(path, beneath: root)
        guard FileManager.default.fileExists(atPath: path.path) else { return Catalog() }
        let data = try Data(contentsOf: path)
        guard data.count < 4_000_000 else { throw AppFailure("环境配置过大，未覆盖原文件。") }
        let c: Catalog
        do { c = try JSONDecoder().decode(Catalog.self, from: data) } catch { throw AppFailure("环境配置损坏，未覆盖原文件。请检查 environments.json。") }
        try validate(c)
        return c
    }
    func validate(_ catalog: Catalog) throws {
        guard catalog.version == 1, catalog.profiles.count <= 500,
              Set(catalog.profiles.map(\.id)).count == catalog.profiles.count,
              Set(catalog.profiles.map(\.seed)).count == catalog.profiles.count else { throw AppFailure("环境配置版本、编号或指纹种子冲突，未修改配置。") }
        for p in catalog.profiles { try p.validate() }
    }
    func save(_ catalog: Catalog) throws {
        try validate(catalog)
        let path = root.appendingPathComponent("environments.json")
        try PrivateFiles.check(path, beneath: root)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try PrivateFiles.write(encoder.encode(catalog), to: path)
    }
    func profileURL(_ profile: BrowserProfile) throws -> URL {
        let path = root.appendingPathComponent("profiles/" + profile.key)
        try PrivateFiles.check(path, beneath: root)
        return path
    }
}

struct BrowserEngine {
    static var bundledPath: String { Bundle.main.resourceURL!.appendingPathComponent("FenJing Browser.app").path }
    let app: URL
    let executable: URL
    let version: String
    init(path: String) throws {
        app = URL(fileURLWithPath: path).standardizedFileURL
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "local.fenjing.engine" else { throw AppFailure("内置指纹引擎缺失或损坏，请重新安装完整的分境应用。") }
        executable = app.appendingPathComponent("Contents/MacOS/Chromium")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw AppFailure("内置指纹引擎不可用，请重新安装完整的分境应用。") }
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard version.range(of: "^[0-9]+(\\.[0-9]+){1,3}$", options: .regularExpression) != nil else { throw AppFailure("无法读取指纹引擎的实际版本。") }
    }
}

final class BrowserCore: @unchecked Sendable {
    let repository: ProfileRepository
    private let lock = NSLock()
    private var children: [UUID: Process] = [:]
    init(repository: ProfileRepository) { self.repository = repository }
    private func native(_ profile: BrowserProfile, quit: Bool) throws -> Bool {
        let path = try repository.profileURL(profile).path
        let value = path.withCString { quit ? nativeQuit($0) : nativeRunning($0) }
        guard let value else { throw AppFailure("无法读取浏览器进程状态。") }
        defer { free(value) }
        let object = try JSONSerialization.jsonObject(with: Data(String(cString: value).utf8)) as? [String: Any]
        if let error = object?["error"] as? String { throw AppFailure(error) }
        if quit { return object?["ok"] as? Bool == true }
        guard let running = object?["running"] as? Bool else { throw AppFailure("无法确认浏览器运行状态。") }
        return running
    }
    func running(_ profile: BrowserProfile) throws -> Bool { try native(profile, quit: false) }
    func arguments(_ p: BrowserProfile, engine: BrowserEngine, page: String? = nil) throws -> [String] {
        try p.validate()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var args = [
            "--user-data-dir=\(try repository.profileURL(p).path)", "--profile-directory=Default",
            "--fingerprint=\(p.seed)", "--fingerprint-platform=macos",
            "--fingerprint-platform-version=\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "--fingerprint-brand=Chrome", "--fingerprint-brand-version=\(engine.version)",
            "--fingerprint-hardware-concurrency=\(ProcessInfo.processInfo.activeProcessorCount)",
            "--lang=\(p.language)", "--accept-lang=\(p.language),\(p.language.split(separator: "-")[0])", "--timezone=\(p.timezone)",
            "--disable-spoofing=font,audio,gpu", "--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
            "--disable-non-proxied-udp", "--disable-quic", "--no-first-run", "--no-default-browser-check", "--window-size=1180,820"
        ]
        if let proxy = try BrowserProfile.proxyURL(p.proxy) {
            args += ["--proxy-server=\(p.proxy.replacingOccurrences(of: "socks5h://", with: "socks5://"))", "--proxy-bypass-list=127.0.0.1;localhost;[::1]"]
            if proxy.scheme?.hasPrefix("socks") == true {
                let host = proxy.host!.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                args += ["--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE \(host), EXCLUDE 127.0.0.1, EXCLUDE localhost, EXCLUDE ::1"]
            }
        }
        args.append(page ?? (p.startURL.isEmpty ? "https://www.google.com/" : p.startURL))
        return args
    }
    private func preferences(_ p: BrowserProfile) throws {
        let profile = try repository.profileURL(p)
        try PrivateFiles.directory(profile)
        let folder = profile.appendingPathComponent("Default")
        try PrivateFiles.check(folder, beneath: repository.root)
        try PrivateFiles.directory(folder)
        let path = folder.appendingPathComponent("Preferences")
        try PrivateFiles.check(path, beneath: repository.root)
        var data: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: path.path) {
            guard let existing = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any] else { throw AppFailure("浏览器偏好格式损坏，未覆盖原文件。") }; data = existing
        }
        func set(_ object: inout [String: Any], _ keys: ArraySlice<String>, _ value: Any) throws {
            guard let key = keys.first else { return }
            if keys.count == 1 { object[key] = value; return }
            if let current = object[key], !(current is [String: Any]) { throw AppFailure("浏览器偏好字段格式异常，未覆盖原文件。") }
            var child = object[key] as? [String: Any] ?? [:]; try set(&child, keys.dropFirst(), value); object[key] = child
        }
        let lang = "\(p.language),\(p.language.split(separator: "-")[0])"
        for (path, value): (String, Any) in [
            ("intl.accept_languages", lang), ("intl.selected_languages", lang),
            ("webrtc.ip_handling_policy", "disable_non_proxied_udp"),
            ("profile.default_content_setting_values.geolocation", 2),
            ("profile.default_content_setting_values.geolocation_with_options", ["approximate": 2, "precise": 2]),
            ("profile.content_settings.exceptions.geolocation", [String: Any]()),
            ("profile.content_settings.exceptions.geolocation_with_options", [String: Any]())
        ] { try set(&data, path.split(separator: ".").map(String.init)[...], value) }
        try PrivateFiles.write(JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), to: path)
    }
    @discardableResult func launch(_ p: BrowserProfile, engine: BrowserEngine, test: Bool = false) throws -> Int32 {
        guard LSRegisterURL(engine.app as CFURL, true) == noErr else { throw AppFailure("无法注册内置浏览器应用。") }
        let active = try running(p)
        if !active { try preferences(p) }
        let process = Process(); process.executableURL = engine.executable
        var args = try arguments(p, engine: engine, page: test ? "about:blank" : nil)
        if test { args.insert(contentsOf: ["--remote-debugging-port=0", "--disable-background-networking", "--disable-component-update"], at: 0) }
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        if test {
            let log = repository.root.appendingPathComponent("engine-\(p.key).log")
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            process.standardError = try FileHandle(forWritingTo: log)
        }
        try process.run()
        lock.lock(); children[p.id] = process; lock.unlock()
        if active { return process.processIdentifier }
        for _ in 0..<160 {
            if try running(p), NSRunningApplication(processIdentifier: process.processIdentifier)?.isFinishedLaunching == true { return process.processIdentifier }
            if !process.isRunning { throw AppFailure("浏览器启动后退出，请检查引擎或资料目录。") }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // This is our own newly spawned process, never an unrelated profile process.
        if test {
            let app = NSRunningApplication(processIdentifier: process.processIdentifier)
            print("engine startup: running=\((try? running(p)) ?? false) bundle=\(app?.bundleIdentifier ?? "unknown") executable=\(app?.executableURL?.lastPathComponent ?? "unknown") ready=\(app?.isFinishedLaunching ?? false)")
            fflush(stdout)
        }
        if process.isRunning { process.terminate() }
        throw AppFailure("浏览器未在 8 秒内确认启动，请刷新状态后重试。")
    }
    func stop(_ p: BrowserProfile) throws {
        _ = try native(p, quit: true)
        for _ in 0..<160 {
            if try !running(p) { lock.lock(); children.removeValue(forKey: p.id); lock.unlock(); return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw AppFailure("浏览器尚未退出，请在对应窗口处理下载或关闭确认后重试。")
    }
}
