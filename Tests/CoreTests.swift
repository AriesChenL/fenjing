import AppKit
import Foundation
import Darwin

func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !value() { throw AppFailure("FAILED: " + message) }
}
func rejects(_ message: String, _ action: () throws -> Void) throws {
    do { try action() } catch { print("PASS " + message); return }
    throw AppFailure("FAILED: expected rejection: " + message)
}

@main struct CoreTests {
    static func main() throws {
        if CommandLine.arguments.contains("--cleanup") {
            let repo = try ProfileRepository(root: URL(fileURLWithPath: CommandLine.arguments[2]))
            let core = BrowserCore(repository: repo)
            for p in try repo.load().profiles { try core.stop(p) }
            print("CLEANUP CONFIRMED"); return
        }
        if CommandLine.arguments.contains("--browser-host") { try browserHost(); return }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fenjing-core-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try ProfileRepository(root: root)
        let core = BrowserCore(repository: repository)
        var a = BrowserProfile(); a.name = "Test A"
        var b = BrowserProfile(); b.name = "Test B"; b.seed = a.seed == 1 ? 2 : 1
        try repository.save(Catalog(profiles: [a, b]))
        try expect(try repository.load().profiles == [a, b], "persistence round trip")
        print("PASS persistence round trip")
        try rejects("exclusive manager lock") { _ = try ProfileRepository(root: root) }
        var bad = a; bad.seed = 0
        try rejects("zero seed") { try bad.validate() }
        bad = a; bad.startURL = "file:///etc/passwd"
        try rejects("local file startup URL") { try bad.validate() }
        for value in ["socks5://user:password@localhost:1080", "http://localhost", "socks5://localhost:1080/?extra=1", "http://localhost:1080 --disable-web-security", "http://localhost:0", "file://localhost:1080"] {
            try rejects("invalid or credential-bearing proxy") { _ = try BrowserProfile.proxyURL(value) }
        }
        _ = try BrowserProfile.proxyURL("socks5h://[::1]:1080")
        _ = try BrowserProfile.proxyURL("http://127.0.0.1:80")
        print("PASS IPv6 and explicit default proxy port")
        var duplicate = b; duplicate.seed = a.seed
        try rejects("duplicate seeds") { try repository.save(Catalog(profiles: [a, duplicate])) }
        duplicate = b; duplicate.id = a.id
        try rejects("duplicate IDs") { try repository.save(Catalog(profiles: [a, duplicate])) }
        let engine = try BrowserEngine(path: (ProcessInfo.processInfo.environment["FENJING_TEST_ENGINE"] ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("FenJing.app/Contents/Resources/FenJing Browser.app").path))
        var malicious = a; malicious.name = "$(touch /tmp/fenjing-must-not-run)"; malicious.startURL = "https://example.test/?q=$(touch%20/tmp/fenjing-must-not-run)"
        let args = try core.arguments(malicious, engine: engine)
        try expect(try core.arguments(a, engine: engine).last == "https://www.google.com/", "default Google home")
        var emptyHome = a; emptyHome.startURL = ""
        try expect(try core.arguments(emptyHome, engine: engine).last == "https://www.google.com/", "empty URL uses Google")
        try expect(args.last == malicious.startURL, "URL remains one argument")
        try expect(!args.contains(where: { $0.contains("remote-debugging") }), "no production debugging endpoint")
        try expect(args.contains("--fingerprint-brand-version=\(engine.version)"), "actual engine version")
        try expect(try repository.profileURL(a) != repository.profileURL(b), "different browser paths")
        print("PASS argument boundaries, real version and unique profile paths")
        var http = a; http.proxy = "http://127.0.0.1:7890"
        let httpArgs = try core.arguments(http, engine: engine)
        try expect(httpArgs.contains("--proxy-server=http://127.0.0.1:7890"), "per-environment HTTP proxy")
        try expect(httpArgs.contains("--proxy-bypass-list=127.0.0.1;localhost;[::1]"), "loopback bypass")
        print("PASS Google default and explicit HTTP proxy arguments")
        let profile = try repository.profileURL(a)
        try PrivateFiles.directory(profile.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(at: profile, withDestinationURL: root)
        try rejects("symlink profile") { _ = try repository.profileURL(a) }
        try FileManager.default.removeItem(at: profile)
        let catalogURL = root.appendingPathComponent("environments.json")
        let mode = try FileManager.default.attributesOfItem(atPath: catalogURL.path)[.posixPermissions] as! NSNumber
        try expect(mode.intValue & 0o777 == 0o600, "private catalog file mode")
        let old = try Data(contentsOf: catalogURL)
        try rejects("unknown catalog version") { try repository.save(Catalog(version: 99, profiles: [a])) }
        try expect(try Data(contentsOf: catalogURL) == old, "failed save preserves file")
        try Data("broken".utf8).write(to: catalogURL)
        try rejects("corrupt catalog") { _ = try repository.load() }
        try expect(try Data(contentsOf: catalogURL) == Data("broken".utf8), "corrupt catalog not overwritten")
        print("PASS private permissions and failure preservation")
        print("ALL CORE TESTS PASSED")
    }
    static func browserHost() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        let repository = try ProfileRepository(root: root)
        let core = BrowserCore(repository: repository)
        let engine = try BrowserEngine(path: (ProcessInfo.processInfo.environment["FENJING_TEST_ENGINE"] ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("FenJing.app/Contents/Resources/FenJing Browser.app").path))
        var a = BrowserProfile(); a.name = "Integration A"; a.seed = 135792468; a.language = "en-US"; a.timezone = "America/New_York"
        var b = BrowserProfile(); b.name = "Integration B"; b.seed = 246813579; b.language = "ja-JP"; b.timezone = "Asia/Tokyo"
        if CommandLine.arguments.count > 4 { a.proxy = CommandLine.arguments[3]; b.proxy = CommandLine.arguments[4] }
        try repository.save(Catalog(profiles: [a, b]))
        defer { try? core.stop(a); try? core.stop(b) }
        // Launch concurrently through the exact core used by the GUI.
        let group = DispatchGroup(); let errors = ErrorCollector()
        for p in [a, b] { group.enter(); DispatchQueue.global().async { defer { group.leave() }; do { try core.launch(p, engine: engine, test: true) } catch { errors.append(error) } } }
        while group.wait(timeout: .now()) != .success { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        if let error = errors.first { throw error }
        func report(_ phase: String) throws {
            let value: [String: Any] = ["phase": phase, "a": try core.running(a), "b": try core.running(b), "pathA": try repository.profileURL(a).path, "pathB": try repository.profileURL(b).path]
            try PrivateFiles.write(JSONSerialization.data(withJSONObject: value), to: root.appendingPathComponent("status.json"))
        }
        try report("both-running")
        let deadline = Date().addingTimeInterval(100)
        var stoppedA = false
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("stop-a").path), !stoppedA {
                try core.stop(a); stoppedA = true; try report("a-stopped")
            }
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("restart-a").path), stoppedA {
                try core.launch(a, engine: engine, test: true); stoppedA = false; try report("a-restarted")
            }
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("finish").path) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        try core.stop(a); try core.stop(b); try report("all-stopped")
    }
}
final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock(); private var values: [Error] = []
    func append(_ error: Error) { lock.lock(); values.append(error); lock.unlock() }
    var first: Error? { lock.lock(); defer { lock.unlock() }; return values.first }
}
