// [INPUT]: FenJing profile core and native macOS UI events.
// [OUTPUT]: An independent graphical multi-browser application; no Claude credential access.
import SwiftUI
import AppKit
import Combine

enum RunState: Equatable { case stopped, running, unknown }
enum AppIdentity {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }
}

@MainActor final class EnvironmentManager: ObservableObject {
    @Published var catalog = Catalog()
    @Published var states: [UUID: RunState] = [:]
    @Published var busy: Set<UUID> = []
    @Published var error: String?
    @Published var locked = false
    @Published var banner = "每个环境拥有独立的登录状态、浏览记录和指纹。"
    let root: URL
    private(set) var repository: ProfileRepository?
    private(set) var core: BrowserCore?
    private var timer: Timer?
    init(root: URL) {
        self.root = root
        do {
            let repository = try ProfileRepository(root: root)
            catalog = try repository.load(); self.repository = repository; core = BrowserCore(repository: repository)
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        } catch { locked = true; self.error = error.localizedDescription; banner = "资料未加载，已停止写入。" }
    }
    var runningCount: Int { states.values.filter { $0 == .running }.count }
    var engine: BrowserEngine? { try? BrowserEngine(path: BrowserEngine.bundledPath) }
    func refresh() {
        guard let core else { return }
        var next: [UUID: RunState] = [:]
        for p in catalog.profiles { do { next[p.id] = try core.running(p) ? .running : .stopped } catch { next[p.id] = .unknown } }
        if next != states { states = next }
    }
    private func persist(_ updated: Catalog) throws {
        guard !locked, let repository else { throw AppFailure("资料未加载，无法修改配置。") }
        try repository.save(updated); catalog = updated
    }
    func save(_ profile: BrowserProfile) -> Bool {
        do {
            guard !busy.contains(profile.id), let core else { throw AppFailure("请等待当前操作完成。") }
            guard try !core.running(profile) else { throw AppFailure("请先关闭这个环境，再修改配置。") }
            try profile.validate()
            var updated = catalog
            if let i = updated.profiles.firstIndex(where: { $0.id == profile.id }) { updated.profiles[i] = profile } else { updated.profiles.append(profile) }
            try persist(updated); refresh(); banner = "已保存「\(profile.name)」，下次启动使用此配置。"; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func fresh() -> BrowserProfile {
        var p = BrowserProfile(); p.name = "环境 \(catalog.profiles.count + 1)"; p.color = catalog.profiles.count % 6
        while catalog.profiles.contains(where: { $0.seed == p.seed }) { p.seed = UInt32.random(in: 1...UInt32.max) }
        return p
    }
    func duplicate(_ profile: BrowserProfile) {
        var copy = fresh(); copy.name = String((profile.name + " 副本").prefix(80)); copy.language = profile.language; copy.timezone = profile.timezone; copy.proxy = profile.proxy; copy.http1Only = profile.http1Only; copy.startURL = profile.startURL; copy.notes = profile.notes
        if save(copy) { banner = "已复制配置并分配新指纹。新环境需要单独登录。" }
    }
    func rotate(_ profile: BrowserProfile) {
        var copy = profile
        repeat { copy.seed = UInt32.random(in: 1...UInt32.max) } while catalog.profiles.contains(where: { $0.seed == copy.seed })
        if save(copy) { banner = "已更新「\(profile.name)」的指纹种子，原有登录资料保留。" }
    }
    func start(_ profile: BrowserProfile) {
        guard !busy.contains(profile.id), let core else { return }
        do {
            let engine = try BrowserEngine(path: BrowserEngine.bundledPath)
            busy.insert(profile.id)
            Task {
                do { _ = try await Task.detached { try core.launch(profile, engine: engine) }.value; banner = "「\(profile.name)」已打开。" }
                catch { self.error = "「\(profile.name)」：\(error.localizedDescription)" }
                busy.remove(profile.id); refresh()
            }
        } catch { self.error = error.localizedDescription }
    }
    func stop(_ profile: BrowserProfile) {
        guard !busy.contains(profile.id), let core else { return }
        busy.insert(profile.id)
        Task {
            do { try await Task.detached { try core.stop(profile) }.value; banner = "「\(profile.name)」已关闭，登录资料保留。" }
            catch { self.error = "「\(profile.name)」：\(error.localizedDescription)" }
            busy.remove(profile.id); refresh()
        }
    }
    func remove(_ profile: BrowserProfile) {
        do {
            guard !busy.contains(profile.id), let core else { throw AppFailure("请等待操作完成。") }
            guard try !core.running(profile) else { throw AppFailure("请先关闭环境再移除。") }
            var updated = catalog; updated.profiles.removeAll { $0.id == profile.id }; try persist(updated)
            refresh(); banner = "已移除「\(profile.name)」。浏览器资料仍保留在原目录。"
        } catch { self.error = error.localizedDescription }
    }
    func reveal(_ profile: BrowserProfile? = nil) {
        do {
            guard let repository else { throw AppFailure("资料目录不可用。") }
            let path = try profile.map { try repository.profileURL($0) } ?? repository.root
            if FileManager.default.fileExists(atPath: path.path) { NSWorkspace.shared.open(path) } else { NSWorkspace.shared.open(repository.root) }
        } catch { self.error = error.localizedDescription }
    }
}

enum Palette {
    static let background = Color(red: 0.075, green: 0.085, blue: 0.10)
    static let sidebar = Color(red: 0.055, green: 0.064, blue: 0.077)
    static let surface = Color(red: 0.125, green: 0.135, blue: 0.15).opacity(0.92)
    static let line = Color.white.opacity(0.075)
    static let secondary = Color(red: 0.58, green: 0.63, blue: 0.68)
    static let accent = Color(red: 0.08, green: 0.48, blue: 1.0)
    static let colors: [Color] = [accent, Color(red: 0.55, green: 0.74, blue: 0.96), Color(red: 0.95, green: 0.68, blue: 0.46), Color(red: 0.76, green: 0.66, blue: 0.95), Color(red: 0.43, green: 0.82, blue: 0.73), Color(red: 0.94, green: 0.61, blue: 0.69)]
}

struct SolidButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(primary ? Color.white : Color.white.opacity(0.88))
            .background(primary ? Palette.accent.opacity(configuration.isPressed ? 0.75 : 1) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.065))
            .clipShape(RoundedRectangle(cornerRadius: 7)).contentShape(Rectangle())
    }
}

// Keep the system backdrop outside SwiftUI's composited layer tree. Hosting must
// remain non-opaque so the actual desktop blur reaches the window's glass areas.
final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

final class GlassRootView<Content: View>: NSView {
    override var isOpaque: Bool { false }
    init(rootView: Content) {
        super.init(frame: .zero)
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        let hosting = ClearHostingView(rootView: rootView)
        hosting.wantsLayer = true
        hosting.layer?.isOpaque = false
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        for view in [effect, hosting] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
}

struct MainView: View {
    @ObservedObject var manager: EnvironmentManager
    @State private var query = ""
    @State private var filter = "全部环境"
    @State private var selected: Set<UUID> = []
    @State private var editing: BrowserProfile?
    @State private var deleting: BrowserProfile?
    @State private var rotating: BrowserProfile?
    @State private var showAbout = false
    var visible: [BrowserProfile] {
        manager.catalog.profiles.filter { p in
            (query.isEmpty || (p.name + p.notes + p.timezone).localizedCaseInsensitiveContains(query)) &&
            (filter == "全部环境" || (filter == "正在运行" ? manager.states[p.id] == .running : manager.states[p.id] == .stopped))
        }
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.24, blue: 0.36).opacity(0.22), Color(red: 0.09, green: 0.24, blue: 0.23).opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            HStack(spacing: 0) {
            sidebar.frame(width: 210)
            VStack(alignment: .leading, spacing: 0) {
                header
                controls
                ScrollView {
                    if visible.isEmpty { emptyState } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 16)], spacing: 16) {
                            ForEach(visible) { p in profileCard(p) }
                        }.padding(26)
                    }
                }
                footer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background.opacity(0.92)).clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
                .padding(.top, 46).padding(.trailing, 12).padding(.bottom, 12)
            }
        }
        .foregroundColor(.white).preferredColorScheme(.dark)
        .frame(minWidth: 980, minHeight: 650)
        .sheet(item: $editing) { profile in ProfileEditor(profile: profile, isNew: !manager.catalog.profiles.contains(where: { $0.id == profile.id }), manager: manager) }
        .alert("操作未完成", isPresented: Binding(get: { manager.error != nil }, set: { if !$0 { manager.error = nil } })) { Button("知道了") { manager.error = nil } } message: { Text(manager.error ?? "") }
        .alert("移除这个环境？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("移除", role: .destructive) { if let p = deleting { manager.remove(p); selected.remove(p.id) }; deleting = nil }
        } message: { Text("将从列表移除「\(deleting?.name ?? "")」。浏览器资料保留在本地目录，不会清除登录数据。") }
        .alert("重新生成指纹？", isPresented: Binding(get: { rotating != nil }, set: { if !$0 { rotating = nil } })) {
            Button("取消", role: .cancel) { rotating = nil }
            Button("生成新指纹") { if let p = rotating { manager.rotate(p) }; rotating = nil }
        } message: { Text("「\(rotating?.name ?? "")」下次启动将使用新的指纹种子。Cookie 和登录状态保持原样。") }
        .sheet(isPresented: $showAbout) { about }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 25)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 4) { Text("分境").font(.system(size: 22, weight: .bold, design: .rounded)); Text("FENJING BROWSER").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(2).foregroundColor(Palette.secondary) }
            }.padding(.top, 62).padding(.bottom, 34)
            Text("工作空间").font(.system(size: 10, weight: .medium)).tracking(2).foregroundColor(Palette.secondary).padding(.bottom, 13)
            ForEach([("全部环境", "square.grid.2x2"), ("正在运行", "play.circle"), ("已关闭", "moon")], id: \.0) { title, icon in
                Button { filter = title } label: {
                    HStack { Image(systemName: icon).frame(width: 18); Text(title); Spacer(); if title == "正在运行" { Text("\(manager.runningCount)").font(.system(size: 11, design: .monospaced)) } }
                        .font(.system(size: 12, weight: filter == title ? .semibold : .regular)).padding(12)
                        .foregroundStyle(filter == title ? Color.white : Color.white.opacity(0.67))
                        .background(filter == title ? Palette.accent.opacity(0.80) : .clear).clipShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).padding(.bottom, 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Circle().fill(manager.engine == nil ? .orange : Palette.accent).frame(width: 6, height: 6); Text(manager.engine == nil ? "内置引擎不可用" : "内置指纹引擎").font(.system(size: 11)) }
                Text(manager.engine.map { "Chromium \($0.version)" } ?? "请重新安装完整的分境应用").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.secondary)
                Text("随应用内置，无需另外安装").font(.system(size: 10)).foregroundColor(Palette.accent)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.bottom, 20)
            Button { manager.reveal() } label: { Label("资料目录", systemImage: "folder").font(.system(size: 12)) }.buttonStyle(.plain).foregroundColor(Palette.secondary).padding(.bottom, 17)
            Button { showAbout = true } label: { Label("关于分境", systemImage: "info.circle").font(.system(size: 12)) }.buttonStyle(.plain).foregroundColor(Palette.secondary)
            Text("LOCAL FIRST  /  v\(AppIdentity.version)").font(.system(size: 8, design: .monospaced)).tracking(1).foregroundColor(Palette.secondary.opacity(0.5)).padding(.top, 22).padding(.bottom, 24)
        }.padding(.horizontal, 18)
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(filter).font(.system(size: 25, weight: .semibold))
                Text("\(manager.catalog.profiles.count) 个浏览器环境  ·  \(manager.runningCount) 个正在运行").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button { for p in manager.catalog.profiles where manager.states[p.id] == .running { manager.stop(p) } } label: { Label("正常退出全部", systemImage: "power") }.buttonStyle(SolidButton()).disabled(manager.runningCount == 0 || manager.locked).help("向每个运行中的环境发送正常退出请求，保留浏览器资料")
            Button { editing = manager.fresh() } label: { Label("新建环境", systemImage: "plus") }.buttonStyle(SolidButton(primary: true)).disabled(manager.locked)
        }.padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 22)
    }
    private var controls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary); TextField("搜索名称、备注或时区", text: $query).textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("搜索环境") }.padding(10).frame(maxWidth: 260).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
            Spacer()
            if !selected.isEmpty { Button("取消选择 (\(selected.count))") { selected.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Palette.secondary) }
            Button { for p in manager.catalog.profiles where selected.contains(p.id) && manager.states[p.id] == .stopped { manager.start(p) } } label: { Label("启动所选", systemImage: "play.fill") }.buttonStyle(SolidButton()).disabled(!manager.catalog.profiles.contains(where: { selected.contains($0.id) && manager.states[$0.id] == .stopped }) || manager.locked)
            Button { for p in manager.catalog.profiles where selected.contains(p.id) && manager.states[p.id] == .running { manager.stop(p) } } label: { Text("正常退出所选") }.buttonStyle(SolidButton()).disabled(!manager.catalog.profiles.contains(where: { selected.contains($0.id) && manager.states[$0.id] == .running }) || manager.locked)
        }.padding(.horizontal, 24).padding(.bottom, 10)
    }
    private func profileCard(_ p: BrowserProfile) -> some View {
        let state = manager.states[p.id] ?? .unknown
        let active = state == .running
        let busy = manager.busy.contains(p.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack { RoundedRectangle(cornerRadius: 10).fill(Palette.colors[p.color].opacity(0.12)).frame(width: 42, height: 42); Text(String(p.name.prefix(1))).font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.colors[p.color]) }
                Spacer()
                Toggle("选择 \(p.name)", isOn: Binding(get: { selected.contains(p.id) }, set: { if $0 { selected.insert(p.id) } else { selected.remove(p.id) } })).labelsHidden().toggleStyle(.checkbox).padding(.top, 2)
                Menu {
                    Button("编辑环境") { editing = p }.disabled(active || busy || state == .unknown)
                    Button("复制配置（新登录资料）") { manager.duplicate(p) }.disabled(manager.locked)
                    Button("重新生成指纹") { rotating = p }.disabled(active || busy || state == .unknown)
                    Button("打开资料目录") { manager.reveal(p) }
                    Divider()
                    Button("移除环境…", role: .destructive) { deleting = p }.disabled(active || busy || state == .unknown)
                } label: { Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 20, height: 18) }.menuStyle(.borderlessButton).fixedSize().disabled(manager.locked).accessibilityLabel("\(p.name)的操作")
            }
            Text(p.name).font(.system(size: 17, weight: .semibold)).lineLimit(1).padding(.top, 17)
            Text(p.notes.isEmpty ? "独立登录 · 独立存储" : p.notes).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1).padding(.top, 6).padding(.bottom, 20)
            VStack(spacing: 10) {
                detail("globe", p.timezone)
                detail("character.bubble", p.language)
                detail("network", p.networkLabel)
                detail("number", "指纹 \(p.seed)", mono: true)
            }
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 19)
            HStack {
                Circle().fill(active ? Palette.accent : state == .unknown ? Color.orange : Palette.secondary.opacity(0.4)).frame(width: 6, height: 6)
                Text(busy ? "处理中…" : active ? "正在运行" : state == .unknown ? "状态未知" : "已关闭").font(.system(size: 11)).foregroundStyle(active ? Palette.accent : Palette.secondary)
                Spacer()
                if busy { ProgressView().controlSize(.small).frame(height: 25) }
            }
            HStack(spacing: 8) {
                if active { Button { manager.stop(p) } label: { Label("正常退出", systemImage: "power").frame(maxWidth: .infinity) }.buttonStyle(SolidButton()).disabled(busy || manager.locked).accessibilityLabel("正常退出 \(p.name)").help("正常退出此环境，保留登录资料；其他环境继续运行") }
                Button { manager.start(p) } label: { Label(active ? "打开窗口" : "启动浏览器", systemImage: active ? "arrow.up.forward" : "play.fill").frame(maxWidth: .infinity) }.buttonStyle(SolidButton(primary: !active)).disabled(busy || state == .unknown || manager.locked).accessibilityLabel("\(active ? "打开" : "启动") \(p.name)")
            }.padding(.top, 14)
        }.padding(20).background(Palette.surface).clipShape(RoundedRectangle(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(selected.contains(p.id) ? Palette.accent.opacity(0.8) : Color.white.opacity(0.095), lineWidth: 1) }.shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
    }
    private func detail(_ icon: String, _ value: String, mono: Bool = false) -> some View {
        HStack(spacing: 10) { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(Palette.secondary.opacity(0.7)).frame(width: 15); Text(value).font(.system(size: 11, design: mono ? .monospaced : .default)).foregroundStyle(Color.white.opacity(0.7)).lineLimit(1); Spacer(minLength: 0) }.help(value)
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Palette.accent).padding(.bottom, 8)
            Text(manager.catalog.profiles.isEmpty ? "给每个身份，一个独立空间。" : "没有匹配的环境").font(.system(size: 22, weight: .medium))
            Text(manager.catalog.profiles.isEmpty ? "固定指纹与独立资料目录，让多个浏览器同时运行。\n登录状态自动保留，下次打开继续使用。" : "尝试其他关键词，或查看全部环境。").font(.system(size: 12)).lineSpacing(6).multilineTextAlignment(.center).foregroundStyle(Palette.secondary)
            if manager.catalog.profiles.isEmpty { Button { editing = manager.fresh() } label: { Label("创建第一个环境", systemImage: "plus") }.buttonStyle(SolidButton(primary: true)).padding(.top, 8).disabled(manager.locked) }
        }.frame(maxWidth: .infinity).frame(minHeight: 340).padding(40)
    }
    private var footer: some View {
        HStack(spacing: 8) { Image(systemName: "externaldrive").font(.system(size: 10)); Text(manager.banner).font(.system(size: 10)).lineLimit(2); Spacer(); Button { manager.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("刷新真实运行状态") }.foregroundStyle(Palette.secondary).padding(.horizontal, 28).padding(.vertical, 14).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("分境 / FenJing").font(.system(size: 25, weight: .semibold))
            Text("一个环境，一个独立的浏览器资料目录。\n多个环境可以同时运行，退出管理器不会关闭浏览器。")
            Text("内置 Fingerprint Chromium 引擎，安装后即可使用。\n环境管理、图形界面和启动器均由分境独立提供。\n浏览器环境资料保存在本机，不修改系统地区设置。")
            Text("环境隔离不会自动提供不同 IP。默认使用系统网络或 TUN，也可逐环境配置代理。不同指纹不代表匿名或账号安全保证。")
            Text("移除列表条目会保留资料目录。复制只复制配置，不复制 Cookie、密码或登录状态。")
            HStack { Button("开源许可") { if let path = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") { NSWorkspace.shared.open(path) } }.buttonStyle(.plain); Spacer(); Button("完成") { showAbout = false }.buttonStyle(SolidButton(primary: true)) }
        }.font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(6).padding(30).frame(width: 560).background(Palette.background).preferredColorScheme(.dark)
    }
}

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: BrowserProfile
    let isNew: Bool
    @ObservedObject var manager: EnvironmentManager
    @State private var seedText = ""
    @State private var validationError: String?
    @State private var proxyEnabled = false
    @State private var proxyType = "http"
    @State private var proxyHost = ""
    @State private var proxyPort = ""
    @State private var http1Only = false
    private let regions = [("美国 · 西部", "en-US", "America/Los_Angeles"), ("美国 · 东部", "en-US", "America/New_York"), ("英国", "en-GB", "Europe/London"), ("日本", "ja-JP", "Asia/Tokyo"), ("新加坡", "en-SG", "Asia/Singapore"), ("德国", "de-DE", "Europe/Berlin"), ("香港", "zh-TW", "Asia/Hong_Kong")]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 6) { Text(isNew ? "新建浏览器环境" : "编辑环境").font(.system(size: 24, weight: .semibold)); Text("独立保存登录资料，使用固定指纹启动。").font(.system(size: 12)).foregroundStyle(Palette.secondary) }; Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundColor(Palette.secondary) }
            Form {
                Section {
                    TextField("环境名称", text: $profile.name)
                    TextField("备注", text: $profile.notes)
                    TextField("起始页", text: $profile.startURL, prompt: Text("默认 https://www.google.com/"))
                    HStack { Text("环境颜色"); Spacer(); ForEach(0..<6, id: \.self) { index in Button { profile.color = index } label: { Circle().fill(Palette.colors[index]).frame(width: 18, height: 18).overlay { Circle().strokeBorder(Color.white, lineWidth: profile.color == index ? 2 : 0) } }.buttonStyle(.plain).accessibilityLabel("颜色 \(index + 1)") } }
                }
                Section("浏览器环境") {
                    Menu("快速填入地区") { ForEach(regions, id: \.0) { name, language, timezone in Button(name) { profile.language = language; profile.timezone = timezone } } }
                    Picker("语言", selection: $profile.language) { ForEach(BrowserProfile.languages, id: \.self) { Text($0).tag($0) } }
                    Picker("时区", selection: $profile.timezone) { ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { Text($0).tag($0) } }
                    HStack { TextField("指纹种子", text: $seedText); Button("随机") { var seed: UInt32; repeat { seed = UInt32.random(in: 1...UInt32.max) } while manager.catalog.profiles.contains(where: { $0.seed == seed }); seedText = String(seed) } }
                }
                Section("网络") {
                    Toggle("为此环境启用独立代理", isOn: $proxyEnabled)
                    if proxyEnabled {
                        Picker("代理类型", selection: $proxyType) { Text("HTTP").tag("http"); Text("HTTPS").tag("https"); Text("SOCKS5").tag("socks5") }.pickerStyle(.segmented)
                        TextField("代理主机", text: $proxyHost, prompt: Text("127.0.0.1 或 proxy.example.com"))
                        TextField("端口", text: $proxyPort, prompt: Text("7890"))
                        if proxyType != "socks5" {
                            Toggle("HTTP/1.1 兼容模式", isOn: $http1Only)
                            Text("Google 持续转圈或静态资源加载卡住时可尝试。仅影响此环境，可能降低并行加载速度；HTTPS 证书校验保持开启。").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Text("代理仅作用于当前环境；关闭时使用系统网络 / TUN。带密码代理请通过本机代理客户端转接。语言、时区请与你的出口地区对应。").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }.formStyle(.grouped).scrollContentBackground(.hidden).frame(height: 480)
            if let validationError { Text(validationError).font(.system(size: 11)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true).accessibilityLabel("保存错误：\(validationError)") }
            HStack { Text("每个环境首次打开时需单独登录。").font(.system(size: 11)).foregroundStyle(Palette.secondary); Spacer(); Button("取消") { dismiss() }.buttonStyle(SolidButton()); Button(isNew ? "创建环境" : "保存修改") { save() }.buttonStyle(SolidButton(primary: true)).keyboardShortcut(.defaultAction) }
        }.padding(26).frame(width: 600).background(Palette.background).foregroundColor(.white).preferredColorScheme(.dark).onAppear {
            seedText = String(profile.seed)
            http1Only = profile.http1Only == true
            if let proxy = try? BrowserProfile.proxyURL(profile.proxy) { proxyEnabled = true; proxyType = proxy.scheme == "socks5h" ? "socks5" : (proxy.scheme ?? "http"); proxyHost = proxy.host ?? ""; proxyPort = proxy.port.map(String.init) ?? "" }
        }
    }
    private func save() {
        guard let seed = UInt32(seedText.trimmingCharacters(in: .whitespacesAndNewlines)), seed > 0 else { validationError = "指纹种子必须是 1–4294967295 的整数。"; return }
        profile.seed = seed; profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines); profile.startURL = profile.startURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if proxyEnabled {
            let host = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let port = proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
            let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
            profile.proxy = "\(proxyType)://\(bracketed):\(port)"
        } else { profile.proxy = "" }
        profile.http1Only = proxyEnabled && proxyType != "socks5" && http1Only
        do { try profile.validate(); guard !manager.catalog.profiles.contains(where: { $0.id != profile.id && $0.seed == profile.seed }) else { throw AppFailure("此指纹种子已被其他环境使用。") }; if manager.save(profile) { dismiss() } else { validationError = manager.error; manager.error = nil } }
        catch { validationError = error.localizedDescription }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var manager: EnvironmentManager?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let root: URL
        // Test-only UI data is explicit and never reads the real catalog.
        if let i = CommandLine.arguments.firstIndex(of: "--ui-test-root"), CommandLine.arguments.count > i + 1 { root = URL(fileURLWithPath: CommandLine.arguments[i + 1]) }
        else { root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FenJing") }
        let manager = EnvironmentManager(root: root); self.manager = manager
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "分境 · FenJing"; window.minSize = NSSize(width: 980, height: 650); window.titlebarAppearsTransparent = true; window.isOpaque = false; window.backgroundColor = .clear
        window.styleMask.insert(.fullSizeContentView); window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = GlassRootView(rootView: MainView(manager: manager)); window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        let menu = NSMenu(); let application = NSMenuItem(); let submenu = NSMenu(); submenu.addItem(withTitle: "关于分境", action: #selector(about), keyEquivalent: ""); submenu.addItem(.separator()); submenu.addItem(withTitle: "退出分境", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); application.submenu = submenu; menu.addItem(application)
        let edit = NSMenuItem(); edit.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] { editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key) }; edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "分境 · FenJing", .applicationVersion: AppIdentity.version, .credits: NSAttributedString(string: "Independent browser environments. Built-in fingerprint engine.")]) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window?.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct FenJingMain {
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate; app.run(); _ = delegate
    }
}
