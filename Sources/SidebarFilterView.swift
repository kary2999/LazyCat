import AppKit

/// 三栏布局的左侧 sidebar（vibrancy + 分组导航）
/// 严格按 ui-app-style-v5.html 风格 A 实现
final class SidebarFilterView: NSView {

    enum Filter: Equatable {
        case today
        case week
        case all
        case done
        case byPerson(String)
        case byPriority(Priority)
    }

    var onChange: ((Filter) -> Void)?
    var onSearch: ((String) -> Void)?
    private(set) var current: Filter = .today

    private let vibrancy = NSVisualEffectView()
    private let stack = FlippedStack()
    private let scroll = NSScrollView()
    private let docContainer = FlippedDocView()
    private let searchField = NSTextField()
    private let footerStrip = NSView()
    private let footerLabel = NSTextField(labelWithString: "")
    private var docHeight: NSLayoutConstraint!

    private var navRows: [NavRow] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // 固定 bgSoft 实色底，不用 vibrancy（避免跟随系统深色模式飘色）
        wantsLayer = true
        layer?.backgroundColor = LazyCatTheme.bgSoft.cgColor

        // 搜索框
        searchField.placeholderString = "搜索 任务 / @人"
        searchField.font = LazyCatTheme.body(12)
        searchField.bezelStyle = .roundedBezel
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.focusRingType = .none
        addSubview(searchField)

        // 滚动容器
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        docContainer.translatesAutoresizingMaskIntoConstraints = false
        docContainer.addSubview(stack)
        docHeight = docContainer.heightAnchor.constraint(equalToConstant: 100)

        scroll.documentView = docContainer
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        // 底部 footer 信息条（双击 → 打字排行）
        footerStrip.wantsLayer = true
        footerStrip.layer?.backgroundColor = LazyCatTheme.border1.withAlphaComponent(0.4).cgColor
        footerStrip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerStrip)

        let dblClick = NSClickGestureRecognizer(target: self, action: #selector(openTypingStats))
        dblClick.numberOfClicksRequired = 2
        footerStrip.addGestureRecognizer(dblClick)
        footerStrip.toolTip = "双击查看打字排行"

        footerLabel.font = LazyCatTheme.body(11, weight: .semibold)
        footerLabel.textColor = LazyCatTheme.tx3
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerStrip.addSubview(footerLabel)

        let footerTopBorder = NSView()
        footerTopBorder.wantsLayer = true
        footerTopBorder.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        footerTopBorder.translatesAutoresizingMaskIntoConstraints = false
        footerStrip.addSubview(footerTopBorder)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            searchField.heightAnchor.constraint(equalToConstant: 22),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footerStrip.topAnchor),

            docContainer.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            docHeight,
            stack.topAnchor.constraint(equalTo: docContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor),

            footerStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerStrip.bottomAnchor.constraint(equalTo: bottomAnchor),
            footerStrip.heightAnchor.constraint(equalToConstant: 28),

            footerTopBorder.topAnchor.constraint(equalTo: footerStrip.topAnchor),
            footerTopBorder.leadingAnchor.constraint(equalTo: footerStrip.leadingAnchor),
            footerTopBorder.trailingAnchor.constraint(equalTo: footerStrip.trailingAnchor),
            footerTopBorder.heightAnchor.constraint(equalToConstant: 0.5),

            footerLabel.leadingAnchor.constraint(equalTo: footerStrip.leadingAnchor, constant: 14),
            footerLabel.centerYAnchor.constraint(equalTo: footerStrip.centerYAnchor),
        ])
    }

    // 重建导航
    func rebuild() {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        for v in stack.subviews where v.superview === stack { v.removeFromSuperview() }
        navRows.removeAll()

        let all = Store.shared.data.tasks
        let pending = all.filter { !$0.completed }
        let done = all.filter { $0.completed }
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: today) ?? now

        let todayN = pending.filter { (cal.startOfDay(for: $0.remindAt ?? $0.createdAt)) <= today }.count
        let weekN  = pending.filter { ($0.remindAt ?? $0.createdAt) <= weekEnd }.count

        var totalH: CGFloat = stack.edgeInsets.top + stack.edgeInsets.bottom

        // 视图区
        totalH += addHeader("视图")
        totalH += addNavRow(.today,  ico: "⏰", title: "今天",   count: todayN)
        totalH += addNavRow(.week,   ico: "📅", title: "本周",   count: weekN)
        totalH += addNavRow(.all,    ico: "📥", title: "全部",   count: pending.count)
        totalH += addNavRow(.done,   ico: "✓",  title: "已完成", count: done.count)

        // 人区
        totalH += addHeader("人")
        let counts = Dictionary(grouping: pending, by: { $0.person })
            .mapValues { $0.count }
            .filter { !$0.key.isEmpty }
            .sorted { $0.value > $1.value }
            .prefix(8)
        if counts.isEmpty {
            totalH += addEmpty("（暂无）")
        } else {
            for (i, item) in counts.enumerated() {
                totalH += addNavRow(.byPerson(item.key), ico: avatarChar(item.key, idx: i),
                                    title: item.key, count: item.value, hueIdx: i)
            }
        }

        // 优先级
        totalH += addHeader("优先级")
        let t0 = pending.filter { $0.priority == .top }.count
        let t1 = pending.filter { $0.priority == .mid }.count
        let t2 = pending.filter { $0.priority == .low }.count
        totalH += addNavRow(.byPriority(.top), ico: "●", title: "T0 紧急", count: t0, iconColor: LazyCatTheme.red)
        totalH += addNavRow(.byPriority(.mid), ico: "●", title: "T1 重要", count: t1, iconColor: LazyCatTheme.accent)
        totalH += addNavRow(.byPriority(.low), ico: "●", title: "T2 一般", count: t2, iconColor: LazyCatTheme.green)

        docHeight.constant = max(totalH, 80)

        // 同步选中态
        for r in navRows { r.isSelected = (r.filter == current) }

        // footer
        let typing = KeyTypingCounter.shared.todayCount
        let total = pending.count + done.count
        let pct = total > 0 ? Int((Double(done.count) / Double(total) * 100).rounded()) : 0
        footerLabel.stringValue = "🔥 \(typing) 键 · \(pct)% · \(streakText())"
    }

    private func streakText() -> String {
        var days = 0
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        for i in 0..<60 {
            guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { break }
            let key = "MyTodo.typingCount." + f.string(from: d)
            let n = UserDefaults.standard.integer(forKey: key)
            if n > 0 { days += 1 } else if i > 0 { break }
        }
        return "\(days) 天"
    }

    private func addHeader(_ s: String) -> CGFloat {
        let v = NSTextField(labelWithString: s.uppercased())
        v.font = LazyCatTheme.body(10, weight: .medium)
        v.textColor = LazyCatTheme.tx3
        v.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(v)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 28),
            v.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
            v.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
        ])
        stack.addArrangedSubview(wrap)
        wrap.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                    constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        return 28
    }

    private func addEmpty(_ s: String) -> CGFloat {
        let v = NSTextField(labelWithString: s)
        v.font = LazyCatTheme.body(11)
        v.textColor = LazyCatTheme.tx4
        v.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(v)
        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(equalToConstant: 22),
            v.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 16),
            v.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        stack.addArrangedSubview(wrap)
        wrap.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                    constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        return 22
    }

    @discardableResult
    private func addNavRow(_ filter: Filter, ico: String, title: String, count: Int,
                           iconColor: NSColor? = nil, hueIdx: Int = 0) -> CGFloat {
        let row = NavRow(filter: filter, icon: ico, title: title, count: count,
                         iconColor: iconColor, hueIdx: hueIdx)
        row.onClick = { [weak self] in
            guard let self = self else { return }
            self.current = filter
            for r in self.navRows { r.isSelected = (r.filter == filter) }
            self.onChange?(filter)
        }
        navRows.append(row)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                   constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true
        return 28
    }

    private func avatarChar(_ name: String, idx: Int) -> String {
        return String(name.prefix(1))
    }
}

extension SidebarFilterView {
    @objc fileprivate func openTypingStats() {
        TypingStatsWindowController.shared.present()
    }
}

extension SidebarFilterView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onSearch?(searchField.stringValue)
    }
}

// MARK: - 单行 nav

private final class NavRow: NSView {
    let filter: SidebarFilterView.Filter
    let title: String
    let count: Int
    let icon: String
    let iconColor: NSColor?
    let hueIdx: Int

    var onClick: (() -> Void)?
    var isSelected: Bool = false { didSet { restyle() } }

    private let iconLabel = NSTextField(labelWithString: "")
    private let avatarChip = AvatarChip()      // 仅 byPerson 时用
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")

    init(filter: SidebarFilterView.Filter, icon: String, title: String, count: Int,
         iconColor: NSColor?, hueIdx: Int) {
        self.filter = filter
        self.icon = icon
        self.title = title
        self.count = count
        self.iconColor = iconColor
        self.hueIdx = hueIdx
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let leftIcon: NSView
        if case .byPerson = filter {
            let palette: [NSColor] = [
                LazyCatTheme.accent,
                LazyCatTheme.mint,
                NSColor(red: 1.00, green: 0.72, blue: 0.40, alpha: 1),
                NSColor(red: 0.95, green: 0.49, blue: 0.55, alpha: 1),
                NSColor(red: 0.50, green: 0.50, blue: 0.78, alpha: 1),
            ]
            avatarChip.bgColor = palette[hueIdx % palette.count]
            avatarChip.text = icon.uppercased()
            avatarChip.translatesAutoresizingMaskIntoConstraints = false
            addSubview(avatarChip)
            leftIcon = avatarChip
        } else {
            iconLabel.stringValue = icon
            iconLabel.alignment = .center
            iconLabel.font = .systemFont(ofSize: 11)
            iconLabel.textColor = iconColor ?? LazyCatTheme.tx2
            iconLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(iconLabel)
            leftIcon = iconLabel
        }

        titleLabel.stringValue = title
        titleLabel.font = LazyCatTheme.body(12.5, weight: .medium)
        titleLabel.textColor = LazyCatTheme.tx1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        countLabel.stringValue = "\(count)"
        countLabel.font = LazyCatTheme.body(11, weight: .medium)
        countLabel.textColor = LazyCatTheme.tx3
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            leftIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            leftIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftIcon.widthAnchor.constraint(equalToConstant: 18),
            leftIcon.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: leftIcon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
        ])
    }

    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }
    override func mouseEntered(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = LazyCatTheme.accent.withAlphaComponent(0.07).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // 左侧橙色指示条
    private lazy var indicator: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = LazyCatTheme.accent.cgColor
        v.layer?.cornerRadius = 1.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private func restyle() {
        if isSelected {
            layer?.backgroundColor = LazyCatTheme.accent.withAlphaComponent(0.12).cgColor
            titleLabel.textColor = LazyCatTheme.accent
            titleLabel.font = LazyCatTheme.body(12.5, weight: .semibold)
            if indicator.superview == nil {
                addSubview(indicator)
                NSLayoutConstraint.activate([
                    indicator.leadingAnchor.constraint(equalTo: leadingAnchor),
                    indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
                    indicator.widthAnchor.constraint(equalToConstant: 3),
                    indicator.heightAnchor.constraint(equalToConstant: 16),
                ])
            }
            indicator.isHidden = false
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = LazyCatTheme.tx1
            titleLabel.font = LazyCatTheme.body(12.5, weight: .medium)
            indicator.isHidden = true
        }
    }
}


// MARK: - AvatarChip：圆形头像，单字符严格几何居中
final class AvatarChip: NSView {
    var bgColor: NSColor = .gray { didSet { needsDisplay = true } }
    var text: String = "" { didSet { needsDisplay = true } }

    override var wantsUpdateLayer: Bool { false }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // 圆
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillEllipse(in: bounds)
        // 文字（取首字符；中文用 11pt semibold，英文 12pt bold）
        guard let ch = text.first else { return }
        let s = String(ch)
        let isHan = (ch.unicodeScalars.first?.value ?? 0) > 0x2E80
        let font: NSFont = isHan
            ? .systemFont(ofSize: 11, weight: .semibold)
            : .systemFont(ofSize: 12, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let attr = NSAttributedString(string: s, attributes: attrs)
        let sz = attr.size()
        // 真几何居中（NSAttributedString.size 包含字形上下间距，所以再做一点点视觉补偿）
        let visualOffsetY: CGFloat = isHan ? -0.5 : 0   // 汉字字形上间距更宽，往下挪一点
        let pt = NSPoint(
            x: (bounds.width - sz.width) / 2,
            y: (bounds.height - sz.height) / 2 + visualOffsetY
        )
        attr.draw(at: pt)
    }
}
