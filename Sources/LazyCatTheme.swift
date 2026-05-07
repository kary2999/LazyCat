import AppKit

/// LazyCat · Style B 治愈系暖橘 · 严格 token
///
/// 全 app 统一调色板。所有 NSView / NSTextField / NSButton 必须从这里取色，
/// 禁止再用 .labelColor / .windowBackgroundColor / .textBackgroundColor / .secondaryLabelColor
/// 等 system semantic color —— 那些会跟系统暗色模式跑色，导致黑底白字 bug。
enum LazyCatTheme {

    // MARK: - 背景层（4 层，深→浅）

    /// 窗口最外层 奶油 #fff7ec
    static let bgPage    = NSColor(red: 1.00, green: 0.97, blue: 0.93, alpha: 1)
    /// 卡片白 #ffffff
    static let bgCard    = NSColor.white
    /// 输入框 / chip / button-secondary surface #fff3e0
    static let bgSurface = NSColor(red: 1.00, green: 0.95, blue: 0.88, alpha: 1)
    /// 标题栏 / sidebar #ffefdc
    static let bgSoft    = NSColor(red: 1.00, green: 0.94, blue: 0.86, alpha: 1)

    // 兼容旧字段名（已经用了的地方继续工作）
    static var bg: NSColor { bgPage }

    // MARK: - 文字（4 层，深→浅）

    /// 主文字（最深，跟白底反差最大）#2c2418
    static let tx1 = NSColor(red: 0.17, green: 0.14, blue: 0.09, alpha: 1)
    /// 副文字 / 标签 #6b5f48
    static let tx2 = NSColor(red: 0.42, green: 0.37, blue: 0.28, alpha: 1)
    /// 弱文字 / 时间戳 #a08f6f
    static let tx3 = NSColor(red: 0.63, green: 0.56, blue: 0.44, alpha: 1)
    /// 占位符 / 禁用 #c1ad8a
    static let tx4 = NSColor(red: 0.76, green: 0.68, blue: 0.54, alpha: 1)

    // 兼容旧字段名
    static var textPrimary: NSColor { tx1 }
    static var textSec: NSColor     { tx2 }
    static var textTer: NSColor     { tx3 }

    // MARK: - 强调色

    /// 暖橙主色 #FF8C42
    static let accent      = NSColor(red: 1.00, green: 0.55, blue: 0.26, alpha: 1)
    /// 深橙（hover）#E0762D
    static let accentDark  = NSColor(red: 0.88, green: 0.46, blue: 0.18, alpha: 1)
    /// 黄油辅 #FFD082
    static let accentLight = NSColor(red: 1.00, green: 0.82, blue: 0.51, alpha: 1)
    /// 薄荷 - 完成 / 今日柱 #2e7d6b
    static let mint        = NSColor(red: 0.18, green: 0.49, blue: 0.42, alpha: 1)
    /// 危险 - 删除 / T0 #c0392b
    static let red         = NSColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1)
    /// T2 / 成功 #2e7d32
    static let green       = NSColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)
    /// 奖牌（统计窗口用）
    static let gold        = NSColor(red: 1.00, green: 0.84, blue: 0.20, alpha: 1)
    static let silver      = NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)
    static let bronze      = NSColor(red: 0.80, green: 0.50, blue: 0.20, alpha: 1)

    // MARK: - 边框

    /// 主边框（暖米）#f5dfb5
    static let border1 = NSColor(red: 0.96, green: 0.87, blue: 0.71, alpha: 1)
    /// 加粗边框 #e9d4a4
    static let border2 = NSColor(red: 0.91, green: 0.83, blue: 0.64, alpha: 1)
    static var border: NSColor { border1 }

    // MARK: - 锁屏专用

    /// 锁屏深棕底 #2c1810
    static let maskDark  = NSColor(red: 0.17, green: 0.09, blue: 0.06, alpha: 1)
    /// 锁屏奶油文字 #ffe7c0
    static let maskCream = NSColor(red: 1.00, green: 0.91, blue: 0.75, alpha: 1)

    // MARK: - 字体

    static func body(_ size: CGFloat = 13.5, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }
    static func mono(_ size: CGFloat = 12, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - 圆角

    static let cornerSm: CGFloat = 6
    static let cornerMd: CGFloat = 10
    static let cornerLg: CGFloat = 14
    static let cornerXl: CGFloat = 18

    // MARK: - 阴影

    static func cardShadow(on layer: CALayer) {
        layer.shadowColor = NSColor(red: 0.7, green: 0.43, blue: 0.12, alpha: 0.08).cgColor
        layer.shadowRadius = 6
        layer.shadowOffset = .init(width: 0, height: -2)
        layer.shadowOpacity = 1
        layer.masksToBounds = false
    }
    static func smallShadow(on layer: CALayer) {
        layer.shadowColor = NSColor(red: 0.7, green: 0.43, blue: 0.12, alpha: 0.06).cgColor
        layer.shadowRadius = 3
        layer.shadowOffset = .init(width: 0, height: -1)
        layer.shadowOpacity = 1
        layer.masksToBounds = false
    }
    static func accentShadow(on layer: CALayer) {
        layer.shadowColor = accent.withAlphaComponent(0.3).cgColor
        layer.shadowRadius = 6
        layer.shadowOffset = .init(width: 0, height: -2)
        layer.shadowOpacity = 1
        layer.masksToBounds = false
    }

    // MARK: - 优先级颜色

    static func priorityColor(_ p: Priority) -> NSColor {
        switch p {
        case .top:  return red
        case .mid:  return accent
        case .low:  return green
        case .none: return tx4
        }
    }

    // 兼容旧 API
    static func pillColor(forPriority raw: Int) -> (bg: NSColor, fg: NSColor) {
        switch raw {
        case 3: return (NSColor(red: 1.00, green: 0.85, blue: 0.85, alpha: 1), red)
        case 2: return (NSColor(red: 1.00, green: 0.91, blue: 0.75, alpha: 1), NSColor(red: 0.72, green: 0.37, blue: 0.00, alpha: 1))
        case 1: return (NSColor(red: 0.84, green: 0.93, blue: 0.86, alpha: 1), green)
        default: return (NSColor(red: 0.93, green: 0.93, blue: 0.93, alpha: 1), tx2)
        }
    }

    // MARK: - 工厂函数

    /// 一个圆角白卡片 view（带柔阴影 + 边框）
    static func makeCard() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = bgCard.cgColor
        v.layer?.cornerRadius = cornerMd
        v.layer?.borderWidth = 1.5
        v.layer?.borderColor = border1.cgColor
        if let l = v.layer { smallShadow(on: l) }
        return v
    }

    // MARK: - 4 种按钮工厂

    enum BtnStyle { case primary, secondary, tertiary, danger, dangerGhost }

    static func makeButton(title: String, style: BtnStyle, target: Any?, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.isBordered = false
        b.wantsLayer = true
        b.translatesAutoresizingMaskIntoConstraints = false
        applyButtonStyle(b, style: style)
        b.attributedTitle = makeBtnTitle(title, style: style)
        return b
    }

    static func applyButtonStyle(_ b: NSButton, style: BtnStyle) {
        b.wantsLayer = true
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.focusRingType = .none            // ★ 关焦点环（按钮外那圈白）
        b.layer?.cornerRadius = cornerSm
        b.layer?.masksToBounds = false      // 让 shadow 能溢出去
        switch style {
        case .primary:
            b.layer?.backgroundColor = accent.cgColor
            b.layer?.borderWidth = 0
            // 较弱的橙色 shadow，避免按钮看着糊
            b.layer?.shadowColor = accent.withAlphaComponent(0.35).cgColor
            b.layer?.shadowRadius = 4
            b.layer?.shadowOffset = .init(width: 0, height: -1)
            b.layer?.shadowOpacity = 1
        case .secondary:
            b.layer?.backgroundColor = bgCard.cgColor
            b.layer?.borderWidth = 1.5
            b.layer?.borderColor = border2.cgColor
            b.layer?.shadowOpacity = 0
        case .tertiary:
            b.layer?.backgroundColor = NSColor.clear.cgColor
            b.layer?.borderWidth = 0
            b.layer?.shadowOpacity = 0
        case .danger:
            b.layer?.backgroundColor = red.cgColor
            b.layer?.borderWidth = 0
            b.layer?.shadowOpacity = 0
        case .dangerGhost:
            b.layer?.backgroundColor = bgCard.cgColor
            b.layer?.borderWidth = 1.5
            b.layer?.borderColor = red.cgColor
            b.layer?.shadowOpacity = 0
        }
    }

    static func makeBtnTitle(_ title: String, style: BtnStyle) -> NSAttributedString {
        let color: NSColor
        switch style {
        case .primary, .danger:    color = .white
        case .secondary:           color = tx1
        case .tertiary:            color = accent
        case .dangerGhost:         color = red
        }
        return NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: body(12.5, weight: .medium),
        ])
    }
}
