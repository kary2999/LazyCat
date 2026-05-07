import AppKit

/// 全局窗口背景透明度管理（5% ~ 100%）
/// 值保存到 UserDefaults，变化时广播通知让 ContentViewController 刷新
final class WindowOpacity {
    static let shared = WindowOpacity()

    static let didChangeNotification = Notification.Name("WindowOpacity.didChange")

    private let key = "MyTodo.windowOpacityPercent"

    /// 当前透明度百分比（5~100）
    var percent: Int {
        let v = UserDefaults.standard.integer(forKey: key)
        return (v >= 5 && v <= 100) ? v : 100
    }

    /// 0.05 ~ 1.0
    var alpha: CGFloat { CGFloat(percent) / 100.0 }

    func setPercent(_ pct: Int) {
        let clamped = max(5, min(100, pct))
        UserDefaults.standard.set(clamped, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: clamped)
    }
}
