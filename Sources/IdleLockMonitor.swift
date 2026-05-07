import AppKit
import CoreGraphics

/// 系统级闲置监听：键盘 / 鼠标 / 触摸板都没动 → 闲置 N 秒后自动拉起专注遮罩
///
/// 用 CGEventSource.secondsSinceLastEventType 拿系统级 idle，
/// 不需要 Accessibility 权限，比 NSEvent.addGlobalMonitor 省电也更准。
final class IdleLockMonitor {
    static let shared = IdleLockMonitor()
    private init() {}

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        // 1 秒 tick 一次（已经够低频，不会有发热问题）
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        AppLog.log("IdleLockMonitor started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let s = AutoLockSettings.shared
        guard s.isEnabled else { return }
        // 已经在锁屏里了不重复触发
        if FullscreenMaskController.shared.isShown { return }

        let idle = systemIdleSeconds()
        if idle >= TimeInterval(s.idleSeconds) {
            AppLog.log("IdleLockMonitor: 闲置 \(Int(idle))s ≥ 阈值 \(s.idleSeconds)s → 拉起遮罩")
            FullscreenMaskController.shared.show()
        }
    }

    /// 系统级"距离上次任意输入事件"秒数。kCGAnyInputEventType 在 Swift 里是 ~0
    private func systemIdleSeconds() -> CFTimeInterval {
        let any = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
    }
}
