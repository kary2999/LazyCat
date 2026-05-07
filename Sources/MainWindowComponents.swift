import AppKit

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 翻转容器（让 NSScrollView documentView 起始 = top-left）
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class FlippedStack: NSStackView {
    override var isFlipped: Bool { true }
}
class FlippedDocView: NSView {
    override var isFlipped: Bool { true }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Hero Bar (顶部紧凑状态条 · 高度 40pt)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class HeroBarView: NSView {
    private let avatarBg = NSView()
    private let avatar  = NSTextField(labelWithString: "🐈")
    private let title   = NSTextField(labelWithString: "")
    private let sub     = NSTextField(labelWithString: "")
    private let pip1    = HeroPipView()
    private let pip2    = HeroPipView()
    private let pip3    = HeroPipView()
    private let pip4    = HeroPipView()
    private let gradient = CAGradientLayer()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = LazyCatTheme.cornerMd
        layer?.masksToBounds = true
        gradient.colors = [
            LazyCatTheme.accent.cgColor,
            NSColor(red: 1.0, green: 0.72, blue: 0.50, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.insertSublayer(gradient, at: 0)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    private func build() {
        avatarBg.wantsLayer = true
        avatarBg.layer?.backgroundColor = NSColor.white.cgColor
        avatarBg.layer?.cornerRadius = 18
        avatarBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarBg)

        avatar.font = .systemFont(ofSize: 20)
        avatar.alignment = .center
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatarBg.addSubview(avatar)

        // ★ 字号整体放大 + 不再加阴影（阴影是糊的根因，改用 .black 重字重 + 实色对比）
        title.font = LazyCatTheme.body(16, weight: .semibold)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        sub.font = LazyCatTheme.body(12, weight: .medium)
        sub.textColor = NSColor.white
        sub.lineBreakMode = .byTruncatingTail
        sub.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sub)

        for p in [pip1, pip2, pip3, pip4] {
            p.translatesAutoresizingMaskIntoConstraints = false
            addSubview(p)
        }

        NSLayoutConstraint.activate([
            avatarBg.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            avatarBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarBg.widthAnchor.constraint(equalToConstant: 36),
            avatarBg.heightAnchor.constraint(equalToConstant: 36),

            avatar.centerXAnchor.constraint(equalTo: avatarBg.centerXAnchor),
            avatar.centerYAnchor.constraint(equalTo: avatarBg.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: avatarBg.trailingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: pip1.leadingAnchor, constant: -10),

            pip4.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pip4.centerYAnchor.constraint(equalTo: centerYAnchor),
            pip3.trailingAnchor.constraint(equalTo: pip4.leadingAnchor, constant: -2),
            pip3.centerYAnchor.constraint(equalTo: centerYAnchor),
            pip2.trailingAnchor.constraint(equalTo: pip3.leadingAnchor, constant: -2),
            pip2.centerYAnchor.constraint(equalTo: centerYAnchor),
            pip1.trailingAnchor.constraint(equalTo: pip2.leadingAnchor, constant: -2),
            pip1.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        refresh()
    }

    func refresh() {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M 月 d 日 · EEEE"
        title.stringValue = df.string(from: Date())

        let n = KeyTypingCounter.shared.todayCount
        let mood: String
        switch n {
        case 0:           mood = "等你回来 🐾"
        case 1...499:     mood = "刚开始热身 ☕"
        case 500..<2000:  mood = "状态在线 💪"
        case 2000..<5000: mood = "手很热 🔥"
        case 5000..<10000:mood = "高产中 ⚡"
        default:          mood = "停不下来啦 🚀"
        }
        let allTasks = Store.shared.data.tasks
        let pending = allTasks.filter { !$0.completed }.count
        let done = allTasks.filter { $0.completed }.count
        sub.stringValue = "小懒猫 · \(mood) · 待办 \(pending) · 完成 \(done)"

        let total = pending + done
        let pct = total > 0 ? Int((Double(done) / Double(total) * 100).rounded()) : 0
        pip1.set(value: "\(n)", label: "今日键")
        pip2.set(value: "\(done)/\(total)", label: "完成")
        pip3.set(value: "\(pct)%", label: "进度")
        pip4.set(value: streakText(), label: "连续")
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
        return "\(days)天"
    }
}

private final class HeroPipView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private let labelLabel = NSTextField(labelWithString: "")
    private let dividerL = NSView()

    init() {
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = .white
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        labelLabel.font = LazyCatTheme.body(10.5, weight: .medium)
        labelLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        labelLabel.alignment = .center
        labelLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labelLabel)

        dividerL.wantsLayer = true
        dividerL.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        dividerL.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dividerL)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 56),

            dividerL.leadingAnchor.constraint(equalTo: leadingAnchor),
            dividerL.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            dividerL.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            dividerL.widthAnchor.constraint(equalToConstant: 1),

            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            labelLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),
            labelLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
            labelLabel.trailingAnchor.constraint(equalTo: valueLabel.trailingAnchor),
            labelLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    func set(value: String, label: String) {
        valueLabel.stringValue = value
        labelLabel.stringValue = label
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Tab Bar (⭐进行中 / ✅完成 / 📋全部 + 🔍 搜索)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class FilterTabBar: NSView {
    enum Mode: Int { case pending = 0, done = 1, all = 2 }

    var onChange: ((Mode) -> Void)?
    var onSearch: ((String) -> Void)?

    private let pendingChip = TabChip(title: "⭐ 进行中")
    private let doneChip    = TabChip(title: "✅ 完成")
    private let allChip     = TabChip(title: "📋 全部")
    private let searchField = NSTextField()

    private(set) var currentMode: Mode = .pending

    init() {
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        pendingChip.translatesAutoresizingMaskIntoConstraints = false
        doneChip.translatesAutoresizingMaskIntoConstraints = false
        allChip.translatesAutoresizingMaskIntoConstraints = false

        pendingChip.onClick = { [weak self] in self?.select(.pending) }
        doneChip.onClick = { [weak self] in self?.select(.done) }
        allChip.onClick = { [weak self] in self?.select(.all) }
        pendingChip.isOn = true

        addSubview(pendingChip)
        addSubview(doneChip)
        addSubview(allChip)

        searchField.placeholderString = "🔍 搜任务 / @人"
        searchField.font = LazyCatTheme.body(12.5, weight: .regular)
        searchField.bezelStyle = .roundedBezel
        searchField.delegate = self
        searchField.textColor = LazyCatTheme.tx1
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        NSLayoutConstraint.activate([
            pendingChip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            pendingChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            doneChip.leadingAnchor.constraint(equalTo: pendingChip.trailingAnchor, constant: 5),
            doneChip.centerYAnchor.constraint(equalTo: centerYAnchor),
            allChip.leadingAnchor.constraint(equalTo: doneChip.trailingAnchor, constant: 5),
            allChip.centerYAnchor.constraint(equalTo: centerYAnchor),

            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 200),
            searchField.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    private func select(_ m: Mode) {
        currentMode = m
        pendingChip.isOn = m == .pending
        doneChip.isOn    = m == .done
        allChip.isOn     = m == .all
        onChange?(m)
    }

    func updateCounts(pending: Int, done: Int, total: Int) {
        pendingChip.title = "⭐ 进行中 (\(pending))"
        doneChip.title    = "✅ 完成 (\(done))"
        allChip.title     = "📋 全部 (\(total))"
    }

    /// 程序化设置搜索框文本（点击合作人 widget 时用）
    func setSearch(_ q: String) {
        searchField.stringValue = q
    }
}

extension FilterTabBar: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        onSearch?(searchField.stringValue)
    }
}

private final class TabChip: NSView {
    var title: String = "" {
        didSet { titleLabel.stringValue = title; restyle() }
    }
    var isOn: Bool = false { didSet { restyle() } }
    var onClick: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.borderWidth = 1.5
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        titleLabel.stringValue = title
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func restyle() {
        if isOn {
            layer?.backgroundColor = LazyCatTheme.accent.cgColor
            layer?.borderColor = LazyCatTheme.accent.cgColor
            titleLabel.attributedStringValue = NSAttributedString(string: title, attributes: [
                .foregroundColor: NSColor.white,
                .font: LazyCatTheme.body(12, weight: .medium),
            ])
        } else {
            layer?.backgroundColor = LazyCatTheme.bgCard.cgColor
            layer?.borderColor = LazyCatTheme.border1.cgColor
            titleLabel.attributedStringValue = NSAttributedString(string: title, attributes: [
                .foregroundColor: LazyCatTheme.tx2,
                .font: LazyCatTheme.body(12, weight: .medium),
            ])
        }
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Timeline Row (单行任务，散列布局，可原地展开)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

protocol TimelineRowDelegate: AnyObject {
    func timelineToggle(_ id: UUID)
    func timelineDelete(_ id: UUID)
    func timelineOpenDetail(_ id: UUID)
    func timelineEditPerson(_ id: UUID)
    func timelineChangePriority(_ id: UUID, _ p: Priority)
    func timelineRowExpanded(_ id: UUID, expanded: Bool)
}

final class TimelineRow: NSView {
    let task: TodoItem
    weak var delegate: TimelineRowDelegate?

    private let priDot = NSView()
    private let check  = CheckCircleView()
    private let textLabel = NSTextField(labelWithString: "")
    private let whoLabel  = NSTextField(labelWithString: "")
    private let whenLabel = NSTextField(labelWithString: "")
    private let iconLabel = NSTextField(labelWithString: "")

    // 展开态
    private var isExpanded = false
    private var heightConstraint: NSLayoutConstraint!
    // 展开时新加的 view，collapse 时移除
    private var expandedAccentBar: NSView?
    private var expandedTextLabel: NSTextField?
    private var expandedActionsRow: NSStackView?

    init(task: TodoItem) {
        self.task = task
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true       // ★ 防止内容溢出 row 边界（修双影 bug）
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // 底部分隔线（极淡）
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(red: 0.98, green: 0.93, blue: 0.82, alpha: 1).cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        // check
        check.isOn = task.completed
        check.translatesAutoresizingMaskIntoConstraints = false
        check.onClick = { [weak self] in
            guard let self = self else { return }
            self.delegate?.timelineToggle(self.task.id)
        }
        addSubview(check)

        // 优先级 dot（小圆 + 投影圈）
        priDot.wantsLayer = true
        priDot.layer?.cornerRadius = 2.5
        priDot.layer?.backgroundColor = LazyCatTheme.priorityColor(task.priority).cgColor
        priDot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(priDot)

        // 文字
        let displayText: String = {
            if task.text.isEmpty { return "(仅图片)" }
            // 第一行作为单行展示（如果文本含换行）
            return task.text.components(separatedBy: "\n").first ?? task.text
        }()
        textLabel.stringValue = displayText
        textLabel.font = LazyCatTheme.body(13.5, weight: .semibold)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        if task.completed {
            textLabel.attributedStringValue = NSAttributedString(string: displayText, attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: LazyCatTheme.tx3,
                .font: LazyCatTheme.body(13.5, weight: .semibold),
            ])
        } else {
            textLabel.textColor = LazyCatTheme.tx1
        }
        addSubview(textLabel)

        // who chip
        if !task.person.isEmpty {
            whoLabel.stringValue = "@\(task.person)"
            whoLabel.font = LazyCatTheme.body(11, weight: .medium)
            whoLabel.textColor = LazyCatTheme.tx2
            whoLabel.drawsBackground = true
            whoLabel.backgroundColor = LazyCatTheme.bgSurface
            whoLabel.wantsLayer = true
            whoLabel.layer?.cornerRadius = 3
            whoLabel.layer?.masksToBounds = true
            whoLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(whoLabel)
        }

        // when（时间 / 提醒）
        let now = Date()
        let isLate = (task.remindAt.map { $0 > now && $0.timeIntervalSinceNow < 86400 }) ?? false
        let whenText: String = {
            if let r = task.remindAt {
                return (r.timeIntervalSinceNow < 3600 && r > now) ? "⏰ " + TaskRowView.smartDate(r) : "🕒 " + TaskRowView.smartDate(r)
            }
            return TaskRowView.smartDate(task.createdAt)
        }()
        whenLabel.stringValue = whenText
        whenLabel.font = LazyCatTheme.body(11, weight: .medium)
        whenLabel.textColor = isLate ? LazyCatTheme.red : LazyCatTheme.tx3
        whenLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(whenLabel)

        // 附件 emoji
        var icons = ""
        if task.text.contains("```") || task.text.contains("##") || task.text.count > 100 {
            icons += "✍️"
        }
        if !task.imageFiles.isEmpty { icons += "🖼" }
        iconLabel.stringValue = icons
        iconLabel.font = LazyCatTheme.body(11, weight: .regular)
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconLabel)

        heightConstraint = heightAnchor.constraint(equalToConstant: 38)   // ★ 字号增大后行高调到 38
        heightConstraint.isActive = true

        // 约束：散列布局（左→右 自然挨着）
        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 13),
            check.heightAnchor.constraint(equalToConstant: 13),

            priDot.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 7),
            priDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            priDot.widthAnchor.constraint(equalToConstant: 5),
            priDot.heightAnchor.constraint(equalToConstant: 5),

            textLabel.leadingAnchor.constraint(equalTo: priDot.trailingAnchor, constant: 8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            iconLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            whenLabel.trailingAnchor.constraint(equalTo: iconLabel.leadingAnchor, constant: -6),
            whenLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            sep.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])

        if !task.person.isEmpty {
            NSLayoutConstraint.activate([
                whoLabel.trailingAnchor.constraint(equalTo: whenLabel.leadingAnchor, constant: -7),
                whoLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                whoLabel.heightAnchor.constraint(equalToConstant: 14),
                textLabel.trailingAnchor.constraint(lessThanOrEqualTo: whoLabel.leadingAnchor, constant: -8),
            ])
        } else {
            NSLayoutConstraint.activate([
                textLabel.trailingAnchor.constraint(lessThanOrEqualTo: whenLabel.leadingAnchor, constant: -8),
            ])
        }
    }

    // MARK: 鼠标 hover / click

    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let t = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }
    override func mouseEntered(with event: NSEvent) {
        if !isExpanded {
            layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        if !isExpanded {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            delegate?.timelineOpenDetail(task.id)
            return
        }
        toggleExpand()
    }

    private func toggleExpand() {
        // 如果文本足够短（≤ 50 字 + 没附件 + 没 markdown）就直接进详情而不展开
        let needsExpand = task.text.count > 50 || !task.imageFiles.isEmpty || task.text.contains("\n")
        guard needsExpand else {
            delegate?.timelineOpenDetail(task.id)
            return
        }
        if isExpanded { collapse() } else { expand() }
    }

    private func expand() {
        isExpanded = true
        layer?.backgroundColor = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1).cgColor
        layer?.cornerRadius = LazyCatTheme.cornerSm

        // ★ 关键：隐藏原本 single-line 的所有元素，避免跟下面 fullText 叠出"双影"
        textLabel.isHidden = true
        whoLabel.isHidden = true
        whenLabel.isHidden = true
        iconLabel.isHidden = true
        check.isHidden = true
        priDot.isHidden = true

        // 给左边加一条橙色 accent
        let accentBar = NSView()
        accentBar.wantsLayer = true
        accentBar.layer?.backgroundColor = LazyCatTheme.accent.cgColor
        accentBar.layer?.cornerRadius = 1.5
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentBar)
        expandedAccentBar = accentBar
        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            accentBar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
        ])

        // 完整正文 + 操作行
        let fullText = NSTextField(wrappingLabelWithString: task.text)
        fullText.font = LazyCatTheme.body(11.5, weight: .regular)
        fullText.textColor = LazyCatTheme.tx1
        fullText.translatesAutoresizingMaskIntoConstraints = false
        fullText.maximumNumberOfLines = 6
        fullText.lineBreakMode = .byTruncatingTail
        fullText.preferredMaxLayoutWidth = max(400, bounds.width - 50)
        addSubview(fullText)
        expandedTextLabel = fullText
        NSLayoutConstraint.activate([
            fullText.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),  // 跟 accentBar 留 13pt 间距
            fullText.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            fullText.topAnchor.constraint(equalTo: topAnchor, constant: 12),
        ])

        // 操作 chip
        let openBtn = makeChipBtn(title: "📝 编辑", action: #selector(actEdit))
        let doneBtn = makeChipBtn(title: task.completed ? "↺ 重开" : "✓ 完成", action: #selector(actToggle))
        let delBtn  = makeChipBtn(title: "🗑 删除", action: #selector(actDelete))

        let actionsRow = NSStackView(views: [openBtn, doneBtn, delBtn])
        actionsRow.orientation = .horizontal
        actionsRow.spacing = 8
        actionsRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionsRow)
        expandedActionsRow = actionsRow
        // ★ bottom 用 equalTo（不是 lessThanEqual），让 row 真的撑高
        NSLayoutConstraint.activate([
            actionsRow.leadingAnchor.constraint(equalTo: fullText.leadingAnchor),
            actionsRow.topAnchor.constraint(equalTo: fullText.bottomAnchor, constant: 10),
            actionsRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            actionsRow.heightAnchor.constraint(equalToConstant: 24),
        ])

        // ★ 同步算高度并设定
        let fullTextHeight = max(20, fullText.intrinsicContentSize.height)
        let newHeight: CGFloat = 12 + fullTextHeight + 10 + 24 + 12   // top + 文 + 间 + 钮 + 底
        heightConstraint.constant = newHeight

        // 强制 stack 立刻重新计算高度，避免后续行被覆盖
        superview?.needsLayout = true
        superview?.layoutSubtreeIfNeeded()

        delegate?.timelineRowExpanded(task.id, expanded: true)
    }

    private func collapse() {
        isExpanded = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = 0

        // ★ 恢复原行元素
        textLabel.isHidden = false
        whoLabel.isHidden = false
        whenLabel.isHidden = false
        iconLabel.isHidden = false
        check.isHidden = false
        priDot.isHidden = false

        expandedAccentBar?.removeFromSuperview(); expandedAccentBar = nil
        expandedTextLabel?.removeFromSuperview(); expandedTextLabel = nil
        expandedActionsRow?.removeFromSuperview(); expandedActionsRow = nil

        heightConstraint.constant = 38
        superview?.needsLayout = true
        superview?.layoutSubtreeIfNeeded()
        delegate?.timelineRowExpanded(task.id, expanded: false)
    }

    private func makeChipBtn(title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = LazyCatTheme.cornerSm
        b.layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: LazyCatTheme.tx2,
            .font: LazyCatTheme.body(10.5, weight: .medium),
        ])
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    @objc private func actEdit() { delegate?.timelineOpenDetail(task.id) }
    @objc private func actToggle() { delegate?.timelineToggle(task.id) }
    @objc private func actDelete() { delegate?.timelineDelete(task.id) }

    // 右键菜单
    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(NSMenuItem(title: task.completed ? "标记未完成" : "标记完成",
                             action: #selector(menuToggle), keyEquivalent: ""))
        m.addItem(.separator())
        let pr = NSMenuItem(title: "优先级", action: nil, keyEquivalent: "")
        let prSub = NSMenu()
        for p in [Priority.top, .mid, .low, .none] {
            let mi = NSMenuItem(title: p.label, action: #selector(menuPriority(_:)), keyEquivalent: "")
            mi.tag = p.rawValue
            mi.target = self
            if p == task.priority { mi.state = .on }
            prSub.addItem(mi)
        }
        pr.submenu = prSub
        m.addItem(pr)
        m.addItem(NSMenuItem(title: "改人名…", action: #selector(menuEditPerson), keyEquivalent: ""))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "打开详情 / 编辑", action: #selector(menuOpenDetail), keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "删除", action: #selector(menuDelete), keyEquivalent: ""))
        for it in m.items { it.target = self }
        return m
    }
    @objc private func menuToggle()      { delegate?.timelineToggle(task.id) }
    @objc private func menuDelete()      { delegate?.timelineDelete(task.id) }
    @objc private func menuOpenDetail()  { delegate?.timelineOpenDetail(task.id) }
    @objc private func menuEditPerson()  { delegate?.timelineEditPerson(task.id) }
    @objc private func menuPriority(_ s: NSMenuItem) {
        if let p = Priority(rawValue: s.tag) {
            delegate?.timelineChangePriority(task.id, p)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - Timeline Section Header (sticky 吸顶 分组标题)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class TimelineSectionHeader: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let pillLabel  = NSTextField(labelWithString: "")
    private let pillBg     = NSView()

    init(title: String, count: Int, isLate: Bool = false, isFuture: Bool = false) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = LazyCatTheme.bgCard.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        build(title: title, count: count, isLate: isLate, isFuture: isFuture)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(title: String, count: Int, isLate: Bool, isFuture: Bool) {
        titleLabel.stringValue = title
        titleLabel.font = LazyCatTheme.body(13, weight: .medium)
        titleLabel.textColor = LazyCatTheme.tx2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        pillBg.wantsLayer = true
        pillBg.layer?.cornerRadius = 8
        pillBg.layer?.backgroundColor = (isLate ? LazyCatTheme.red : (isFuture ? LazyCatTheme.tx3 : LazyCatTheme.accent)).cgColor
        pillBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pillBg)

        pillLabel.stringValue = isLate ? "\(count) 即将到期" : "\(count)"
        pillLabel.attributedStringValue = NSAttributedString(string: pillLabel.stringValue, attributes: [
            .foregroundColor: NSColor.white,
            .font: LazyCatTheme.body(11, weight: .medium),
        ])
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pillBg.addSubview(pillLabel)

        // 底部分隔线
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = LazyCatTheme.border1.cgColor
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            pillBg.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            pillBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillBg.heightAnchor.constraint(equalToConstant: 18),

            pillLabel.leadingAnchor.constraint(equalTo: pillBg.leadingAnchor, constant: 7),
            pillLabel.trailingAnchor.constraint(equalTo: pillBg.trailingAnchor, constant: -7),
            pillLabel.centerYAnchor.constraint(equalTo: pillBg.centerYAnchor),

            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - CheckCircle (复用 v3 之前的)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class CheckCircleView: NSView {
    var isOn: Bool = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        if isOn {
            LazyCatTheme.accent.setFill()
            path.fill()
            NSColor.white.setStroke()
            let p2 = NSBezierPath()
            p2.lineWidth = 1.5
            p2.lineCapStyle = .round
            p2.move(to: NSPoint(x: bounds.width * 0.28, y: bounds.height * 0.5))
            p2.line(to: NSPoint(x: bounds.width * 0.45, y: bounds.height * 0.32))
            p2.line(to: NSPoint(x: bounds.width * 0.72, y: bounds.height * 0.65))
            p2.stroke()
        } else {
            NSColor.white.setFill()
            path.fill()
            LazyCatTheme.border2.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 本周打字 widget
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class WeekTypingWidget: NSView {
    var onClick: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "📊 本周打字")
    private let chart = WeekBarChart()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        // ★ B 方案：作为 sidebar section，不再画卡片框
        layer?.backgroundColor = NSColor.clear.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func build() {
        titleLabel.font = LazyCatTheme.body(12, weight: .medium)
        titleLabel.textColor = LazyCatTheme.tx1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        chart.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chart)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            chart.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            chart.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            chart.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chart.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    func refresh() { chart.refresh() }
}

private final class WeekBarChart: NSView {
    private var data: [(date: Date, count: Int)] = []
    private var weekdayNames = ["一","二","三","四","五","六","日"]

    func refresh() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        var comp = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
        comp.weekday = 2
        guard let monday = cal.date(from: comp) else { return }
        var out: [(Date, Int)] = []
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        for i in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: i, to: monday) else { continue }
            let n = UserDefaults.standard.integer(forKey: "MyTodo.typingCount." + f.string(from: d))
            out.append((d, n))
        }
        data = out
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !data.isEmpty else { return }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let maxVal = max(1, data.map { $0.count }.max() ?? 1)
        let chartH = bounds.height - 14
        let slot = bounds.width / CGFloat(data.count)
        let barW = max(6, slot * 0.55)

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
            .foregroundColor: LazyCatTheme.tx3,
        ]

        for (i, item) in data.enumerated() {
            let isToday = cal.isDate(item.date, inSameDayAs: today)
            let isFuture = item.date > today
            let h = CGFloat(item.count) / CGFloat(maxVal) * (chartH - 4)
            let x = CGFloat(i) * slot + (slot - barW) / 2
            let y: CGFloat = 14
            let rect = NSRect(x: x, y: y, width: barW, height: max(4, h))

            let color: NSColor
            if isFuture {
                color = LazyCatTheme.accentLight.withAlphaComponent(0.25)
            } else if isToday {
                color = LazyCatTheme.mint
            } else {
                color = LazyCatTheme.accent
            }
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()

            let label = weekdayNames[i]
            let lsz = (label as NSString).size(withAttributes: labelAttrs)
            (label as NSString).draw(at: NSPoint(x: x + barW/2 - lsz.width/2, y: 1),
                                     withAttributes: labelAttrs)
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 最常合作 widget
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class PeopleWidget: NSView {
    var onPickPerson: ((String) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "👥 最常合作")
    private let stack = NSStackView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor   // section 风，无卡片
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        titleLabel.font = LazyCatTheme.body(12, weight: .medium)
        titleLabel.textColor = LazyCatTheme.tx1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),

            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            // ★ 等于 bottomAnchor 让 widget 跟着内容收缩，不再留空白
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    func refresh() {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        let allTasks = Store.shared.data.tasks.filter { !$0.completed }
        let counts = Dictionary(grouping: allTasks, by: { $0.person })
            .mapValues { $0.count }
            .filter { !$0.key.isEmpty }
            .sorted { $0.value > $1.value }
            .prefix(5)

        if counts.isEmpty {
            let empty = NSTextField(labelWithString: "暂无合作人")
            empty.font = LazyCatTheme.body(10)
            empty.textColor = LazyCatTheme.tx3
            stack.addArrangedSubview(empty)
            return
        }
        for (i, item) in counts.enumerated() {
            let row = PeopleRow(name: item.key, count: item.value, hueIdx: i)
            row.onClick = { [weak self] in self?.onPickPerson?(item.key) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

private final class PeopleRow: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    init(name: String, count: Int, hueIdx: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        let head = NSTextField(labelWithString: String(name.prefix(1)))
        head.font = .systemFont(ofSize: 10, weight: .medium)
        head.textColor = .white
        head.alignment = .center
        head.wantsLayer = true
        head.drawsBackground = false
        head.layer?.cornerRadius = 9
        head.layer?.masksToBounds = true
        let palette: [NSColor] = [
            LazyCatTheme.accent,
            LazyCatTheme.mint,
            NSColor(red: 1.00, green: 0.72, blue: 0.40, alpha: 1),
            NSColor(red: 0.95, green: 0.49, blue: 0.55, alpha: 1),
            NSColor(red: 0.50, green: 0.50, blue: 0.78, alpha: 1),
        ]
        head.layer?.backgroundColor = palette[hueIdx % palette.count].cgColor
        head.translatesAutoresizingMaskIntoConstraints = false
        addSubview(head)

        let nm = NSTextField(labelWithString: name)
        nm.font = LazyCatTheme.body(10.5, weight: .medium)
        nm.textColor = LazyCatTheme.tx1
        nm.lineBreakMode = .byTruncatingTail
        nm.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nm)

        let ct = NSTextField(labelWithString: "\(count)")
        ct.font = LazyCatTheme.body(9.5, weight: .medium)
        ct.textColor = LazyCatTheme.tx3
        ct.alignment = .right
        ct.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ct)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            head.leadingAnchor.constraint(equalTo: leadingAnchor),
            head.centerYAnchor.constraint(equalTo: centerYAnchor),
            head.widthAnchor.constraint(equalToConstant: 18),
            head.heightAnchor.constraint(equalToConstant: 18),

            nm.leadingAnchor.constraint(equalTo: head.trailingAnchor, constant: 6),
            nm.centerYAnchor.constraint(equalTo: centerYAnchor),

            ct.trailingAnchor.constraint(equalTo: trailingAnchor),
            ct.centerYAnchor.constraint(equalTo: centerYAnchor),
            ct.leadingAnchor.constraint(greaterThanOrEqualTo: nm.trailingAnchor, constant: 6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 今日完成度 widget（小进度环）
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class TodayProgressWidget: NSView {
    private let titleLabel = NSTextField(labelWithString: "🎯 今日完成度")
    private let ringView = ProgressRingView()
    private let stats = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor   // section 风，无卡片
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        titleLabel.font = LazyCatTheme.body(12, weight: .medium)
        titleLabel.textColor = LazyCatTheme.tx1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        ringView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ringView)

        stats.font = LazyCatTheme.body(9.5, weight: .semibold)
        stats.textColor = LazyCatTheme.tx2
        stats.maximumNumberOfLines = 3
        stats.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stats)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),

            ringView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            ringView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            ringView.widthAnchor.constraint(equalToConstant: 44),
            ringView.heightAnchor.constraint(equalToConstant: 44),
            ringView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),

            stats.leadingAnchor.constraint(equalTo: ringView.trailingAnchor, constant: 8),
            stats.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),
            stats.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ])
    }

    func refresh() {
        let all = Store.shared.data.tasks
        let pending = all.filter { !$0.completed }
        let done = all.filter { $0.completed }
        let total = pending.count + done.count
        let pct: CGFloat = total > 0 ? CGFloat(done.count) / CGFloat(total) : 0

        let t0p = pending.filter { $0.priority == .top }.count
        let t0d = done.filter { $0.priority == .top }.count
        let t1p = pending.filter { $0.priority == .mid }.count
        let t1d = done.filter { $0.priority == .mid }.count
        let t2p = pending.filter { $0.priority == .low }.count
        let t2d = done.filter { $0.priority == .low }.count

        ringView.setProgress(pct, label: "\(Int(pct * 100))%")

        let lines = [
            "🔴 T0  \(t0d) / \(t0p + t0d)",
            "🟠 T1  \(t1d) / \(t1p + t1d)",
            "🟢 T2  \(t2d) / \(t2p + t2d)",
        ]
        stats.stringValue = lines.joined(separator: "\n")
    }
}

private final class ProgressRingView: NSView {
    private var pct: CGFloat = 0
    private var pctLabel: String = "0%"

    func setProgress(_ p: CGFloat, label: String) {
        pct = max(0, min(1, p))
        pctLabel = label
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = min(bounds.width, bounds.height) / 2 - 1
        let center = NSPoint(x: bounds.midX, y: bounds.midY)

        // 底圈
        LazyCatTheme.bgSurface.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)).fill()

        // 进度弧
        let path = NSBezierPath()
        path.move(to: center)
        path.appendArc(withCenter: center, radius: r,
                       startAngle: 90, endAngle: 90 - 360 * pct, clockwise: true)
        path.close()
        LazyCatTheme.accent.setFill()
        path.fill()

        // 内白圆
        let innerR = r * 0.7
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - innerR, y: center.y - innerR, width: innerR*2, height: innerR*2)).fill()

        // 中心文字
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: LazyCatTheme.tx1,
        ]
        let s = pctLabel as NSString
        let sz = s.size(withAttributes: attrs)
        s.draw(at: NSPoint(x: center.x - sz.width/2, y: center.y - sz.height/2),
               withAttributes: attrs)
    }
}
