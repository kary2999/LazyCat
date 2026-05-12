import AppKit

/// 列表渲染条目:同发件人私聊会被合并成一条(代表 = 最新消息),mergedIds 含所有原 InboxMessage.id
/// 群消息每条独立,merged.count == 1
fileprivate struct InboxRenderEntry {
    let representative: InboxMessage     // 用最新一条作为卡片显示
    let mergedIds: [String]              // 所有被聚合进来的原 InboxMessage.id(含代表自己)
    var mergedCount: Int { mergedIds.count }
}

/// 一个 tab 项 — [titleLabel, badge] 横向 NSStackView,整组居中 + 底部下划线 layer。
/// stack view 的 arranged badge 在 isHidden=true 时会被 stack 自动折叠,
/// 让 title 在没数字时单独居中。
fileprivate final class TGTabItem: NSView {
    private let titleLbl = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let inner = NSStackView()
    private let underline = CALayer()
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        titleLbl.alignment = .center
        titleLbl.drawsBackground = false
        titleLbl.isBezeled = false

        badge.alignment = .center
        badge.drawsBackground = false
        badge.isBezeled = false
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.masksToBounds = true
        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: 14),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])

        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.spacing = 5
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.addArrangedSubview(titleLbl)
        inner.addArrangedSubview(badge)
        addSubview(inner)
        NSLayoutConstraint.activate([
            inner.centerXAnchor.constraint(equalTo: centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: centerYAnchor),
            inner.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 2),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -2),
        ])

        underline.name = "tab-underline"
        layer?.addSublayer(underline)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func update(title: String, count: Int, isActive: Bool, accentColor: NSColor) {
        let titleColor: NSColor = isActive ? accentColor : LazyCatTheme.tx3
        titleLbl.attributedStringValue = NSAttributedString(string: title, attributes: [
            .foregroundColor: titleColor,
            .font: LazyCatTheme.body(12, weight: isActive ? .bold : .semibold),
        ])
        if count > 0 {
            badge.isHidden = false
            badge.attributedStringValue = NSAttributedString(string: " \(count) ", attributes: [
                .foregroundColor: NSColor.white,
                .font: LazyCatTheme.body(9.5, weight: .bold),
            ])
            badge.layer?.backgroundColor = (isActive ? accentColor : LazyCatTheme.tx4).cgColor
        } else {
            badge.isHidden = true
        }
        underline.backgroundColor = isActive ? accentColor.cgColor : NSColor.clear.cgColor
    }

    override func layout() {
        super.layout()
        underline.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 2)
    }
}

/// 设计图 .tg-card .av:135deg 渐变 + 圆 + 白字单字母。
/// 用 CAGradientLayer 做底,文字 NSTextField 浮在上面;layout() 同步 frame。
fileprivate final class GradientAvatar: NSView {
    private let label = NSTextField(labelWithString: "")
    private let gradient = CAGradientLayer()

    init(letter: String, colors: [NSColor]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        gradient.colors = colors.map { $0.cgColor }
        gradient.startPoint = CGPoint(x: 0, y: 0)   // 左上
        gradient.endPoint = CGPoint(x: 1, y: 1)     // 右下 ≈ 135deg
        layer?.addSublayer(gradient)

        label.alignment = .center
        label.font = .systemFont(ofSize: 11.5, weight: .bold)
        label.textColor = .white
        label.drawsBackground = false
        label.isBezeled = false
        label.stringValue = letter
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}

/// 主窗口最右侧第 4 栏:Telegram 通知箱 v2
/// - 4 选项卡:全部 / 私聊 / 群@ / 报警(关键词正则)
/// - 翻页:每页 6 条,底部页码栏
/// - 批量模式:✓ 选择 → checkbox + 工具栏(已读/转任务/删除/esc)
/// - 同人私聊在列表层会按 senderId 合并成一张卡(显示 +N 条 角标);
///   未读最新一条作为代表;转任务时一次性把同人的所有消息一并 dismiss/转。
final class TGInboxView: NSView {

    var onConvertToTask: ((InboxMessage) -> Void)?
    var onOpenSettings: (() -> Void)?

    enum Tab: Int { case all = 0, dm = 1, group = 2, alert = 3 }

    // ── 状态 ──
    private var currentTab: Tab = .all
    private var currentPage: Int = 1
    private let pageSize: Int = 6
    private var batchMode: Bool = false
    private var selectedIds: Set<String> = []

    // ── 视图 ──
    private let header = NSView()
    private let titleIcon = NSTextField(labelWithString: "✈")
    private let titleLbl = NSTextField(labelWithString: "TG 提示")
    private let countPill = NSTextField(labelWithString: "0")
    private let selectBtn = NSButton(title: "批量处理", target: nil, action: nil)
    private let clearAllBtn = NSButton(title: "全部已读", target: nil, action: nil)

    private let tabBar = NSStackView()
    private var tabItems: [TGTabItem] = []

    private let scroll = NSScrollView()
    private let docContainer = FlippedDocView()
    private let stack = FlippedStack()
    private var docHeight: NSLayoutConstraint!

    private let emptyLbl = NSTextField(labelWithString: "暂无新消息\n配置好 TG 后\n这里会出现 @ 你和私聊的消息")

    private let batchBar = NSView()
    private let batchCount = NSTextField(labelWithString: "0")
    private let batchLabel = NSTextField(labelWithString: "已选")
    private let batchSelectAll = NSButton(title: "全选", target: nil, action: nil)
    private var batchActionButtons: [NSButton] = []
    /// batchBar 动态高度:正常 40,!batchMode 时收为 0(不再占空白)
    private var batchBarHeight: NSLayoutConstraint!

    private let pager = NSView()
    private let pagerInfoLbl = NSTextField(labelWithString: "")

    private let escBtn = NSButton(title: "esc", target: nil, action: nil)

    private let footer = NSView()
    private let footerStatus = NSTextField(labelWithString: "未连接")
    private let gearBtn = NSButton(title: "⚙ 设置", target: nil, action: nil)

    private var observer: NSObjectProtocol?

    // 报警关键词正则
    private static let alertRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: "告警|alert|alarm|报警|异常|exception|fail|崩溃|严重|critical|down|错误|error",
            options: [.caseInsensitive])
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(red: 0.97, green: 0.99, blue: 1.0, alpha: 1).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        build()
        observer = NotificationCenter.default.addObserver(
            forName: TelegramTDLib.inboxDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
        }
        NotificationCenter.default.addObserver(
            forName: TelegramTDLib.authStateDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    // MARK: - build

    private func build() {
        let tg = NSColor(red: 0.13, green: 0.62, blue: 0.85, alpha: 1)

        // header
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        titleIcon.font = .systemFont(ofSize: 13, weight: .bold)
        titleIcon.textColor = .white
        titleIcon.alignment = .center
        titleIcon.wantsLayer = true
        titleIcon.layer?.backgroundColor = tg.cgColor
        titleIcon.layer?.cornerRadius = 12
        titleIcon.layer?.masksToBounds = true
        titleIcon.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleIcon)

        titleLbl.font = LazyCatTheme.body(14.5, weight: .bold)
        titleLbl.textColor = LazyCatTheme.tx1
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(titleLbl)

        countPill.alignment = .center
        countPill.wantsLayer = true
        countPill.layer?.backgroundColor = tg.cgColor
        countPill.layer?.cornerRadius = 9
        countPill.drawsBackground = false
        countPill.isBezeled = false
        countPill.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(countPill)

        // 选择按钮(.select-mode 药丸:普通态浅灰底,激活态 TG 蓝底白字)
        selectBtn.bezelStyle = .regularSquare
        selectBtn.isBordered = false
        selectBtn.focusRingType = .none
        selectBtn.target = self
        selectBtn.action = #selector(actToggleBatch)
        selectBtn.wantsLayer = true
        selectBtn.layer?.cornerRadius = 5
        selectBtn.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(selectBtn)

        // 全部已读
        styleSmallTextBtn(clearAllBtn, title: "全部已读", color: tg,
                          action: #selector(actMarkAllRead))
        header.addSubview(clearAllBtn)

        let hDiv = thinDivider()
        addSubview(hDiv)

        // tab bar(NSStackView 等宽 4 列)
        tabBar.orientation = .horizontal
        tabBar.distribution = .fillEqually
        tabBar.spacing = 0
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBar)
        for i in 0..<4 {
            let item = TGTabItem()
            item.onClick = { [weak self] in
                guard let self = self else { return }
                guard let t = Tab(rawValue: i) else { return }
                self.currentTab = t
                self.currentPage = 1
                self.selectedIds.removeAll()
                self.refresh()
            }
            tabBar.addArrangedSubview(item)
            tabItems.append(item)
        }

        // 滚动列表
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
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

        emptyLbl.font = LazyCatTheme.body(12, weight: .medium)
        emptyLbl.textColor = LazyCatTheme.tx3
        emptyLbl.alignment = .center
        emptyLbl.maximumNumberOfLines = 0
        emptyLbl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLbl)

        // 批量工具栏
        batchBar.wantsLayer = true
        batchBar.layer?.backgroundColor = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 0.96).cgColor
        batchBar.translatesAutoresizingMaskIntoConstraints = false
        batchBar.isHidden = true
        addSubview(batchBar)
        // 动态高度:!batchMode 收 0,batchMode 40
        batchBarHeight = batchBar.heightAnchor.constraint(equalToConstant: 0)
        batchBarHeight.isActive = true

        let batchDiv = thinDivider()
        batchBar.addSubview(batchDiv)
        NSLayoutConstraint.activate([
            batchDiv.topAnchor.constraint(equalTo: batchBar.topAnchor),
            batchDiv.leadingAnchor.constraint(equalTo: batchBar.leadingAnchor),
            batchDiv.trailingAnchor.constraint(equalTo: batchBar.trailingAnchor),
            batchDiv.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        batchCount.alignment = .center
        batchCount.wantsLayer = true
        batchCount.layer?.backgroundColor = LazyCatTheme.accent.cgColor
        batchCount.layer?.cornerRadius = 9
        batchCount.drawsBackground = false
        batchCount.isBezeled = false
        batchCount.translatesAutoresizingMaskIntoConstraints = false
        batchBar.addSubview(batchCount)

        batchLabel.font = LazyCatTheme.body(10.5, weight: .medium)
        batchLabel.textColor = LazyCatTheme.tx2
        batchLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        batchLabel.translatesAutoresizingMaskIntoConstraints = false
        batchBar.addSubview(batchLabel)

        styleSmallTextBtn(batchSelectAll, title: "全选",
                          color: LazyCatTheme.accent,
                          action: #selector(actBatchSelectAll))
        batchBar.addSubview(batchSelectAll)

        // 已读 / 转任务 / 删除 — 字号缩小到 10.5，固定宽防止截断
        let actions: [(String, NSColor, Selector, CGFloat)] = [
            ("已读",  LazyCatTheme.tx2,    #selector(actBatchMarkRead),  40),
            ("转任务", LazyCatTheme.accent, #selector(actBatchConvert),   52),
            ("删除",   LazyCatTheme.red,   #selector(actBatchDelete),    40),
        ]
        for (t, c, sel, w) in actions {
            let b = NSButton(title: t, target: self, action: sel)
            styleBatchActionBtn(b, title: t, color: c, width: w)
            batchBar.addSubview(b)
            batchActionButtons.append(b)
        }

        // 完成按钮左侧 divider
        let escDivider = NSView()
        escDivider.wantsLayer = true
        escDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.1).cgColor
        escDivider.translatesAutoresizingMaskIntoConstraints = false
        batchBar.addSubview(escDivider)

        // ✓ 完成按钮(批量栏最右)— TG 蓝底白字药丸,明确表示退出批量模式
        // 之前用 "esc" 文案太隐晦,用户找不到完成入口
        escBtn.bezelStyle = .regularSquare
        escBtn.isBordered = false
        escBtn.focusRingType = .none
        escBtn.target = self
        escBtn.action = #selector(actExitBatch)
        escBtn.toolTip = "完成批量处理(也可按 esc 退出)"
        escBtn.wantsLayer = true
        escBtn.layer?.cornerRadius = 5
        escBtn.layer?.borderWidth = 0
        escBtn.layer?.backgroundColor = tg.cgColor
        escBtn.attributedTitle = NSAttributedString(string: " ✓ 完成 ", attributes: [
            .foregroundColor: NSColor.white,
            .font: LazyCatTheme.body(11, weight: .bold),
        ])
        escBtn.translatesAutoresizingMaskIntoConstraints = false
        batchBar.addSubview(escBtn)

        // 翻页栏
        pager.wantsLayer = true
        pager.layer?.backgroundColor = NSColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 0.7).cgColor
        pager.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pager)
        let pagerDiv = thinDivider()
        pager.addSubview(pagerDiv)
        NSLayoutConstraint.activate([
            pagerDiv.topAnchor.constraint(equalTo: pager.topAnchor),
            pagerDiv.leadingAnchor.constraint(equalTo: pager.leadingAnchor),
            pagerDiv.trailingAnchor.constraint(equalTo: pager.trailingAnchor),
            pagerDiv.heightAnchor.constraint(equalToConstant: 0.5),
        ])
        pagerInfoLbl.font = LazyCatTheme.body(10.5, weight: .medium)
        pagerInfoLbl.textColor = LazyCatTheme.tx3
        pagerInfoLbl.translatesAutoresizingMaskIntoConstraints = false
        pager.addSubview(pagerInfoLbl)

        // footer
        footer.wantsLayer = true
        footer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footer)

        let fDiv = thinDivider()
        footer.addSubview(fDiv)
        NSLayoutConstraint.activate([
            fDiv.topAnchor.constraint(equalTo: footer.topAnchor),
            fDiv.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            fDiv.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            fDiv.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        footerStatus.font = LazyCatTheme.body(10.5, weight: .medium)
        footerStatus.textColor = LazyCatTheme.tx3
        footerStatus.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(footerStatus)

        styleSmallTextBtn(gearBtn, title: "⚙ 设置", color: tg,
                          action: #selector(actOpenSettings))
        footer.addSubview(gearBtn)

        // 整体约束
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            titleIcon.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            titleIcon.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            titleIcon.widthAnchor.constraint(equalToConstant: 24),
            titleIcon.heightAnchor.constraint(equalToConstant: 24),

            titleLbl.leadingAnchor.constraint(equalTo: titleIcon.trailingAnchor, constant: 8),
            titleLbl.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            countPill.leadingAnchor.constraint(equalTo: titleLbl.trailingAnchor, constant: 6),
            countPill.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            countPill.heightAnchor.constraint(equalToConstant: 18),
            countPill.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),

            clearAllBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            clearAllBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            selectBtn.trailingAnchor.constraint(equalTo: clearAllBtn.leadingAnchor, constant: -8),
            selectBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            selectBtn.heightAnchor.constraint(equalToConstant: 22),

            hDiv.topAnchor.constraint(equalTo: header.bottomAnchor),
            hDiv.leadingAnchor.constraint(equalTo: leadingAnchor),
            hDiv.trailingAnchor.constraint(equalTo: trailingAnchor),
            hDiv.heightAnchor.constraint(equalToConstant: 0.5),

            tabBar.topAnchor.constraint(equalTo: hDiv.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 32),

            scroll.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: batchBar.topAnchor),

            docContainer.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            docHeight,
            stack.topAnchor.constraint(equalTo: docContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor),

            emptyLbl.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLbl.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            emptyLbl.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 14),
            emptyLbl.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -14),

            batchBar.bottomAnchor.constraint(equalTo: pager.topAnchor),
            batchBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            batchBar.trailingAnchor.constraint(equalTo: trailingAnchor),

            batchCount.leadingAnchor.constraint(equalTo: batchBar.leadingAnchor, constant: 10),
            batchCount.centerYAnchor.constraint(equalTo: batchBar.centerYAnchor),
            batchCount.heightAnchor.constraint(equalToConstant: 18),
            batchCount.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),

            batchLabel.leadingAnchor.constraint(equalTo: batchCount.trailingAnchor, constant: 6),
            batchLabel.centerYAnchor.constraint(equalTo: batchBar.centerYAnchor),

            batchSelectAll.leadingAnchor.constraint(equalTo: batchLabel.trailingAnchor, constant: 4),
            batchSelectAll.centerYAnchor.constraint(equalTo: batchBar.centerYAnchor),

            pager.bottomAnchor.constraint(equalTo: footer.topAnchor),
            pager.leadingAnchor.constraint(equalTo: leadingAnchor),
            pager.trailingAnchor.constraint(equalTo: trailingAnchor),
            pager.heightAnchor.constraint(equalToConstant: 32),

            pagerInfoLbl.trailingAnchor.constraint(equalTo: pager.trailingAnchor, constant: -10),
            pagerInfoLbl.centerYAnchor.constraint(equalTo: pager.centerYAnchor),

            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: 28),

            footerStatus.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            footerStatus.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            gearBtn.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -10),
            gearBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])

        // 批量按钮栏右侧布局:从右到左 [完成 | divider | 删除 转任务 已读]
        let trailingPad: CGFloat = 8
        NSLayoutConstraint.activate([
            escBtn.trailingAnchor.constraint(equalTo: batchBar.trailingAnchor, constant: -trailingPad),
            escBtn.centerYAnchor.constraint(equalTo: batchBar.centerYAnchor),
            escBtn.heightAnchor.constraint(equalToConstant: 22),
            escBtn.widthAnchor.constraint(equalToConstant: 52),

            escDivider.trailingAnchor.constraint(equalTo: escBtn.leadingAnchor, constant: -6),
            escDivider.centerYAnchor.constraint(equalTo: batchBar.centerYAnchor),
            escDivider.widthAnchor.constraint(equalToConstant: 0.5),
            escDivider.heightAnchor.constraint(equalToConstant: 16),
        ])
        var prev: NSView = escDivider
        for b in batchActionButtons.reversed() {
            b.trailingAnchor.constraint(equalTo: prev.leadingAnchor, constant: -4).isActive = true
            b.centerYAnchor.constraint(equalTo: batchBar.centerYAnchor).isActive = true
            b.heightAnchor.constraint(equalToConstant: 22).isActive = true
            prev = b
        }
        // ★ 防止左侧标签组和右侧按钮组重叠 — 全选按钮右边缘 ≤ 最左侧动作按钮左边缘
        if let leftmost = batchActionButtons.first {
            batchSelectAll.trailingAnchor.constraint(
                lessThanOrEqualTo: leftmost.leadingAnchor, constant: -6
            ).isActive = true
        }
    }

    // MARK: - 私有 helpers

    private func thinDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    private func styleSmallTextBtn(_ b: NSButton, title: String, color: NSColor, action: Selector) {
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.focusRingType = .none
        b.target = self
        b.action = action
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: LazyCatTheme.body(11, weight: .semibold),
        ])
        b.translatesAutoresizingMaskIntoConstraints = false
    }

    /// 批量栏按钮 .bbtn:padding 5×9, 圆角 5, 字 11.5/600,默认透明背景
    /// padding 用左右空格做(NSButton 没 contentInsets)
    private func styleBatchActionBtn(_ b: NSButton, title: String, color: NSColor, width: CGFloat = 48) {
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.focusRingType = .none
        b.wantsLayer = true
        b.layer?.cornerRadius = 4
        b.layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
        b.layer?.borderWidth = 0.5
        b.layer?.borderColor = color.withAlphaComponent(0.3).cgColor
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: color,
            .font: LazyCatTheme.body(10.5, weight: .semibold),
            .paragraphStyle: ps,
        ])
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    // MARK: - 数据 / 渲染

    /// 当前过滤后的所有消息(未分页 / 未合并)
    private func filteredItems() -> [InboxMessage] {
        let all = TelegramTDLib.shared.inbox
        switch currentTab {
        case .all:   return all
        case .dm:    return all.filter { $0.isPrivate }
        case .group: return all.filter { !$0.isPrivate }
        case .alert: return all.filter { isAlertMessage($0) }
        }
    }

    /// ★ 列表渲染入口:在 filteredItems 之上做"同 senderId 私聊合并"。
    ///   群聊 / 报警每条独立(报警没必要再聚合,容易掩盖关键告警)。
    private func renderEntries() -> [InboxRenderEntry] {
        let raw = filteredItems()
        // 私聊合并条件:tab=.all 或 .dm 时启用;.group / .alert 不合并(分别有自己的语义)
        let mergePrivate = (currentTab == .all || currentTab == .dm)
        guard mergePrivate else {
            return raw.map { InboxRenderEntry(representative: $0, mergedIds: [$0.id]) }
        }
        var keyToEntryIdx: [String: Int] = [:]
        var entries: [InboxRenderEntry] = []

        for m in raw {
            // 群聊照原样输出
            if !m.isPrivate {
                entries.append(InboxRenderEntry(representative: m, mergedIds: [m.id]))
                continue
            }
            // 私聊按 senderId 合并
            let key = "p_\(m.senderId)"
            if let idx = keyToEntryIdx[key] {
                var ids = entries[idx].mergedIds
                ids.append(m.id)
                let oldRep = entries[idx].representative
                let newRep = (m.date > oldRep.date) ? m : oldRep
                entries[idx] = InboxRenderEntry(representative: newRep, mergedIds: ids)
            } else {
                keyToEntryIdx[key] = entries.count
                entries.append(InboxRenderEntry(representative: m, mergedIds: [m.id]))
            }
        }
        // 排序:按代表的 date 从新到旧(raw 已经按 inbox 顺序;TelegramTDLib 推送通常已是新→旧
        // 但合并后代表可能变,这里再保一次稳)
        entries.sort { $0.representative.date > $1.representative.date }
        return entries
    }

    /// 该发件人在 24h 内是否已有未完成的私聊任务 — 用于决定按钮显示
    /// "＋ 转任务" 还是 "＋ 追加到已有任务"。逻辑必须与 ContentViewController.convertTGToTask 一致。
    private func hasOpenPrivateTask(forSender name: String) -> Bool {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return Store.shared.data.tasks.contains {
            !$0.completed
            && $0.tgChatType == "private"
            && $0.person == name
            && $0.createdAt >= cutoff
        }
    }

    private func isAlertMessage(_ m: InboxMessage) -> Bool {
        guard let re = Self.alertRegex else { return false }
        let s = m.text as NSString
        return re.firstMatch(in: m.text, range: NSRange(location: 0, length: s.length)) != nil
    }

    private func tabCount(_ tab: Tab) -> Int {
        let all = TelegramTDLib.shared.inbox
        switch tab {
        case .all:   return all.count
        case .dm:    return all.filter { $0.isPrivate }.count
        case .group: return all.filter { !$0.isPrivate }.count
        case .alert: return all.filter { isAlertMessage($0) }.count
        }
    }

    func refresh() {
        // 过滤 → 合并 → 翻页(注意:total 用合并后的 entries 数,与翻页栏一致)
        let entries = renderEntries()
        let total = entries.count
        let pageCount = max(1, Int(ceil(Double(total) / Double(pageSize))))
        if currentPage > pageCount { currentPage = pageCount }
        if currentPage < 1 { currentPage = 1 }
        let startIdx = (currentPage - 1) * pageSize
        let endIdx = min(startIdx + pageSize, total)
        let pageEntries = (startIdx < endIdx) ? Array(entries[startIdx..<endIdx]) : []

        // header
        let unread = TelegramTDLib.shared.inbox.filter { !$0.read }.count
        countPill.isHidden = (unread == 0)
        countPill.attributedStringValue = NSAttributedString(string: " \(unread) ", attributes: [
            .foregroundColor: NSColor.white,
            .font: LazyCatTheme.body(10.5, weight: .bold),
        ])
        // 批量处理按钮:.select-mode 药丸,普通 rgba(0,0,0,.04) 灰底,激活 TG 蓝底白字
        let tg = NSColor(red: 0.13, green: 0.62, blue: 0.85, alpha: 1)
        let selectTitle = batchMode ? "  ✓ 批量中  " : "  批量处理  "
        selectBtn.attributedTitle = NSAttributedString(
            string: selectTitle,
            attributes: [
                .foregroundColor: batchMode ? NSColor.white : LazyCatTheme.tx2,
                .font: LazyCatTheme.body(11, weight: .semibold),
            ])
        selectBtn.layer?.backgroundColor = (batchMode
            ? tg
            : NSColor.black.withAlphaComponent(0.04)).cgColor

        // tab 内 [title][badge] 都由 TGTabItem.update 一起做,确保不飘
        let names = ["全部", "私聊", "群 @", "报警"]
        let cnts = [tabCount(.all), tabCount(.dm), tabCount(.group), tabCount(.alert)]
        for (i, item) in tabItems.enumerated() {
            let isActive = (i == currentTab.rawValue)
            let isAlert = (i == Tab.alert.rawValue)
            let accentColor = isAlert ? LazyCatTheme.red : tg
            item.update(title: names[i], count: cnts[i], isActive: isActive, accentColor: accentColor)
        }

        // 列表重建
        for v in stack.arrangedSubviews { stack.removeArrangedSubview(v) }
        for v in stack.subviews { v.removeFromSuperview() }

        if pageEntries.isEmpty {
            emptyLbl.isHidden = false
            docHeight.constant = 60
        } else {
            emptyLbl.isHidden = true
            var h: CGFloat = stack.edgeInsets.top + stack.edgeInsets.bottom
            for entry in pageEntries {
                let rep = entry.representative
                // 选中态:合并组只要任一 id 在 selectedIds 都算选中
                let isGroupSelected = entry.mergedIds.contains(where: { selectedIds.contains($0) })
                let appendMode = rep.isPrivate && hasOpenPrivateTask(forSender: rep.senderName)
                let row = TGInboxRow(
                    item: rep,
                    batchMode: batchMode,
                    selected: isGroupSelected,
                    isAlert: isAlertMessage(rep),
                    mergedCount: entry.mergedCount,
                    appendMode: appendMode)
                let allIds = entry.mergedIds
                row.onConvert = { [weak self] in
                    guard let self = self else { return }
                    // 合并组 → 把组内所有未读消息按时间正序逐条转任务,同人 24h 合并逻辑由
                    // ContentViewController.convertTGToTask 保证:第一条建任务,其余追加。
                    let inbox = TelegramTDLib.shared.inbox
                    let groupItems = inbox
                        .filter { allIds.contains($0.id) }
                        .sorted { $0.date < $1.date }
                    for m in groupItems {
                        self.onConvertToTask?(m)
                    }
                }
                row.onDismiss = {
                    for id in allIds { TelegramTDLib.shared.dismiss(id) }
                }
                row.onCheckToggle = { [weak self] in
                    guard let self = self else { return }
                    if isGroupSelected {
                        for id in allIds { self.selectedIds.remove(id) }
                    } else {
                        for id in allIds { self.selectedIds.insert(id) }
                    }
                    self.refresh()
                }
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
                h += TGInboxRow.estimatedHeight(for: rep) + stack.spacing
            }
            docHeight.constant = max(h, 100)
        }

        // 批量栏(N / 共 M 用"组"维度,与用户实际看到的卡片数一致)
        batchBar.isHidden = !batchMode
        batchBarHeight.constant = batchMode ? 40 : 0
        let selectedGroupCount = entries.filter { e in
            e.mergedIds.contains(where: { selectedIds.contains($0) })
        }.count
        batchCount.attributedStringValue = NSAttributedString(
            string: " \(selectedGroupCount) ",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: LazyCatTheme.body(10.5, weight: .bold),
            ])
        batchLabel.stringValue = "已选 / \(total)"

        // 翻页栏:设计图 ‹ 1 2 [3] 4 … N › ── 当前页用 accent 实心,其余透明
        // 清掉旧的按钮和数字 label(保留 pagerInfoLbl 和分割线)
        for sub in pager.subviews
            where sub !== pagerInfoLbl
                && (sub is NSButton || (sub is NSTextField && (sub as? NSTextField) !== pagerInfoLbl)) {
            sub.removeFromSuperview()
        }
        let prevB = makePagerArrow("‹", enabled: currentPage > 1, action: #selector(actPrevPage))
        let nextB = makePagerArrow("›", enabled: currentPage < pageCount, action: #selector(actNextPage))
        pager.addSubview(prevB)
        pager.addSubview(nextB)
        NSLayoutConstraint.activate([
            prevB.leadingAnchor.constraint(equalTo: pager.leadingAnchor, constant: 8),
            prevB.centerYAnchor.constraint(equalTo: pager.centerYAnchor),
            prevB.widthAnchor.constraint(equalToConstant: 24),
            prevB.heightAnchor.constraint(equalToConstant: 24),
        ])
        // 数字按钮(含省略号)
        let pageNums = pageNumbersToShow(current: currentPage, total: pageCount)
        var leftAnchor = prevB.trailingAnchor
        for n in pageNums {
            let v: NSView
            if n == -1 {
                // 省略号
                let lbl = NSTextField(labelWithString: "…")
                lbl.font = LazyCatTheme.body(11, weight: .medium)
                lbl.textColor = LazyCatTheme.tx3
                lbl.drawsBackground = false
                lbl.isBezeled = false
                lbl.alignment = .center
                lbl.translatesAutoresizingMaskIntoConstraints = false
                pager.addSubview(lbl)
                v = lbl
            } else {
                let isCurrent = (n == currentPage)
                let nb = NSButton(title: "\(n)", target: self, action: #selector(actGotoPage(_:)))
                nb.tag = n
                nb.bezelStyle = .regularSquare
                nb.isBordered = false
                nb.focusRingType = .none
                nb.wantsLayer = true
                nb.layer?.cornerRadius = 5
                nb.layer?.backgroundColor = isCurrent ? LazyCatTheme.accent.cgColor : NSColor.clear.cgColor
                nb.attributedTitle = NSAttributedString(string: " \(n) ", attributes: [
                    .foregroundColor: isCurrent ? NSColor.white : LazyCatTheme.tx2,
                    .font: LazyCatTheme.body(11, weight: .semibold),
                ])
                nb.translatesAutoresizingMaskIntoConstraints = false
                pager.addSubview(nb)
                nb.heightAnchor.constraint(equalToConstant: 24).isActive = true
                nb.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
                v = nb
            }
            v.leadingAnchor.constraint(equalTo: leftAnchor, constant: 2).isActive = true
            v.centerYAnchor.constraint(equalTo: pager.centerYAnchor).isActive = true
            leftAnchor = v.trailingAnchor
        }
        NSLayoutConstraint.activate([
            nextB.leadingAnchor.constraint(equalTo: leftAnchor, constant: 4),
            nextB.centerYAnchor.constraint(equalTo: pager.centerYAnchor),
            nextB.widthAnchor.constraint(equalToConstant: 24),
            nextB.heightAnchor.constraint(equalToConstant: 24),
        ])
        pagerInfoLbl.stringValue = "第 \(currentPage) / \(pageCount) 页 · 共 \(total) 条"

        // footer 状态
        let st = TelegramTDLib.shared.authState
        let (dot, txt): (String, String)
        switch st {
        case .ready:              (dot, txt) = ("🟢", "已连接 · 监听中")
        case .waitingTdParams:    (dot, txt) = ("🟠", "未配置 · 点 ⚙ 设置")
        case .waitingEncryptionKey:(dot, txt) = ("🟠", "初始化中…")
        case .waitingPhoneNumber: (dot, txt) = ("🟠", "等待手机号")
        case .waitingCode:        (dot, txt) = ("🟠", "等待验证码")
        case .waitingPassword:    (dot, txt) = ("🟠", "等待 2FA 密码")
        case .loggingOut:         (dot, txt) = ("🟡", "正在登出…")
        case .closed:             (dot, txt) = ("⚫", "未连接")
        case .unknown:            (dot, txt) = ("⚫", "启动中…")
        }
        footerStatus.stringValue = "\(dot) \(txt)"
    }

    // MARK: - actions

    @objc private func actMarkAllRead() {
        TelegramTDLib.shared.markAllRead()
    }
    @objc private func actOpenSettings() {
        onOpenSettings?()
    }
    @objc private func actToggleBatch() {
        batchMode.toggle()
        if !batchMode { selectedIds.removeAll() }
        refresh()
    }
    /// esc 按钮 / 后续支持 ⎋ 键 — 退出批量模式
    @objc private func actExitBatch() {
        batchMode = false
        selectedIds.removeAll()
        refresh()
    }
    @objc private func actBatchSelectAll() {
        // 全选 / 取消全选用"组"维度判断:
        //   - 当前页面所有 entry 都至少有一个 id 在 selectedIds → 取消全选(清空选中)
        //   - 否则 → 把所有 entry 的所有 mergedIds 都加进来
        let entries = renderEntries()
        let allSelected = !entries.isEmpty && entries.allSatisfy { e in
            e.mergedIds.contains(where: { selectedIds.contains($0) })
        }
        if allSelected {
            selectedIds.removeAll()
        } else {
            selectedIds = Set(entries.flatMap { $0.mergedIds })
        }
        refresh()
    }
    @objc private func actBatchMarkRead() {
        // 简单做法:未读全部置已读(精确 per-id markRead 没单独 API,等后续加)
        TelegramTDLib.shared.markAllRead()
        selectedIds.removeAll()
        batchMode = false
        refresh()
    }
    @objc private func actBatchConvert() {
        let items = TelegramTDLib.shared.inbox.filter { selectedIds.contains($0.id) }
        for it in items { onConvertToTask?(it) }
        selectedIds.removeAll()
        batchMode = false
        refresh()
    }
    @objc private func actBatchDelete() {
        for id in selectedIds { TelegramTDLib.shared.dismiss(id) }
        selectedIds.removeAll()
        batchMode = false
        refresh()
    }
    @objc private func actPrevPage() {
        if currentPage > 1 { currentPage -= 1; refresh() }
    }
    @objc private func actNextPage() {
        currentPage += 1
        refresh()
    }
    @objc private func actGotoPage(_ sender: NSButton) {
        let n = sender.tag
        guard n > 0 else { return }
        currentPage = n
        refresh()
    }

    /// pager arrow factory
    private func makePagerArrow(_ glyph: String, enabled: Bool, action: Selector) -> NSButton {
        let b = NSButton(title: glyph, target: self, action: action)
        b.bezelStyle = .regularSquare
        b.isBordered = false
        b.focusRingType = .none
        b.wantsLayer = true
        b.layer?.cornerRadius = 5
        b.attributedTitle = NSAttributedString(string: glyph, attributes: [
            .foregroundColor: enabled ? LazyCatTheme.tx1 : LazyCatTheme.tx4,
            .font: LazyCatTheme.body(14, weight: .semibold),
        ])
        b.isEnabled = enabled
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    /// 设计图 .tg-pager 行为:头尾页 + 当前页周围 ±1,中间用 -1 表示省略号 …
    /// 例如 total=9 current=2 → [1,2,3,4,-1,9]
    /// total<=7 直接全列出
    private func pageNumbersToShow(current: Int, total: Int) -> [Int] {
        guard total > 0 else { return [] }
        if total <= 7 { return Array(1...total) }
        var pages: Set<Int> = [1, total, current, current - 1, current + 1, 2, total - 1]
        pages = pages.filter { $0 >= 1 && $0 <= total }
        let sorted = pages.sorted()
        var result: [Int] = []
        for (i, n) in sorted.enumerated() {
            if i > 0, n - sorted[i - 1] > 1 { result.append(-1) }
            result.append(n)
        }
        return result
    }
}

// MARK: - 单条 row (v2: 时间独占一行 / 选择 checkbox / 暖橘按钮)

private final class TGInboxRow: NSView {
    let item: InboxMessage
    var onConvert: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onCheckToggle: (() -> Void)?

    private let batchMode: Bool
    private let selected: Bool
    private let isAlert: Bool
    /// 合并组消息条数;>=2 时显示 +N 条 角标
    private let mergedCount: Int
    /// true → "＋ 转任务" 显示成"＋ 追加到已有任务"(append 浅蓝样式),
    ///        说明该发件人 24h 内已有未完成同人私聊任务,转任务会追加到那条上。
    private let appendMode: Bool

    init(item: InboxMessage, batchMode: Bool, selected: Bool, isAlert: Bool,
         mergedCount: Int = 1, appendMode: Bool = false) {
        self.item = item
        self.batchMode = batchMode
        self.selected = selected
        self.isAlert = isAlert
        self.mergedCount = mergedCount
        self.appendMode = appendMode
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    static func estimatedHeight(for item: InboxMessage) -> CGFloat {
        // 强制按"3 行文本上限"算固定高度,跟 build() 里的 textHeight 必须保持一致
        let isGroup = !item.isPrivate && !item.sourceLabel.isEmpty
        let groupRow: CGFloat = isGroup ? 18 : 0
        let imageH: CGFloat = (item.imageLocalPath != nil) ? 86 : 0
        // header(头像 30) + group row + text(3行*17=51) + when(18) + actions(30) + paddings(20)
        return 30 + groupRow + 51 + imageH + 18 + 30 + 18
    }

    /// 把多行 / 长文本压成单字符串(\n → 空格,限 200 字),
    /// 交给 wrappingLabel + 行高约束自然折行 + truncate
    private static func compactText(_ s: String) -> String {
        let oneLine = s
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.count > 200 {
            return String(oneLine.prefix(200)) + "…"
        }
        return oneLine
    }

    private func build() {
        let tg = NSColor(red: 0.13, green: 0.62, blue: 0.85, alpha: 1)
        let red = LazyCatTheme.red
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = selected
            ? NSColor(red: 0.92, green: 0.96, blue: 0.99, alpha: 1).cgColor
            : NSColor.white.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = selected ? 1 : 0.5
        card.layer?.borderColor = selected
            ? tg.cgColor
            : NSColor.black.withAlphaComponent(0.06).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        // 未读 / 报警左色条
        let leftBarColor: NSColor? = isAlert ? red : (item.read ? nil : tg)
        if let cc = leftBarColor {
            let mark = NSView()
            mark.wantsLayer = true
            mark.layer?.backgroundColor = cc.cgColor
            mark.layer?.cornerRadius = 1.5
            mark.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(mark)
            NSLayoutConstraint.activate([
                mark.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                mark.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
                mark.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
                mark.widthAnchor.constraint(equalToConstant: 3),
            ])
        }

        let leftPad: CGFloat = leftBarColor == nil ? 12 : 14

        // checkbox(批量模式)
        var checkBox: NSButton? = nil
        if batchMode {
            let cb = NSButton(title: selected ? "✓" : "", target: self, action: #selector(actToggleCheck))
            cb.bezelStyle = .regularSquare
            cb.isBordered = false
            cb.focusRingType = .none
            cb.wantsLayer = true
            cb.layer?.cornerRadius = 5
            cb.layer?.backgroundColor = selected ? tg.cgColor : NSColor.white.cgColor
            cb.layer?.borderWidth = 1.5
            cb.layer?.borderColor = selected ? tg.cgColor : NSColor.black.withAlphaComponent(0.15).cgColor
            cb.attributedTitle = NSAttributedString(string: selected ? "✓" : "", attributes: [
                .foregroundColor: NSColor.white,
                .font: LazyCatTheme.body(13, weight: .bold),
            ])
            cb.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(cb)
            checkBox = cb
        }

        // 头像 — 设计图 135deg 渐变(GradientAvatar 自带圆角 + 白字)
        let av = GradientAvatar(
            letter: String(item.senderName.prefix(1)),
            colors: avatarGradient(for: item.senderName))
        card.addSubview(av)

        // sender name
        let who = NSTextField(labelWithString: item.senderName)
        who.font = LazyCatTheme.body(13, weight: .bold)
        who.textColor = LazyCatTheme.tx1
        who.lineBreakMode = .byTruncatingTail
        who.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(who)

        // pill (报警 / 私聊 / 群@)
        let pill = NSTextField(labelWithString: "")
        let pillColor: NSColor
        let pillFg: NSColor
        let pillTxt: String
        if isAlert {
            pillColor = NSColor(red: 1.00, green: 0.88, blue: 0.86, alpha: 1)
            pillFg = red
            pillTxt = item.isPrivate ? " 报警 · 私聊 " : " 报警 · 群 @ "
        } else if item.isPrivate {
            pillColor = tg; pillFg = .white; pillTxt = " 私聊 "
        } else {
            pillColor = NSColor(red: 0.84, green: 0.92, blue: 0.97, alpha: 1)
            pillFg = NSColor(red: 0.10, green: 0.49, blue: 0.69, alpha: 1)
            pillTxt = " 群 @ "
        }
        pill.attributedStringValue = NSAttributedString(string: pillTxt, attributes: [
            .foregroundColor: pillFg,
            .font: LazyCatTheme.body(10, weight: .bold),
        ])
        pill.alignment = .center
        pill.wantsLayer = true
        pill.layer?.backgroundColor = pillColor.cgColor
        pill.layer?.cornerRadius = 4
        pill.drawsBackground = false
        pill.isBezeled = false
        pill.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(pill)

        // ✕
        let xBtn = NSButton(title: "×", target: self, action: #selector(actDismiss))
        xBtn.bezelStyle = .regularSquare
        xBtn.isBordered = false
        xBtn.focusRingType = .none
        xBtn.wantsLayer = true
        xBtn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        xBtn.layer?.cornerRadius = 11
        xBtn.attributedTitle = NSAttributedString(string: "×", attributes: [
            .foregroundColor: LazyCatTheme.tx3,
            .font: LazyCatTheme.body(13, weight: .bold),
        ])
        xBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(xBtn)

        // 群名一行(仅群@)
        var sourceLine: NSTextField? = nil
        if !item.isPrivate, !item.sourceLabel.isEmpty {
            let s = NSTextField(labelWithString: item.sourceLabel)
            s.font = LazyCatTheme.body(11, weight: .medium)
            s.textColor = LazyCatTheme.tx3
            s.lineBreakMode = .byTruncatingTail
            s.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(s)
            sourceLine = s
        }

        // 文本(已压成单行 / \n→空格,wrappingLabel 自然 3 行折行)
        let text = NSTextField(wrappingLabelWithString: Self.compactText(item.text))
        text.font = LazyCatTheme.body(13, weight: .regular)
        text.textColor = LazyCatTheme.tx1
        text.maximumNumberOfLines = 3
        text.lineBreakMode = .byTruncatingTail
        text.cell?.truncatesLastVisibleLine = true
        text.preferredMaxLayoutWidth = 240
        text.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(text)

        // 缩略图(可选)
        var imageBtn: NSButton? = nil
        if let path = item.imageLocalPath, let img = NSImage(contentsOfFile: path) {
            let btn = NSButton(image: img, target: self, action: #selector(actOpenImage))
            btn.imageScaling = .scaleProportionallyUpOrDown
            btn.bezelStyle = .shadowlessSquare
            btn.isBordered = false
            btn.focusRingType = .none
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.masksToBounds = true
            btn.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(btn)
            imageBtn = btn
        }

        // 时间(独占一行)
        let when = NSTextField(labelWithString: "🕐  " + relativeTime(item.date))
        when.font = LazyCatTheme.body(11, weight: .medium)
        when.textColor = LazyCatTheme.tx3
        when.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(when)

        // 转任务 / 追加到已有任务 / 已处理 — 设计图 .btn:padding 6×12, 圆角 6, 字 11.5/700
        // NSButton 没 contentInset,改用固定 width 控制 padding,默认 title 居中对齐
        let convertTitle: String
        let convertBg: NSColor
        let convertFg: NSColor
        let convertWidth: CGFloat
        if appendMode {
            // .btn.append: bg #eaf4fb(tg-vsoft), fg #1A7CB0(tg-dark)
            convertTitle = "＋ 追加到已有任务"
            convertBg = NSColor(red: 0.92, green: 0.96, blue: 0.98, alpha: 1)
            convertFg = NSColor(red: 0.10, green: 0.49, blue: 0.69, alpha: 1)
            convertWidth = 134
        } else {
            // .btn.primary: bg #FF8C42(accent), fg white
            convertTitle = "＋ 转任务"
            convertBg = LazyCatTheme.accent
            convertFg = .white
            convertWidth = 84
        }
        let convertBtn = NSButton(title: convertTitle, target: self, action: #selector(actConvert))
        convertBtn.bezelStyle = .regularSquare
        convertBtn.isBordered = false
        convertBtn.focusRingType = .none
        convertBtn.alignment = .center
        convertBtn.wantsLayer = true
        convertBtn.layer?.backgroundColor = convertBg.cgColor
        convertBtn.layer?.cornerRadius = 6
        let convertPara = NSMutableParagraphStyle()
        convertPara.alignment = .center
        convertBtn.attributedTitle = NSAttributedString(string: convertTitle, attributes: [
            .foregroundColor: convertFg,
            .font: LazyCatTheme.body(11.5, weight: .bold),
            .paragraphStyle: convertPara,
        ])
        convertBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(convertBtn)

        // .btn.ghost: bg rgba(0,0,0,.04), fg tx-2
        let doneTitle = "已处理"
        let doneBtn = NSButton(title: doneTitle, target: self, action: #selector(actDismiss))
        doneBtn.bezelStyle = .regularSquare
        doneBtn.isBordered = false
        doneBtn.focusRingType = .none
        doneBtn.alignment = .center
        doneBtn.wantsLayer = true
        doneBtn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        doneBtn.layer?.cornerRadius = 6
        let donePara = NSMutableParagraphStyle()
        donePara.alignment = .center
        doneBtn.attributedTitle = NSAttributedString(string: doneTitle, attributes: [
            .foregroundColor: LazyCatTheme.tx2,
            .font: LazyCatTheme.body(11.5, weight: .bold),
            .paragraphStyle: donePara,
        ])
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(doneBtn)

        // ★ +N 条 角标(仅合并组,position 同设计图 top:9 right:35,在 ✕ 左侧)
        var multiIndicator: NSTextField? = nil
        if mergedCount >= 2 {
            let mi = NSTextField(labelWithString: "")
            mi.alignment = .center
            mi.wantsLayer = true
            mi.layer?.backgroundColor = tg.cgColor
            mi.layer?.cornerRadius = 8
            mi.layer?.masksToBounds = true
            mi.drawsBackground = false
            mi.isBezeled = false
            mi.attributedStringValue = NSAttributedString(
                string: " +\(mergedCount) 条 ",
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: LazyCatTheme.body(9.5, weight: .bold),
                ])
            mi.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(mi)
            multiIndicator = mi
        }

        // ── 约束 ──
        let cb = checkBox
        let avLeading: NSLayoutXAxisAnchor = cb?.trailingAnchor ?? card.leadingAnchor
        let avLeadingPad: CGFloat = cb != nil ? 6 : leftPad

        // ★ 整行强制固定高度,与 estimatedHeight 一致;text 高度 51pt(3 行 ×17),溢出截断
        let rowHeight = TGInboxRow.estimatedHeight(for: item)

        var cons: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: rowHeight),

            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            text.heightAnchor.constraint(equalToConstant: 51),

            av.leadingAnchor.constraint(equalTo: avLeading, constant: avLeadingPad),
            av.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
            av.widthAnchor.constraint(equalToConstant: 26),
            av.heightAnchor.constraint(equalToConstant: 26),

            who.leadingAnchor.constraint(equalTo: av.trailingAnchor, constant: 8),
            who.centerYAnchor.constraint(equalTo: av.centerYAnchor),
            who.trailingAnchor.constraint(lessThanOrEqualTo: pill.leadingAnchor, constant: -6),

            pill.leadingAnchor.constraint(greaterThanOrEqualTo: who.trailingAnchor, constant: 6),
            pill.centerYAnchor.constraint(equalTo: av.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: 16),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: xBtn.leadingAnchor, constant: -4),

            xBtn.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            xBtn.centerYAnchor.constraint(equalTo: av.centerYAnchor),
            xBtn.widthAnchor.constraint(equalToConstant: 22),
            xBtn.heightAnchor.constraint(equalToConstant: 22),

            text.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: leftPad),
            text.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),

            when.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: leftPad),

            convertBtn.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: leftPad),
            convertBtn.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            convertBtn.heightAnchor.constraint(equalToConstant: 28),
            convertBtn.widthAnchor.constraint(equalToConstant: convertWidth),

            doneBtn.leadingAnchor.constraint(equalTo: convertBtn.trailingAnchor, constant: 6),
            doneBtn.centerYAnchor.constraint(equalTo: convertBtn.centerYAnchor),
            doneBtn.heightAnchor.constraint(equalToConstant: 28),
            doneBtn.widthAnchor.constraint(equalToConstant: 64),
            doneBtn.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -10),

            when.bottomAnchor.constraint(equalTo: convertBtn.topAnchor, constant: -8),
        ]
        // +N 角标:绝对位 top 9 / right 35(贴 xBtn 左)
        if let mi = multiIndicator {
            cons += [
                mi.trailingAnchor.constraint(equalTo: xBtn.leadingAnchor, constant: -6),
                mi.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
                mi.heightAnchor.constraint(equalToConstant: 16),
            ]
        }
        if let cb = cb {
            cons += [
                cb.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: leftPad),
                cb.centerYAnchor.constraint(equalTo: av.centerYAnchor),
                cb.widthAnchor.constraint(equalToConstant: 18),
                cb.heightAnchor.constraint(equalToConstant: 18),
            ]
        }
        if let s = sourceLine {
            cons += [
                s.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: leftPad + 34),
                s.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
                s.topAnchor.constraint(equalTo: av.bottomAnchor, constant: 4),
                text.topAnchor.constraint(equalTo: s.bottomAnchor, constant: 4),
            ]
        } else {
            cons += [text.topAnchor.constraint(equalTo: av.bottomAnchor, constant: 6)]
        }
        if let ib = imageBtn {
            cons += [
                ib.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: leftPad),
                ib.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -10),
                ib.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 6),
                ib.heightAnchor.constraint(equalToConstant: 76),
                ib.widthAnchor.constraint(equalToConstant: 120),
            ]
        }
        NSLayoutConstraint.activate(cons)
    }

    @objc private func actConvert() { onConvert?() }
    @objc private func actDismiss() { onDismiss?() }
    @objc private func actToggleCheck() { onCheckToggle?() }
    @objc private func actOpenImage() {
        guard let path = item.imageLocalPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// 与设计图 .tg-card .av / .av.alt1-4 五条 135deg 渐变对齐
    private func avatarGradient(for name: String) -> [NSColor] {
        // 颜色 hex 与设计图原值一一对应
        let palette: [(NSColor, NSColor)] = [
            (NSColor(red: 0.365, green: 0.678, blue: 0.886, alpha: 1),     // #5DADE2
             NSColor(red: 0.157, green: 0.455, blue: 0.651, alpha: 1)),    // #2874A6
            (NSColor(red: 0.463, green: 0.843, blue: 0.769, alpha: 1),     // #76D7C4
             NSColor(red: 0.086, green: 0.627, blue: 0.522, alpha: 1)),    // #16A085
            (NSColor(red: 0.945, green: 0.580, blue: 0.541, alpha: 1),     // #F1948A
             NSColor(red: 0.753, green: 0.224, blue: 0.169, alpha: 1)),    // #C0392B
            (NSColor(red: 0.733, green: 0.561, blue: 0.808, alpha: 1),     // #BB8FCE
             NSColor(red: 0.424, green: 0.204, blue: 0.514, alpha: 1)),    // #6C3483
            (NSColor(red: 0.969, green: 0.863, blue: 0.435, alpha: 1),     // #F7DC6F
             NSColor(red: 0.718, green: 0.584, blue: 0.043, alpha: 1)),    // #B7950B
        ]
        let h = abs(name.hashValue) % palette.count
        let p = palette[h]
        return [p.0, p.1]
    }

    private func relativeTime(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "刚刚" }
        if s < 3600 { return "\(Int(s/60)) 分前" }
        if s < 86400 { return "\(Int(s/3600)) 小时前" }
        let f = DateFormatter(); f.dateFormat = "M/d HH:mm"; return f.string(from: d)
    }
}
