import Foundation

/// 自动锁屏（=拉起专注遮罩）的设置
final class AutoLockSettings {
    static let shared = AutoLockSettings()
    static let didChangeNotification = Notification.Name("AutoLockSettings.didChange")

    private let enabledKey = "MyTodo.autoLock.enabled"
    private let secondsKey = "MyTodo.autoLock.seconds"

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// 闲置秒数阈值，默认 30 秒
    var idleSeconds: Int {
        get {
            let n = UserDefaults.standard.integer(forKey: secondsKey)
            return n > 0 ? n : 30
        }
        set {
            UserDefaults.standard.set(max(5, newValue), forKey: secondsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// 菜单 preset
    static let presets: [(seconds: Int, title: String)] = [
        (10,  "10 秒"),
        (30,  "30 秒（默认）"),
        (60,  "1 分钟"),
        (120, "2 分钟"),
        (300, "5 分钟"),
        (600, "10 分钟"),
    ]

    var currentTitle: String {
        if !isEnabled { return "关闭" }
        let s = idleSeconds
        if let p = Self.presets.first(where: { $0.seconds == s }) { return p.title }
        return s < 60 ? "\(s) 秒" : "\(s / 60) 分钟"
    }
}
