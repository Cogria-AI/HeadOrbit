import AppKit
import os

/// 自动更新：从 GitHub Releases 拿最新版 DMG，先把新 .app 解到临时目录；
/// 用户确认重启后，由一个小脚本等本进程退出、替换原 .app、再打开新版本。
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate
        case downloading(String)
        case ready(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var download: Download?
    private let log = Logger(subsystem: "com.cogria.HeadOrbit", category: "update")
    private static let latestURL = URL(string: "https://api.github.com/repos/Cogria-AI/HeadOrbit/releases/latest")!

    /// 启动时调用的那次 interactive = false：后台下好后弹窗问要不要重启；
    /// 设置里手动点的那次只更新页面状态，由用户自己点重启
    func check(interactive: Bool) {
        switch state {
        case .checking, .downloading, .ready: return
        default: break
        }
        state = .checking
        Task {
            do {
                let release = try await Self.fetchLatest()
                guard Self.isNewer(release.version, than: StatusText.version) else {
                    log.notice("up to date: latest \(release.version, privacy: .public)")
                    state = .upToDate
                    return
                }
                state = .downloading(release.version)
                download = try await Self.fetch(release)
                state = .ready(release.version)
                log.notice("update \(release.version, privacy: .public) staged")
                if !interactive { promptRestart(release.version) }
            } catch {
                log.error("update failed: \(error.localizedDescription, privacy: .public)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    func installAndRelaunch() {
        guard case .ready = state, let download else { return }
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        // 被系统随机化路径运行，或所在目录没写权限：替换不了，打开 DMG 让用户自己拖
        guard !target.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: parent.path) else {
            NSWorkspace.shared.open(download.dmg)
            return
        }
        // 先复制到旁边的 .new，成功了才删旧的，中途失败不会把 App 弄没
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.new"
        /usr/bin/ditto "$1" "$2.new" || exit 1
        rm -rf "$2" && mv "$2.new" "$2"
        /usr/bin/open "$2"
        rm -rf "$3"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", download.app.path, target.path, download.dir.path]
        do {
            try p.run()
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        NSApplication.shared.terminate(nil)
    }

    private func promptRestart(_ version: String) {
        let l10n = L10n.shared
        let alert = NSAlert()
        alert.messageText = l10n.t("update.readyTitle", version)
        alert.informativeText = l10n.t("update.readyBody")
        alert.addButton(withTitle: l10n.t("update.restart"))
        alert.addButton(withTitle: l10n.t("update.later"))
        NSApplication.shared.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { installAndRelaunch() }
    }

    // MARK: - 下载与解包

    private struct Release {
        let version: String
        let dmgURL: URL
    }

    private struct Download {
        let dir: URL
        let dmg: URL
        let app: URL
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    private static func fetchLatest() async throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable { let name: String; let browser_download_url: URL }
            let tag_name: String
            let assets: [Asset]
        }
        var req = URLRequest(url: latestURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("HeadOrbit/\(StatusText.version)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHub API returned \((resp as? HTTPURLResponse)?.statusCode ?? 0)") }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let dmg = payload.assets.first(where: { $0.name.hasSuffix(".dmg") }) else { throw UpdateError("No DMG in release \(payload.tag_name)") }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return Release(version: version, dmgURL: dmg.browser_download_url)
    }

    private static func fetch(_ release: Release) async throws -> Download {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("HeadOrbit-update-\(release.version)")
        try? fm.removeItem(at: dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let (tmp, resp) = try await URLSession.shared.download(from: release.dmgURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("Download returned \((resp as? HTTPURLResponse)?.statusCode ?? 0)") }
        let dmg = dir.appendingPathComponent("HeadOrbit.dmg")
        try fm.moveItem(at: tmp, to: dmg)

        let mount = dir.appendingPathComponent("mnt")
        let app = dir.appendingPathComponent("HeadOrbit.app")
        try await Task.detached {
            try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
            defer { try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
            try run("/usr/bin/ditto", [mount.appendingPathComponent("HeadOrbit.app").path, app.path])
        }.value

        // 确认解出来的确实是 HeadOrbit，且版本和 Release 标签一致
        let info = Bundle(url: app)?.infoDictionary
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info?["CFBundleShortVersionString"] as? String == release.version else {
            throw UpdateError("Downloaded app does not match release \(release.version)")
        }
        return Download(dir: dir, dmg: dmg, app: app)
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("\(tool) exited with \(p.terminationStatus)") }
    }

    /// 按数字逐段比较，"2.10.0" > "2.9.1"
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
