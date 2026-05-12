import AppKit

/// 打字统计窗口：
///   · 上半区：最近 30 天 Top 5 按键排名（带条形 + 计数）
///   · 下半区：最近 30 天每日打字总数（大字数字 + 柱状图）
final class TypingStatsWindowController: NSWindowController {

    static let shared = TypingStatsWindowController()

    private let statsView = TypingStatsView()

    private convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        win.title = "打字统计 · 最近 30 天"
        win.minSize = NSSize(width: 640, height: 480)
        win.isReleasedWhenClosed = false
        win.center()
        // 固定走 light 外观 —— 用户要求"白底黑字"，不跟随系统暗色模式
        win.appearance = NSAppearance(named: .aqua)
        self.init(window: win)
        win.contentView = statsView
    }

    func present() {
        statsView.reload()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 内容视图

private final class TypingStatsView: NSView {

    private let titleLabel    = NSTextField(labelWithString: "")
    private let totalBigLabel = NSTextField(labelWithString: "0")
    private let totalSubLabel = NSTextField(labelWithString: "今日按键数")

    // Top 5 区域
    private let topTitleLabel = NSTextField(labelWithString: "🏆  最近 30 天 · TOP 5")
    private let topStack      = NSStackView()

    // 日柱状图
    private let chartTitleLabel = NSTextField(labelWithString: "📊  每日总按键 · 最近 30 天")
    private let chartView       = DailyBarChartView()

    // 操作按钮
    private let refreshBtn      = NSButton(title: "刷新", target: nil, action: nil)
    private let clearBtn        = NSButton(title: "清空全部历史", target: nil, action: nil)
    // 权限状态
    private let permStatusLbl   = NSTextField(labelWithString: "")
    private let resetPermBtn    = NSButton(title: "重置权限", target: nil, action: nil)

    // ★ Style B · 治愈系暖橘 调色板（接 LazyCatTheme）
    fileprivate static let bgColor       = LazyCatTheme.bg                                  // 奶油
    fileprivate static let bgCard        = LazyCatTheme.bgCard                              // 白
    fileprivate static let bgSurface     = LazyCatTheme.bgSurface                           // 浅米
    fileprivate static let textPrimary   = LazyCatTheme.textPrimary                         // 暖深棕
    fileprivate static let textSecondary = LazyCatTheme.textSec                             // 暖中棕
    fileprivate static let textTertiary  = LazyCatTheme.textTer                             // 暖弱棕
    fileprivate static let separator     = LazyCatTheme.border                              // 暖边线
    fileprivate static let accent        = LazyCatTheme.accent                              // 暖橙
    fileprivate static let accentLight   = LazyCatTheme.accentLight                         // 黄油
    fileprivate static let accentToday   = NSColor(red: 0.39, green: 0.69, blue: 0.49, alpha: 1)  // 薄荷绿（今日柱子）
    fileprivate static let gold          = LazyCatTheme.gold
    fileprivate static let silver        = LazyCatTheme.silver
    fileprivate static let bronze        = LazyCatTheme.bronze

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Self.bgColor.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    // ★ 顶部状态卡（暖橙渐变底）
    private let topCard = NSView()

    private func build() {
        // ── 顶部状态卡：渐变底 ──
        topCard.wantsLayer = true
        topCard.layer?.cornerRadius = LazyCatTheme.cornerLg
        let gradient = CAGradientLayer()
        gradient.colors = [
            Self.accentLight.cgColor,
            Self.bgSurface.cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = LazyCatTheme.cornerLg
        topCard.layer?.insertSublayer(gradient, at: 0)
        topCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topCard)

        // ── 顶部：今日大数字 ──
        titleLabel.stringValue = "🐾 今天打了好多字呀"
        titleLabel.font = LazyCatTheme.body(14, weight: .heavy)
        titleLabel.textColor = Self.textPrimary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        totalBigLabel.font = .monospacedDigitSystemFont(ofSize: 56, weight: .heavy)
        totalBigLabel.textColor = Self.accent
        totalBigLabel.alignment = .right
        totalBigLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(totalBigLabel)

        totalSubLabel.stringValue = "今日按键 · 加油加油！"
        totalSubLabel.font = LazyCatTheme.body(11, weight: .semibold)
        totalSubLabel.textColor = Self.textSecondary
        totalSubLabel.alignment = .left
        totalSubLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(totalSubLabel)

        // ── Top 5 ──
        topTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        topTitleLabel.textColor = Self.textPrimary
        topTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topTitleLabel)

        topStack.orientation = .vertical
        topStack.alignment = .leading
        topStack.distribution = .fillEqually
        topStack.spacing = 4
        topStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topStack)

        // ── 柱状图 ──
        chartTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        chartTitleLabel.textColor = Self.textPrimary
        chartTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartTitleLabel)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chartView)

        // ── 按钮 ──
        refreshBtn.target = self
        refreshBtn.action = #selector(onRefresh)
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(refreshBtn)

        clearBtn.target = self
        clearBtn.action = #selector(onClearAll)
        clearBtn.bezelColor = .systemRed
        clearBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearBtn)

        // 权限状态标签
        permStatusLbl.font = LazyCatTheme.body(11, weight: .medium)
        permStatusLbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(permStatusLbl)

        resetPermBtn.target = self
        resetPermBtn.action = #selector(onResetPerm)
        resetPermBtn.bezelColor = .systemOrange
        resetPermBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resetPermBtn)

        // 把 topCard 移到最底层，避免覆盖里面的标签
        if let g = topCard.layer?.sublayers?.first as? CAGradientLayer {
            _ = g  // 引用避免 warning
        }

        // ── 约束 ──
        NSLayoutConstraint.activate([
            // 顶部状态卡（暖橙渐变）
            topCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            topCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            topCard.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            topCard.heightAnchor.constraint(equalToConstant: 100),

            titleLabel.leadingAnchor.constraint(equalTo: topCard.leadingAnchor, constant: 22),
            titleLabel.topAnchor.constraint(equalTo: topCard.topAnchor, constant: 22),

            totalSubLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            totalSubLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),

            totalBigLabel.trailingAnchor.constraint(equalTo: topCard.trailingAnchor, constant: -22),
            totalBigLabel.centerYAnchor.constraint(equalTo: topCard.centerYAnchor),

            // Top 5
            topTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            topTitleLabel.topAnchor.constraint(equalTo: topCard.bottomAnchor, constant: 22),

            topStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            topStack.topAnchor.constraint(equalTo: topTitleLabel.bottomAnchor, constant: 8),
            topStack.heightAnchor.constraint(equalToConstant: 180),

            // 柱状图
            chartTitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            chartTitleLabel.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 22),

            chartView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            chartView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            chartView.topAnchor.constraint(equalTo: chartTitleLabel.bottomAnchor, constant: 8),
            chartView.bottomAnchor.constraint(equalTo: refreshBtn.topAnchor, constant: -16),

            // 权限状态（底部左侧）
            permStatusLbl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            permStatusLbl.bottomAnchor.constraint(equalTo: refreshBtn.topAnchor, constant: -8),

            resetPermBtn.leadingAnchor.constraint(equalTo: permStatusLbl.trailingAnchor, constant: 10),
            resetPermBtn.centerYAnchor.constraint(equalTo: permStatusLbl.centerYAnchor),

            // 按钮
            refreshBtn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            refreshBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),

            clearBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            clearBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    // MARK: - 刷新

    func reload() {
        let counter = KeyTypingCounter.shared
        totalBigLabel.stringValue = "\(counter.todayCount)"

        // Top 5（最近 30 天聚合）
        let top = counter.topKeys(days: 30, limit: 5)
        let maxCount = top.first?.count ?? 1

        // 清空旧条目
        for v in topStack.arrangedSubviews { v.removeFromSuperview() }
        if top.isEmpty {
            let empty = NSTextField(labelWithString: "暂无数据 — 多敲两下试试 🐈")
            empty.textColor = Self.textTertiary
            empty.font = .systemFont(ofSize: 13)
            topStack.addArrangedSubview(empty)
        } else {
            for (idx, item) in top.enumerated() {
                let row = TopKeyRow()
                row.configure(rank: idx + 1,
                              label: KeyTypingCounter.label(for: item.keyCode),
                              count: item.count,
                              maxCount: maxCount)
                topStack.addArrangedSubview(row)
                row.leadingAnchor.constraint(equalTo: topStack.leadingAnchor).isActive = true
                row.trailingAnchor.constraint(equalTo: topStack.trailingAnchor).isActive = true
            }
        }

        // 日柱状图
        let daily = counter.dailyCounts(days: 30)
        chartView.setData(daily)

        // 权限状态
        let state = counter.accessState
        switch state {
        case kIOHIDAccessTypeGranted:
            permStatusLbl.stringValue = "✅ 输入监控已授权"
            permStatusLbl.textColor = NSColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)
            resetPermBtn.isHidden = true
        case kIOHIDAccessTypeDenied:
            permStatusLbl.stringValue = "❌ 输入监控被拒 — 计数器失效"
            permStatusLbl.textColor = NSColor.systemRed
            resetPermBtn.isHidden = false
        default:
            permStatusLbl.stringValue = "⚠️ 输入监控未授权"
            permStatusLbl.textColor = NSColor.systemOrange
            resetPermBtn.isHidden = false
        }
    }

    override func layout() {
        super.layout()
        // 渐变层尺寸跟着 topCard 走
        if let g = topCard.layer?.sublayers?.first as? CAGradientLayer {
            g.frame = topCard.bounds
        }
    }

    @objc private func onRefresh() { reload() }

    @objc private func onResetPerm() {
        KeyTypingCounter.shared.resetTCCAndRequest()
    }

    @objc private func onClearAll() {
        let alert = NSAlert()
        alert.messageText = "确定清空全部打字历史？"
        alert.informativeText = "这会删除最近 30 天内所有按键记录（每日总数 + 单键计数）。\n该操作不可撤销。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        if alert.runModal() != .alertFirstButtonReturn { return }

        let ud = UserDefaults.standard
        var n = 0
        for (k, _) in ud.dictionaryRepresentation() {
            if k.hasPrefix("MyTodo.typingCount.") || k.hasPrefix("MyTodo.typingByKey.") {
                ud.removeObject(forKey: k)
                n += 1
            }
        }
        AppLog.log("TypingStats: 用户手动清空 \(n) 条记录")
        NotificationCenter.default.post(name: .typingKeyDown, object: nil)  // 顺手刷一下菜单栏
        reload()
    }
}

// MARK: - Top 5 按键单行

private final class TopKeyRow: NSView {
    private let medal      = NSView()
    private let medalLabel = NSTextField(labelWithString: "")
    private let keyLabel   = NSTextField(labelWithString: "")
    private let bar        = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private var barWidth: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // ★ 卡片化：白底 + 圆角 + 柔阴影
        layer?.backgroundColor = TypingStatsView.bgCard.cgColor
        layer?.cornerRadius = LazyCatTheme.cornerSm
        layer?.shadowColor = NSColor(red: 0.7, green: 0.43, blue: 0.12, alpha: 0.06).cgColor
        layer?.shadowRadius = 4
        layer?.shadowOpacity = 1
        layer?.shadowOffset = .init(width: 0, height: -1)
        layer?.masksToBounds = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // 奖牌（圆形渐变底）
        medal.wantsLayer = true
        medal.layer?.cornerRadius = 13
        medal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(medal)

        medalLabel.font = .systemFont(ofSize: 11, weight: .heavy)
        medalLabel.textColor = .white
        medalLabel.alignment = .center
        medalLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(medalLabel)

        for f in [keyLabel, countLabel] {
            f.translatesAutoresizingMaskIntoConstraints = false
            addSubview(f)
        }
        bar.wantsLayer = true
        bar.layer?.backgroundColor = TypingStatsView.accent.cgColor
        bar.layer?.cornerRadius = 4
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)

        keyLabel.font = LazyCatTheme.body(13.5, weight: .heavy)
        keyLabel.textColor = TypingStatsView.textPrimary

        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .heavy)
        countLabel.textColor = TypingStatsView.textSecondary
        countLabel.alignment = .right

        barWidth = bar.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            medal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            medal.centerYAnchor.constraint(equalTo: centerYAnchor),
            medal.widthAnchor.constraint(equalToConstant: 26),
            medal.heightAnchor.constraint(equalToConstant: 26),

            medalLabel.centerXAnchor.constraint(equalTo: medal.centerXAnchor),
            medalLabel.centerYAnchor.constraint(equalTo: medal.centerYAnchor),

            keyLabel.leadingAnchor.constraint(equalTo: medal.trailingAnchor, constant: 10),
            keyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            keyLabel.widthAnchor.constraint(equalToConstant: 90),

            bar.leadingAnchor.constraint(equalTo: keyLabel.trailingAnchor, constant: 8),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 10),
            barWidth,

            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 70),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: bar.trailingAnchor, constant: 8),
        ])
    }

    func configure(rank: Int, label: String, count: Int, maxCount: Int) {
        medalLabel.stringValue = "\(rank)"
        keyLabel.stringValue = label
        countLabel.stringValue = "\(count)"

        // 条形宽度按比例
        let pct = maxCount > 0 ? CGFloat(count) / CGFloat(maxCount) : 0
        let maxBarPt: CGFloat = 320
        barWidth.constant = max(2, pct * maxBarPt)

        // 奖牌颜色：金 / 银 / 铜 / 橘
        let medalColor: NSColor
        switch rank {
        case 1: medalColor = TypingStatsView.gold
        case 2: medalColor = TypingStatsView.silver
        case 3: medalColor = TypingStatsView.bronze
        default: medalColor = TypingStatsView.accent
        }
        medal.layer?.backgroundColor = medalColor.cgColor

        // 条形颜色：暖橙渐淡
        let alpha: CGFloat = max(0.45, 1.0 - CGFloat(rank - 1) * 0.12)
        bar.layer?.backgroundColor = TypingStatsView.accent.withAlphaComponent(alpha).cgColor
    }
}

// MARK: - 每日柱状图

private final class DailyBarChartView: NSView {
    private var data: [(date: Date, day: String, count: Int)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = TypingStatsView.separator.cgColor
        layer?.borderWidth = 1
    }
    required init?(coder: NSCoder) { fatalError() }

    func setData(_ d: [(date: Date, day: String, count: Int)]) {
        data = d
        needsDisplay = true
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        guard !data.isEmpty else {
            // 空态文字
            let s = "暂无历史数据"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: TypingStatsView.textTertiary,
            ]
            let size = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                withAttributes: attrs)
            return
        }

        let padL: CGFloat = 44   // y 轴刻度
        let padR: CGFloat = 12
        let padT: CGFloat = 14
        let padB: CGFloat = 28   // x 轴日期

        let plotRect = NSRect(
            x: bounds.minX + padL,
            y: bounds.minY + padB,
            width: max(0, bounds.width - padL - padR),
            height: max(0, bounds.height - padT - padB))

        let maxVal = max(1, data.map { $0.count }.max() ?? 1)
        let n = data.count
        let slot = plotRect.width / CGFloat(n)
        let barW = max(2, slot * 0.7)

        // y 轴刻度（0 / 50% / 100%）
        let axisAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: TypingStatsView.textSecondary,
        ]
        ctx.saveGState()
        ctx.setStrokeColor(TypingStatsView.separator.cgColor)
        ctx.setLineWidth(0.5)
        for frac in [0.0, 0.5, 1.0] {
            let y = plotRect.minY + plotRect.height * CGFloat(frac)
            ctx.move(to: CGPoint(x: plotRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: plotRect.maxX, y: y))
            let label = "\(Int(Double(maxVal) * frac))"
            let sz = (label as NSString).size(withAttributes: axisAttrs)
            (label as NSString).draw(
                at: NSPoint(x: plotRect.minX - sz.width - 6, y: y - sz.height / 2),
                withAttributes: axisAttrs)
        }
        ctx.strokePath()
        ctx.restoreGState()

        // 找到今日中最大值的索引（高亮）
        let maxIdx = data.firstIndex(where: { $0.count == maxVal }) ?? -1

        // 柱体 + 顶端数字
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: TypingStatsView.textSecondary,
        ]
        for (i, item) in data.enumerated() {
            let h = CGFloat(item.count) / CGFloat(maxVal) * plotRect.height
            let x = plotRect.minX + CGFloat(i) * slot + (slot - barW) / 2
            let y = plotRect.minY
            let rect = NSRect(x: x, y: y, width: barW, height: h)

            let color: NSColor = (i == n - 1)
                ? TypingStatsView.accentToday  // 今日 — 高亮橙
                : (i == maxIdx
                    ? TypingStatsView.accent.withAlphaComponent(0.95)
                    : TypingStatsView.accent.withAlphaComponent(0.55))
            color.setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            path.fill()

            // 顶端 count 文字（仅当柱足够高时画）
            if h > 18 && item.count > 0 {
                let s = "\(item.count)"
                let sz = (s as NSString).size(withAttributes: valueAttrs)
                (s as NSString).draw(
                    at: NSPoint(x: x + barW / 2 - sz.width / 2, y: y + h - sz.height - 2),
                    withAttributes: valueAttrs)
            }
        }

        // x 轴日期（每 5 天 1 个 + 第一天 + 最后一天）
        let dayAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: TypingStatsView.textSecondary,
        ]
        let df = DateFormatter()
        df.dateFormat = "M/d"
        for i in 0..<n {
            // 显示 0 / 5 / 10 ... 以及最后
            if !(i % 5 == 0 || i == n - 1) { continue }
            let item = data[i]
            let s = df.string(from: item.date)
            let x = plotRect.minX + CGFloat(i) * slot + slot / 2
            let sz = (s as NSString).size(withAttributes: dayAttrs)
            (s as NSString).draw(
                at: NSPoint(x: x - sz.width / 2, y: plotRect.minY - sz.height - 4),
                withAttributes: dayAttrs)
        }
    }
}
