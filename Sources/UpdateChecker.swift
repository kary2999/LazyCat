import AppKit
import Foundation

final class UpdateChecker {

    static let shared = UpdateChecker()

    /// version.json 地址 — 每次 CI 发布时自动更新
    static let manifestURL = "https://github.com/kary2999/LazyCat/releases/latest/download/version.json"

    /// 轮询间隔（秒）
    private let interval: TimeInterval = 60

    private var timer: Timer?
    private var isShowing = false   // 防止弹框叠加

    private init() {}

    // MARK: - Public

    /// 启动后延迟 5s 首检，之后每 60s 轮询一次（静默，有新版本才弹框）
    func startPolling() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.fetch(manual: false)
            self?.scheduleTimer()
        }
    }

    /// 菜单手动触发 — 无论有没有新版本都给提示
    func checkManually() {
        fetch(manual: true)
    }

    // MARK: - Private

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.fetch(manual: false)
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func fetch(manual: Bool) {
        guard let url = URL(string: Self.manifestURL) else {
            if manual { showAlert(title: "检查失败", message: "更新地址无效") }
            return
        }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("LazyCat-UpdateChecker", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                if manual {
                    DispatchQueue.main.async {
                        self.showAlert(title: "检查失败", message: error.localizedDescription)
                    }
                }
                return
            }

            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                let remoteVersion  = json["version"],
                // 支持 "url" 或 "download_url" 两种字段名
                let downloadString = json["url"] ?? json["download_url"],
                let downloadURL    = URL(string: downloadString)
            else {
                if manual {
                    DispatchQueue.main.async {
                        self.showAlert(title: "检查失败", message: "响应格式无效")
                    }
                }
                return
            }

            // 支持 "notes" 或 "release_notes" 两种字段名
            let notes = json["notes"] ?? json["release_notes"] ?? ""
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            DispatchQueue.main.async {
                if self.isNewer(remoteVersion, than: current) {
                    self.showUpdateAlert(remoteVersion: remoteVersion,
                                        releaseNotes: notes,
                                        downloadURL: downloadURL)
                } else if manual {
                    self.showAlert(title: "已是最新版本",
                                  message: "当前版本 \(current) 已是最新。")
                }
            }
        }.resume()
    }

    private func isNewer(_ remote: String, than current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        let count = max(r.count, c.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv != cv { return rv > cv }
        }
        return false
    }

    private func showUpdateAlert(remoteVersion: String, releaseNotes: String, downloadURL: URL) {
        guard !isShowing else { return }
        isShowing = true
        let alert = NSAlert()
        alert.messageText = "发现新版本 v\(remoteVersion)"
        alert.informativeText = releaseNotes.isEmpty ? "点击「立即更新」下载最新安装包。" : releaseNotes
        alert.addButton(withTitle: "立即更新")
        alert.addButton(withTitle: "稍后再说")
        let result = alert.runModal()
        isShowing = false
        if result == .alertFirstButtonReturn {
            NSWorkspace.shared.open(downloadURL)
        }
    }

    private func showAlert(title: String, message: String) {
        guard !isShowing else { return }
        isShowing = true
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
        isShowing = false
    }
}
