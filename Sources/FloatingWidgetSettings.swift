import AppKit

/// 桌面悬浮小猫的样式 + 尺寸设置
final class FloatingWidgetSettings {
    static let shared = FloatingWidgetSettings()

    static let didChangeNotification = Notification.Name("FloatingWidgetSettings.didChange")

    /// 可选样式 —— 默认是程序绘制的 24 帧走动猫，其它都是大号 emoji 栅格化（更可爱、更轻量）
    /// 悬浮形态 —— 程序化绘制（不用 emoji，不要圆形 logo 底盘）
    /// rawValue 0 为默认。
    enum CatStyle: Int, CaseIterable {
        case cat       = 0    // 🐱 白色走动小猫 — CatRenderer
        case orangeCat = 15   // 🐈 橘猫 — OrangeCatRenderer / 用户自带 cat-orange.png
        case penguin   = 14   // 🐧 招手企鹅 — PenguinRenderer / 用户自带 penguin.png
        case custom    = 16   // 🖼️ 自定义图片 — 用户从 NSOpenPanel 选的 custom.png

        var title: String {
            switch self {
            case .cat:       return "🐱 走动小猫（默认）"
            case .orangeCat: return "🐈 橘色小猫"
            case .penguin:   return "🐧 招手小企鹅"
            case .custom:    return "🖼️ 自定义图片"
            }
        }

        /// 兼容旧 UserDefaults
        static func fromStored(_ raw: Int) -> CatStyle {
            if raw == CatStyle.penguin.rawValue   { return .penguin }
            if raw == CatStyle.orangeCat.rawValue { return .orangeCat }
            if raw == CatStyle.custom.rawValue    { return .custom }
            return .cat
        }
    }

    /// 尺寸 10..100%（10 档），基准 100% = 72pt 圆球 panel。
    /// 比例越小，panel / badge / 字号都按比例缩。最小可点的 panel 不会低于 18pt
    struct Size: Equatable {
        let percent: Int          // 10..100，按 10 取整

        static let presets: [Size] = (1...10).map { Size(percent: $0 * 10) }
        static let `default` = Size(percent: 100)

        var title: String {
            percent == 100 ? "100%（默认）" : "\(percent)%"
        }
        var scale: CGFloat { CGFloat(percent) / 100.0 }

        /// 整个悬浮 panel 的边长 (pt)
        var panelSize: CGFloat {
            max(18, 72.0 * scale)
        }
        /// 红色未完成徽章直径
        var badgeSize: CGFloat {
            max(7, 18.0 * scale)
        }
        /// 徽章里数字字号
        var badgeFontSize: CGFloat {
            max(6, 10.0 * scale)
        }

        static func clamp(_ pct: Int) -> Size {
            // 先按 10 对齐，再夹到 [10, 100]
            let r = max(10, min(100, (pct / 10) * 10))
            return Size(percent: r)
        }
    }

    // MARK: persistence

    private let styleKey = "MyTodo.floatStyle"
    private let sizeKey  = "MyTodo.floatSize"
    private let alphaKey = "MyTodo.floatAlpha"   // 0.3 ~ 1.0，仅作用于猫/企鹅本体，不影响小红点
    private let shakeKey = "MyTodo.floatShakeStyle"

    /// 打字时悬浮窗的抖动方式（5 档）
    enum ShakeStyle: Int, CaseIterable {
        case off       = 0   // 不抖
        case vSoft     = 1   // 上下 · 轻
        case vHard     = 2   // 上下 · 重
        case hSoft     = 3   // 左右 · 轻
        case hHard     = 4   // 左右 · 重

        var title: String {
            switch self {
            case .off:   return "关闭抖动"
            case .vSoft: return "上下 · 轻（默认）"
            case .vHard: return "上下 · 重"
            case .hSoft: return "左右 · 轻"
            case .hHard: return "左右 · 重"
            }
        }
        var keyPath: String {
            switch self {
            case .off:           return ""
            case .vSoft, .vHard: return "transform.translation.y"
            case .hSoft, .hHard: return "transform.translation.x"
            }
        }
        /// 单次抖动的最大像素偏移
        var amount: CGFloat {
            switch self {
            case .off:           return 0
            case .vSoft, .hSoft: return -3
            case .vHard, .hHard: return -10
            }
        }
        /// 一次抖动的总时长
        var duration: CFTimeInterval {
            switch self {
            case .vSoft, .hSoft: return 0.10
            case .vHard, .hHard: return 0.18
            case .off:           return 0
            }
        }
    }

    var style: CatStyle {
        let v = UserDefaults.standard.integer(forKey: styleKey)
        return CatStyle.fromStored(v)
    }
    func setStyle(_ s: CatStyle) {
        UserDefaults.standard.set(s.rawValue, forKey: styleKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    var size: Size {
        // 兼容旧值：旧版本存的是 100/50/30；新版本存任意 10..100，对齐到 10
        let v = UserDefaults.standard.object(forKey: sizeKey) as? Int ?? 100
        return Size.clamp(v)
    }
    func setSize(_ s: Size) {
        UserDefaults.standard.set(s.percent, forKey: sizeKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// 悬浮动画体的不透明度。**小红点徽章不受其影响**（在视图里显式 alphaValue=1）
    var alpha: CGFloat {
        let v = UserDefaults.standard.object(forKey: alphaKey) as? Double ?? 1.0
        return CGFloat(max(0.3, min(1.0, v)))
    }
    func setAlpha(_ a: CGFloat) {
        let clamped = max(0.3, min(1.0, a))
        UserDefaults.standard.set(Double(clamped), forKey: alphaKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// 当前抖动配置（默认 .vSoft = 上下 · 轻）
    var shakeStyle: ShakeStyle {
        let v = UserDefaults.standard.object(forKey: shakeKey) as? Int ?? ShakeStyle.vSoft.rawValue
        return ShakeStyle(rawValue: v) ?? .vSoft
    }
    func setShakeStyle(_ s: ShakeStyle) {
        UserDefaults.standard.set(s.rawValue, forKey: shakeKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// 透明度档位预设（菜单用）
    static let alphaPresets: [(label: String, value: CGFloat)] = [
        ("100%（不透明）", 1.0),
        ("90%", 0.9),
        ("80%", 0.8),
        ("70%", 0.7),
        ("60%", 0.6),
        ("50%", 0.5),
        ("40%", 0.4),
        ("30%（最透明）", 0.3),
    ]
}
