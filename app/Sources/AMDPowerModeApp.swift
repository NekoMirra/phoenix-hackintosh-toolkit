import SwiftUI
import Foundation
import ServiceManagement

// MARK: - 模型

enum PowerMode: String, CaseIterable, Identifiable {
    case quiet, balanced, max, auto
    var id: String { rawValue }

    var title: String {
        switch self {
        case .quiet:    return "安静"
        case .balanced: return "均衡"
        case .max:      return "性能"
        case .auto:     return "自动"
        }
    }
    var subtitle: String {
        switch self {
        case .quiet:    return "15W · 65℃ 静音"
        case .balanced: return "35W · 85℃"
        case .max:      return "54W · 90℃"
        case .auto:     return "跟随系统"
        }
    }
    var symbol: String {
        switch self {
        case .quiet:    return "leaf.fill"
        case .balanced: return "equal.circle.fill"
        case .max:      return "bolt.fill"
        case .auto:     return "arrow.triangle.2.circlepath"
        }
    }
    var tint: Color {
        switch self {
        case .quiet:    return .green
        case .balanced: return .blue
        case .max:      return .orange
        case .auto:     return .gray
        }
    }
    /// 写入档位文件的标识（quiet 映射到 daemon 的 save）
    var fileKey: String {
        switch self {
        case .quiet: return "save"
        case .max:   return "max"
        case .balanced: return "balanced"
        case .auto:  return "auto"
        }
    }
}

// MARK: - 控制器

@MainActor
final class PowerController: ObservableObject {
    @Published var mode: PowerMode = .auto
    @Published var temperature: Double = 0
    @Published var powerSource: String = "交流电源"
    @Published var statusLine: String = "就绪"
    @Published var customPPT: Double = 35     // 瓦
    @Published var customTctl: Double = 85    // 摄氏度
    @Published var isCustom: Bool = false
    @Published var fanRPM: Int = 0
    @Published var fanBoost: Bool = false

    private let toolsDir = "/Users/mirra/WorkBuddy/2026-11-03-20-03-17/tools"
    private var pollTask: Task<Void, Never>?

    private var amdctl: String { toolsDir + "/amdctl" }
    private var smcread: String { toolsDir + "/smcread" }
    private var statePath: String { "/var/run/local.amd.pmsync.state" }

    private var modeFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AMDPowerMode/mode")
    }

    static let shared = PowerController()

    init() {
        // 只读轻量状态；耗时的读取放到 start() 的异步循环里
        loadFromStateFile()
    }

    deinit { pollTask?.cancel() }

    /// 视图出现后启动轮询（init 里做会与视图构建冲突，导致 AttributeGraph 崩溃）
    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snap = await Self.snapshot(toolsDir: self.toolsDir)
                self.apply(snap)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func apply(_ s: Snapshot) {
        temperature = s.temperature
        powerSource = s.powerSource
        fanRPM = s.fanRPM
        fanBoost = s.fanBoost
        if let line = s.status { statusLine = line }
    }

    // MARK: 读取（全部在后台线程，避免阻塞主线程）

    struct Snapshot: Sendable {
        var temperature: Double
        var powerSource: String
        var status: String?
        var fanRPM: Int
        var fanBoost: Bool
    }

    nonisolated static func snapshot(toolsDir: String) async -> Snapshot {
        await Task.detached(priority: .utility) {
            let smcread = toolsDir + "/smcread"
            var temp: Double = 0
            let out = runSync(smcread, ["TC0P"])
            if let r = out.range(of: "= ") {
                let v = out[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                temp = Double(v) ?? 0
            }
            var src = "未知"
            let batt = runSync("/usr/bin/pmset", ["-g", "batt"])
            if batt.contains("Battery Power") { src = "电池" }
            else if batt.contains("AC Power") { src = "交流电源" }

            var status: String? = nil
            if let s = try? String(contentsOfFile: "/var/run/local.amd.pmsync.state", encoding: .utf8) {
                let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/")
                if parts.count == 3 {
                    let name: String
                    switch parts[0] {
                    case "save": name = "安静"
                    case "balanced": name = "均衡"
                    case "max": name = "性能"
                    case "battery": name = "电池省电"
                    case "custom": name = "自定义"
                    default: name = String(parts[0])
                    }
                    let w = (Double(parts[1]) ?? 0) / 1000.0
                    status = String(format: "当前 %@ · %.0fW · %@℃", name, w, String(parts[2]))
                }
            }

            // 风扇：RPM 来自 EC 0x464/0x465（低字节在前），强冷状态看 0x751 bit6
            var rpm = 0
            var boost = false
            let ectool = toolsDir + "/ectool"
            let w = runSync(ectool, ["readw", "0x464"])
            if let r = w.range(of: "= 0x"), let v = Int(w[r.upperBound...].prefix(4), radix: 16) {
                rpm = ((v & 0xFF) << 8) | (v >> 8)
            }
            let b = runSync(ectool, ["read", "0x751"])
            if let r = b.range(of: "= 0x"), let v = Int(b[r.upperBound...].prefix(2), radix: 16) {
                boost = (v & 0x40) != 0
            }
            return Snapshot(temperature: temp, powerSource: src, status: status,
                            fanRPM: rpm, fanBoost: boost)
        }.value
    }

    nonisolated static func runSync(_ path: String, _ args: [String]) -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func loadFromStateFile() {
        // 从用户档位文件恢复 UI 选择
        guard let s = try? String(contentsOf: modeFileURL, encoding: .utf8) else { return }
        let lines = s.split(separator: "\n").map(String.init)
        guard let first = lines.first else { return }
        fanBoost = lines.contains("boost")
        switch first {
        case "save": mode = .quiet
        case "balanced": mode = .balanced
        case "max": mode = .max
        case "custom":
            mode = .balanced
            isCustom = true
            if lines.count > 1, let p = Double(lines[1]) { customPPT = p / 1000.0 }
            if lines.count > 2, let t = Double(lines[2]) { customTctl = t }
        default: mode = .auto
        }
    }

    // MARK: 开机自启

    @Published var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            statusLine = "登录项设置失败：\(error.localizedDescription)"
        }
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: 应用

    func apply(_ m: PowerMode) {
        mode = m
        isCustom = false
        writeModeFile(key: m.fileKey, ppt: nil, tctl: nil)
        statusLine = "正在切换…"
        if m == .auto {
            statusLine = "已交给系统自动调度"
            return
        }
        Task {
            let ok = await Self.setLimits(toolsDir: toolsDir,
                                          ppt: Self.preset(m).0, tctl: Self.preset(m).1)
            statusLine = ok ? "已应用 \(m.title) \(Self.preset(m).0 / 1000)W · \(Self.preset(m).1)℃"
                            : "应用失败，检查驱动是否加载"
        }
    }

    static func preset(_ m: PowerMode) -> (Int, Int) {
        switch m {
        case .quiet:    return (15000, 65)
        case .balanced: return (35000, 85)
        case .max:      return (54000, 90)
        case .auto:     return (0, 0)
        }
    }

    func applyCustom() {
        isCustom = true
        let pptMW = Int((customPPT * 1000).rounded())
        let tctl = Int(customTctl.rounded())
        writeModeFile(key: "custom", ppt: pptMW, tctl: tctl)
        statusLine = "正在切换…"
        Task {
            let ok = await Self.setLimits(toolsDir: toolsDir, ppt: pptMW, tctl: tctl)
            statusLine = ok
                ? String(format: "已应用自定义 %.0fW · %.0f℃", customPPT, customTctl)
                : "应用失败，检查驱动是否加载"
        }
    }

    nonisolated static func setLimits(toolsDir: String, ppt: Int, tctl: Int) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let amdctl = toolsDir + "/amdctl"
            guard FileManager.default.isExecutableFile(atPath: amdctl) else { return false }
            let tctlOK = runSync(amdctl, ["tctl", "\(tctl)"]).contains("0x01")
            let pptOK = runSync(amdctl, ["ppt", "\(ppt)"]).contains("0x01")
            return tctlOK && pptOK
        }.value
    }

    private func writeModeFile(key: String, ppt: Int?, tctl: Int?) {
        let dir = modeFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var text = key + "\n"
        if let p = ppt { text += "\(p)\n" }
        if let t = tctl { text += "\(t)\n" }
        if fanBoost { text += "boost\n" }
        try? text.write(to: modeFileURL, atomically: true, encoding: .utf8)
    }

    // MARK: 风扇强冷

    func setFanBoost(_ on: Bool) {
        fanBoost = on
        // 重写档位文件（保留当前档位/自定义值），追加或移除 boost 行
        let lines = (try? String(contentsOf: modeFileURL, encoding: .utf8))?
            .split(separator: "\n").map(String.init).filter { $0 != "boost" } ?? []
        var text = lines.joined(separator: "\n")
        if text.isEmpty { text = "auto" }
        if on { text += "\nboost" }
        text += "\n"
        try? text.write(to: modeFileURL, atomically: true, encoding: .utf8)
        statusLine = on ? "风扇强冷开启" : "风扇已恢复自动"
        Task {
            let curHex = await Self.readRegister(toolsDir: toolsDir, "0x751")
            var cur = 0
            if let r = curHex.range(of: "= 0x"), let v = Int(curHex[r.upperBound...].prefix(2), radix: 16) { cur = v }
            let nb = on ? (cur | 0x40) : (cur & ~0x40)
            _ = await Self.ecWrite(toolsDir: toolsDir, "0x751", String(format: "0x%02X", nb))
        }
    }

    nonisolated static func readRegister(toolsDir: String, _ addr: String) async -> String {
        await Task.detached(priority: .userInitiated) {
            runSync(toolsDir + "/ectool", ["read", addr])
        }.value
    }

    nonisolated static func ecWrite(toolsDir: String, _ addr: String, _ val: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            runSync(toolsDir + "/ectool", ["write", addr, val, "--i-understand"]).contains("成功")
        }.value
    }
}

// MARK: - 界面

struct ContentView: View {
    @ObservedObject private var pc = PowerController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            presetGrid
            customSection
            Divider()
            fanSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { pc.start() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CPU 温度")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(pc.temperature > 0 ? String(format: "%.1f", pc.temperature) : "--")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("℃")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Label(pc.powerSource, systemImage: pc.powerSource == "电池" ? "battery.75" : "powerplug.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(pc.isCustom ? "自定义" : pc.mode.title)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((pc.isCustom ? Color.purple : pc.mode.tint).opacity(0.16), in: Capsule())
                    .foregroundStyle(pc.isCustom ? Color.purple : pc.mode.tint)
            }
        }
    }

    private var presetGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(PowerMode.allCases) { m in
                Button {
                    pc.apply(m)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: m.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(m.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.title).font(.system(size: 12, weight: .semibold))
                            Text(m.subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(pc.mode == m && !pc.isCustom ? m.tint.opacity(0.14) : Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(pc.mode == m && !pc.isCustom ? m.tint.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("自定义")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(String(format: "%.0fW · %.0f℃", pc.customPPT, pc.customTctl))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("功耗").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                    Slider(value: $pc.customPPT, in: 8...80, step: 1)
                    Text(String(format: "%.0f", pc.customPPT)).font(.system(size: 10)).monospacedDigit().frame(width: 22, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Text("温度").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
                    Slider(value: $pc.customTctl, in: 60...100, step: 1)
                    Text(String(format: "%.0f", pc.customTctl)).font(.system(size: 10)).monospacedDigit().frame(width: 22, alignment: .trailing)
                }
            }

            Button {
                pc.applyCustom()
            } label: {
                Text("应用自定义")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }

    private var fanSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(pc.fanBoost ? Color.red : Color.teal)
            VStack(alignment: .leading, spacing: 1) {
                Text("风扇").font(.system(size: 11, weight: .semibold))
                Text(pc.fanRPM > 0 ? "\(pc.fanRPM) RPM" : "--")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                pc.setFanBoost(!pc.fanBoost)
            } label: {
                Text(pc.fanBoost ? "强冷中 · 点击关闭" : "强冷 100%")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(pc.fanBoost ? Color.red.opacity(0.16) : Color.primary.opacity(0.06))
                    )
                    .foregroundStyle(pc.fanBoost ? Color.red : Color.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(pc.statusLine.contains("失败") ? Color.red : Color.green)
                .frame(width: 6, height: 6)
            Text(pc.statusLine)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Toggle("开机自启", isOn: Binding(
                get: { pc.launchAtLogin },
                set: { pc.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(.system(size: 9))
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("退出")
        }
    }
}

// MARK: - 入口

@main
struct AMDPowerModeApp: App {
    init() {
        // 支持 --render <path>：离屏渲染界面为 PNG，用于开发期检查
        let args = CommandLine.arguments
        if args.contains("--enable-login") {
            MainActor.assumeIsolated { PowerController.shared.setLaunchAtLogin(true) }
            exit(0)
        }
        if args.contains("--disable-login") {
            MainActor.assumeIsolated { PowerController.shared.setLaunchAtLogin(false) }
            exit(0)
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            let path = args[i + 1]
            MainActor.assumeIsolated {
                UIRenderer.renderToPNG(path: path)
            }
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    @ObservedObject private var pc = PowerController.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
            if pc.temperature > 0 {
                Text("\(Int(pc.temperature.rounded()))°")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        }
        .onAppear { pc.start() }
    }
}

@MainActor
enum UIRenderer {
    static func renderToPNG(path: String) {
        let view = ContentView()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 300, height: 500)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
