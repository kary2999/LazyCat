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

    // MARK: - 工作时间段（只在上班时间才启用自动锁屏）

    private let workHoursEnabledKey = "MyTodo.autoLock.workHoursEnabled"
    private let workStartHourKey    = "MyTodo.autoLock.workStartHour"
    private let workEndHourKey      = "MyTodo.autoLock.workEndHour"

    /// 是否仅在工作时段内自动锁屏（下班后自动解除遮罩）
    var workHoursOnly: Bool {
        get { UserDefaults.standard.object(forKey: workHoursEnabledKey) as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: workHoursEnabledKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// 工作开始时间（小时，24h），默认 9
    var workStartHour: Int {
        get {
            let n = UserDefaults.standard.integer(forKey: workStartHourKey)
            return n > 0 ? n : 9
        }
        set {
            UserDefaults.standard.set(max(0, min(23, newValue)), forKey: workStartHourKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// 工作结束时间（小时，24h），默认 18
    var workEndHour: Int {
        get {
            let n = UserDefaults.standard.integer(forKey: workEndHourKey)
            return n > 0 ? n : 18
        }
        set {
            UserDefaults.standard.set(max(0, min(23, newValue)), forKey: workEndHourKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    /// 当前是否处于工作时段内
    var isInWorkHours: Bool {
        guard workHoursOnly else { return true }   // 未限制时段 → 全天有效
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= workStartHour && hour < workEndHour
    }
}
