import AppKit
import UserNotifications

extension Notification.Name {
    /// 触发汇总提醒时投递，object = unfinished count (Int)
    static let reminderFired = Notification.Name("MyTodo.reminderFired")
}

/// 提醒引擎 —— v1.3 改版
///   - **不再** 逐条任务弹 modal / Dock 弹跳 / 系统通知
///   - 每 N 分钟扫一次，如有未完成任务就投 1 条汇总通知：
///       「📋 你还有 N 个未完成任务」
///   - 间隔可配置：30 分钟 / 1 小时（默认）/ 2 小时 / 4 小时 / 关闭
final class ReminderEngine: NSObject {
    static let shared = ReminderEngine()

    static let didChangeIntervalNotification = Notification.Name("ReminderEngine.didChangeInterval")

    private let intervalKey = "MyTodo.digestIntervalMinutes"
    private let defaultInterval = 60

    /// 分钟数；0 = 关闭
    var intervalMinutes: Int {
        let v = UserDefaults.standard.object(forKey: intervalKey) as? Int
        return v ?? defaultInterval
    }

    func setInterval(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: intervalKey)
        restartTimer()
        NotificationCenter.default.post(name: Self.didChangeIntervalNotification, object: nil)
    }

    private var timer: Timer?
    private var lastDigestAt: Date?

    func start() {
        requestAuthorization()
        restartTimer()
    }

    private func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func restartTimer() {
        timer?.invalidate(); timer = nil
        let m = intervalMinutes
        guard m > 0 else {
            AppLog.log("ReminderEngine: digest disabled")
            return
        }
        // 每 30 秒检查一次，到点就 digest（避免 app 睡眠后错过精确时刻）
        let t = Timer(timeInterval: 30, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // 启动后先立刻评估一次（但不一定 fire —— 有 cooldown）
        tick()
        AppLog.log("ReminderEngine: digest every \(m) min")
    }

    @objc private func tick() {
        let m = intervalMinutes
        guard m > 0 else { return }
        let now = Date()
        let cooldown = TimeInterval(m * 60)
        if let last = lastDigestAt, now.timeIntervalSince(last) < cooldown { return }

        let count = Store.shared.data.tasks.filter { !$0.completed }.count
        guard count > 0 else {
            // 没有未完成 ⇒ 不打扰；下次到点再看
            lastDigestAt = now
            return
        }

        fireDigest(count: count, at: now)
        lastDigestAt = now
    }

    private func fireDigest(count: Int, at now: Date) {
        AppLog.log("ReminderEngine.digest count=\(count)")

        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        let content = UNMutableNotificationContent()
        content.title = "📋 未完成任务汇总"
        content.body = "截至 \(hm.string(from: now))，你还有 \(count) 个未完成任务"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "mytodo.digest",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)

        // 悬浮窗猫咪抖一抖
        NotificationCenter.default.post(name: .reminderFired, object: count)
    }

    /// 手动立即触发一次 digest（菜单里的"立刻汇总一次"）
    func fireNow() {
        lastDigestAt = nil   // 绕过 cooldown
        tick()
    }
}

extension ReminderEngine: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        if let delegate = NSApp.delegate as? AppDelegate {
            DispatchQueue.main.async { delegate.showMainWindow() }
        }
        completion()
    }
}
