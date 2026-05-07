import AppKit

/// 全屏遮罩的可调设置：背景不透明度 10..100%、字号档位
final class MaskSettings {
    static let shared = MaskSettings()

    static let didChangeNotification = Notification.Name("MaskSettings.didChange")

    private let pctKey = "MyTodo.maskOpacityPercent"
    private let fontKey = "MyTodo.maskFontSizeTag"   // Int: 0=小 1=中 2=大 3=超大

    enum FontSize: Int, CaseIterable {
        case small = 0, medium = 1, large = 2, huge = 3

        var title: String {
            switch self {
            case .small:  return "小"
            case .medium: return "中（默认）"
            case .large:  return "大"
            case .huge:   return "超大"
            }
        }

        /// 时钟主文字号（右下角显示，比原中央版本小很多）
        var clockSize: CGFloat {
            switch self {
            case .small:  return 28
            case .medium: return 40
            case .large:  return 56
            case .huge:   return 76
            }
        }
        /// 任务文字号
        var taskSize: CGFloat {
            switch self {
            case .small:  return 13
            case .medium: return 16
            case .large:  return 20
            case .huge:   return 26
            }
        }
        /// 日期文字号
        var dateSize: CGFloat {
            switch self {
            case .small:  return 11
            case .medium: return 13
            case .large:  return 16
            case .huge:   return 20
            }
        }
    }

    /// 0..100（默认 82）。0% = 完全透明（仍有毛玻璃，但黑色暗化层 alpha=0）
    var opacityPercent: Int {
        // 用 object 拿 raw 值（int 默认 0 会被误判为 "未设置"）
        if let raw = UserDefaults.standard.object(forKey: pctKey) as? Int,
           raw >= 0 && raw <= 100 {
            return raw
        }
        return 82
    }
    var alpha: CGFloat { CGFloat(opacityPercent) / 100.0 }

    func setOpacity(_ pct: Int) {
        let c = max(0, min(100, pct))
        UserDefaults.standard.set(c, forKey: pctKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    var fontSize: FontSize {
        let raw = UserDefaults.standard.object(forKey: fontKey) as? Int ?? FontSize.medium.rawValue
        return FontSize(rawValue: raw) ?? .medium
    }

    func setFontSize(_ f: FontSize) {
        UserDefaults.standard.set(f.rawValue, forKey: fontKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
