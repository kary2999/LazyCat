import AppKit

/// 桌面悬浮小窗：两种形态
///   - .expanded 列表面板（320x420）
///   - .collapsed 可拖动小圆球（一只猫 + 未完成数量徽标）
///     收到提醒时会抖动，点击展开为列表
final class FloatingWidgetController: NSWindowController {
    static let shared = FloatingWidgetController()

    enum Mode { case expanded, collapsed }
    private(set) var mode: Mode = .expanded

    // Expanded
    private let tableView = NSTableView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "暂无进行中事件")
    private let collapseBtn = NSButton(title: "–", target: nil, action: nil)
    private var tasks: [TodoItem] = []

    // Collapsed
    private var collapsedWindow: NSPanel?
    private let catView = CatBadgeView()

    // 上一次 expanded 的 frame，收起后再还原
    private var lastExpandedFrame: NSRect?

    private override init(window: NSWindow?) { super.init(window: window) }
    required init?(coder: NSCoder) { fatalError() }

    private convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "🐈 悬浮 · 进行中"
        panel.isMovableByWindowBackground = true
        panel.setFrameAutosaveName("MyTodoFloatingWidget")
        // ★ Style B：强制浅色 + 奶油底
        panel.appearance = NSAppearance(named: .aqua)
        panel.backgroundColor = LazyCatTheme.bg
        self.init(window: panel)
        panel.delegate = self
        setup()
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: Store.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onReminderFired(_:)),
                                               name: .reminderFired, object: nil)
        // 样式 / 尺寸切换时即时重画
        NotificationCenter.default.addObserver(self, selector: #selector(onWidgetSettingsChanged),
                                               name: FloatingWidgetSettings.didChangeNotification,
                                               object: nil)
        reload()
    }

    @objc private func onWidgetSettingsChanged() {
        // 收起态时重建小猫 panel；展开态不影响
        guard mode == .collapsed, let p = collapsedWindow else { return }
        let origin = p.frame.origin
        let s = FloatingWidgetSettings.shared.size.panelSize
        // 用旧 origin 做"中心保持" —— 缩放后视觉上不会跑很远
        let oldRect = p.frame
        let newRect = NSRect(x: oldRect.midX - s/2, y: oldRect.midY - s/2, width: s, height: s)
        p.setFrame(newRect, display: true, animate: false)
        catView.reloadStyleAndSize()
        _ = origin   // silence unused
    }

    private func setup() {
        guard let content = window?.contentView else { return }

        // 顶部工具条
        let addBtn = NSButton(title: "＋ 新建", target: self, action: #selector(openMain))
        addBtn.bezelStyle = .inline
        addBtn.font = .systemFont(ofSize: 11)

        let mainBtn = NSButton(title: "主窗口", target: self, action: #selector(openMain))
        mainBtn.bezelStyle = .inline
        mainBtn.font = .systemFont(ofSize: 11)

        collapseBtn.bezelStyle = .inline
        collapseBtn.font = .systemFont(ofSize: 14, weight: .bold)
        collapseBtn.target = self
        collapseBtn.action = #selector(collapse)
        collapseBtn.toolTip = "收起为小猫徽标"

        let toolbar = NSStackView(views: [addBtn, NSView(), mainBtn, collapseBtn])
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        // 列表
        tableView.headerView = nil
        tableView.rowHeight = 40
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.selectionHighlightStyle = .none
        tableView.gridStyleMask = []
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        let col = NSTableColumn(identifier: .init("t"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = LazyCatTheme.body(12, weight: .medium)
        emptyLabel.textColor = LazyCatTheme.textTer
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(toolbar)
        content.addSubview(scroll)
        content.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),

            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
    }

    // MARK: Public

    var isOpen: Bool {
        (window?.isVisible ?? false) || (collapsedWindow?.isVisible ?? false)
    }

    func toggle() {
        if isOpen { close() } else { showCollapsed() }
    }

    func showExpanded() {
        mode = .expanded
        collapsedWindow?.orderOut(nil)
        window?.makeKeyAndOrderFront(nil)
        reload()
    }

    /// 小猫徽标形态（默认）
    func showCollapsed() {
        mode = .collapsed
        window?.orderOut(nil)
        let origin = defaultCollapsedOrigin()
        showCollapsedPanel(at: origin)
    }

    private func defaultCollapsedOrigin() -> NSPoint {
        // 上次展开位置右上角；否则主屏右上角内 120pt
        if let f = window?.frame, f.origin.x > 0 {
            return NSPoint(x: f.origin.x + f.width - 80, y: f.origin.y + f.height - 80)
        }
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            return NSPoint(x: v.maxX - 100, y: v.maxY - 120)
        }
        return NSPoint(x: 500, y: 500)
    }

    override func close() {
        window?.orderOut(nil)
        collapsedWindow?.orderOut(nil)
    }

    // MARK: Collapse / Expand

    @objc private func collapse() {
        mode = .collapsed
        lastExpandedFrame = window?.frame
        // 默认收起到原窗口右上角位置
        let origin = window?.frame.origin ?? NSPoint(x: 300, y: 300)
        window?.orderOut(nil)
        showCollapsedPanel(at: origin)
    }

    @objc private func expand() {
        collapsedWindow?.orderOut(nil)
        mode = .expanded
        if let f = lastExpandedFrame {
            window?.setFrame(f, display: true)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    private func showCollapsedPanel(at origin: NSPoint) {
        let s = FloatingWidgetSettings.shared.size.panelSize
        if collapsedWindow == nil {
            let p = NSPanel(contentRect: NSRect(x: origin.x, y: origin.y, width: s, height: s),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = false   // ★ 关键：透明窗口默认带圆形 drop shadow，关掉
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isMovableByWindowBackground = true
            p.contentView = catView
            catView.onClick = { [weak self] in self?.expand() }
            collapsedWindow = p
        }
        if let p = collapsedWindow {
            // 尺寸可能在设置中变化过，每次显示都同步一次
            p.setFrame(NSRect(x: origin.x, y: origin.y, width: s, height: s),
                       display: true, animate: false)
            catView.reloadStyleAndSize()
            p.orderFrontRegardless()
            updateCatBadge()
        }
    }

    private func updateCatBadge() {
        let pending = Store.shared.data.tasks.filter { !$0.completed }.count
        catView.badgeCount = pending
    }

    @objc private func onReminderFired(_ note: Notification) {
        // 不管当前是不是收起态，都让猫抖一抖
        if mode != .collapsed { collapse() }       // 被提醒时主动收起，以免挡事
        catView.jiggle()
        updateCatBadge()
    }

    // MARK: expanded actions

    @objc private func reload() {
        tasks = Store.shared.data.tasks
            .filter { !$0.completed }
            .sorted { a, b in
                if a.priority.rawValue != b.priority.rawValue {
                    return a.priority.rawValue > b.priority.rawValue
                }
                return a.createdAt < b.createdAt
            }
        tableView.reloadData()
        emptyLabel.isHidden = !tasks.isEmpty
        updateCatBadge()
    }

    @objc private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showMainWindow()
        }
    }
}

extension FloatingWidgetController: NSWindowDelegate {
    /// 用户点 × / ⌘W 关闭快捷列表面板时，**自动切回悬浮猫**（不让悬浮窗就此消失）
    /// 想彻底关闭悬浮：菜单栏 → 桌面悬浮窗 (走的是 close() 路径，不会触发 windowWillClose)
    func windowWillClose(_ notification: Notification) {
        // 必须延后到下一个 runloop，因为此时 expanded window 还没真正 orderOut
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // 仅在用户没有把整体悬浮关掉的情况下才回到 collapsed
            // 判断方式：collapsedWindow 也已隐藏 → 说明是 close() 整体关；否则就重新展示
            if self.collapsedWindow?.isVisible == true {
                return   // collapsed 已经在显示（不应该到这里，但防御）
            }
            // 切到 collapsed
            self.showCollapsed()
        }
    }
}

extension FloatingWidgetController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { tasks.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        return FloatingRow(task: tasks[row]) { id in
            Store.shared.toggleComplete(id)
        }
    }
}

// MARK: - 小猫徽标视图（cat + 数字 + 抖动）

final class CatBadgeView: NSView {
    var onClick: (() -> Void)?
    var badgeCount: Int = 0 { didSet { needsDisplay = true } }

    /// 当前显示的样式（决定走 24 帧动画 还是 emoji 静态）
    private var currentStyle: FloatingWidgetSettings.CatStyle = .cat
    private var currentSize:  FloatingWidgetSettings.Size = .default

    private let catImageView = NSImageView()
    private let catHolder = NSView()   // 圆形裁剪 + 阴影（透明背景）
    private let badgeBG = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var idleTimer: Timer?

    private var spriteFrames: [NSImage] = []
    private var spriteIndex = 0
    private var spriteTimer: Timer?

    // 用变量代替硬约束，方便切尺寸时改值
    private var holderWConstraint: NSLayoutConstraint?
    private var holderHConstraint: NSLayoutConstraint?
    private var badgeWConstraint:  NSLayoutConstraint?
    private var badgeHConstraint:  NSLayoutConstraint?

    // ★ 打字状态相关
    private var typingResetTimer: Timer?       // 1.5s 内没新键就切回原图
    private var isInTypingMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        build()
        reloadStyleAndSize()

        // 监听全局 keyDown
        NotificationCenter.default.addObserver(self, selector: #selector(onTypingKey),
                                               name: .typingKeyDown, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onDayChanged),
                                               name: .typingDayChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        spriteTimer?.invalidate()
        idleTimer?.invalidate()
    }

    /// 设置变化时调用：重新加载帧 + 重新布局尺寸
    func reloadStyleAndSize() {
        let style = FloatingWidgetSettings.shared.style
        let size  = FloatingWidgetSettings.shared.size
        currentStyle = style
        currentSize  = size

        // 容器尺寸
        // - 猫：panel - 8（贴边）
        // - 企鹅：panel × 0.6（再缩小一档；徽章贴 holder 边缘自然跟着内缩）
        let panelPt = size.panelSize
        let holderPt: CGFloat = (style == .penguin)
            ? max(20, panelPt * 0.6)
            : max(20, panelPt - 8)
        holderWConstraint?.constant = holderPt
        holderHConstraint?.constant = holderPt
        catHolder.layer?.cornerRadius = 0   // 不再画圆背景

        // 徽章尺寸（红圈未完成数）
        let bs = size.badgeSize
        badgeWConstraint?.constant = bs
        badgeHConstraint?.constant = bs
        badgeBG.layer?.cornerRadius = bs / 2
        badgeLabel.font = .systemFont(ofSize: size.badgeFontSize, weight: .bold)

        // ★ 切形态前清掉所有 layer 动画 + 重置 transform，避免新图被旧 transform 拖偏
        catHolder.layer?.removeAllAnimations()
        catImageView.layer?.removeAllAnimations()
        catHolder.layer?.transform = CATransform3DIdentity
        catImageView.layer?.transform = CATransform3DIdentity

        // 退出可能残留的"打字数字"模式
        isInTypingMode = false
        typingResetTimer?.invalidate()
        typingResetTimer = nil

        // 重新生成精灵帧
        spriteIndex = 0
        spriteFrames = Self.framesForStyle(style, size: NSSize(width: holderPt, height: holderPt))
        catImageView.image = spriteFrames.first
        // 两种形态都是 24 帧动画 — 启动 sprite timer
        spriteTimer?.invalidate()
        if spriteFrames.count > 1 {
            startSpriteAnimation()
        }

        // 应用悬浮动画体的透明度（仅 catHolder/catImageView，不动 badgeBG/badgeLabel）
        let alpha = FloatingWidgetSettings.shared.alpha
        catHolder.alphaValue = alpha
        catImageView.alphaValue = 1.0
        badgeBG.alphaValue    = 1.0       // ★ 小红点固定不透明
        badgeLabel.alphaValue = 1.0

        // ★ 强制立刻 layout，否则约束更新需要等下一次 runloop 才生效，
        //   期间 catImageView.frame 还是旧值 → 图按错的 size 渲染 → 视觉偏移
        needsLayout = true
        layoutSubtreeIfNeeded()

        needsDisplay = true
    }

    private func build() {
        // 透明圆形容器，只保留柔软阴影，不再用蓝底
        catHolder.wantsLayer = true
        // 透明容器：仅作为 scale/bob 动画的承载层。**不再画圆形底盘 / 阴影**
        // —— 用户嫌圆背景丑，希望企鹅/猫的透明 PNG 直接显在桌面
        catHolder.layer?.cornerRadius = 0
        catHolder.layer?.masksToBounds = false
        catHolder.layer?.backgroundColor = NSColor.clear.cgColor
        catHolder.layer?.shadowColor = nil
        catHolder.layer?.shadowOpacity = 0
        catHolder.translatesAutoresizingMaskIntoConstraints = false

        // 帧由 reloadStyleAndSize() 在初始化时统一加载
        catImageView.imageScaling = .scaleProportionallyUpOrDown
        catImageView.imageAlignment = .alignCenter   // ★ 切形态时强制居中，避免错位
        catImageView.wantsLayer = true
        catImageView.layer?.cornerRadius = 0   // 图片本身带透明背景，不用裁剪
        catImageView.layer?.masksToBounds = false
        catImageView.translatesAutoresizingMaskIntoConstraints = false

        badgeBG.wantsLayer = true
        badgeBG.layer?.cornerRadius = 9
        badgeBG.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeBG.layer?.borderColor = NSColor.white.cgColor
        badgeBG.layer?.borderWidth = 1.5
        badgeBG.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.isBezeled = false
        badgeLabel.drawsBackground = false
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(catHolder)
        catHolder.addSubview(catImageView)
        addSubview(badgeBG)
        badgeBG.addSubview(badgeLabel)

        let hw = catHolder.widthAnchor.constraint(equalToConstant: 64)
        let hh = catHolder.heightAnchor.constraint(equalToConstant: 64)
        let bw = badgeBG.widthAnchor.constraint(greaterThanOrEqualToConstant: 18)
        let bh = badgeBG.heightAnchor.constraint(equalToConstant: 18)
        holderWConstraint = hw
        holderHConstraint = hh
        badgeWConstraint  = bw
        badgeHConstraint  = bh

        NSLayoutConstraint.activate([
            catHolder.centerXAnchor.constraint(equalTo: centerXAnchor),
            catHolder.centerYAnchor.constraint(equalTo: centerYAnchor),
            hw, hh,

            catImageView.leadingAnchor.constraint(equalTo: catHolder.leadingAnchor),
            catImageView.trailingAnchor.constraint(equalTo: catHolder.trailingAnchor),
            catImageView.topAnchor.constraint(equalTo: catHolder.topAnchor),
            catImageView.bottomAnchor.constraint(equalTo: catHolder.bottomAnchor),

            badgeBG.topAnchor.constraint(equalTo: catHolder.topAnchor, constant: -4),
            badgeBG.trailingAnchor.constraint(equalTo: catHolder.trailingAnchor, constant: 4),
            bh, bw,

            badgeLabel.centerXAnchor.constraint(equalTo: badgeBG.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeBG.centerYAnchor),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeBG.leadingAnchor, constant: 5),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeBG.trailingAnchor, constant: -5),
        ])

        // tracking for cursor
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        badgeLabel.stringValue = badgeCount > 99 ? "99+" : "\(badgeCount)"
        badgeBG.isHidden = badgeCount <= 0
    }

    private var dragStart: NSPoint = .zero
    private var isDragging = false

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let dx = event.locationInWindow.x - dragStart.x
        let dy = event.locationInWindow.y - dragStart.y
        if !isDragging && (dx*dx + dy*dy > 9) {
            isDragging = true
            window?.performDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging { onClick?() }
    }

    // MARK: 动画

    /// 播放 24 帧精灵（12 fps，循环）
    private func startSpriteAnimation() {
        spriteTimer?.invalidate()
        guard spriteFrames.count > 1 else { return }
        let t = Timer(timeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.spriteIndex = (self.spriteIndex + 1) % self.spriteFrames.count
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.catImageView.image = self.spriteFrames[self.spriteIndex]
            CATransaction.commit()
        }
        // 加入 common mode，拖动 / 菜单弹出时也继续动
        RunLoop.main.add(t, forMode: .common)
        spriteTimer = t
    }

    /// 收到提醒：身体放大 20% 持续 5 秒；其间持续上下浮动；红色发光环呼应
    func jiggle() {
        // 设置 layer.anchorPoint 为中心（默认就是中心，确保 scale 不偏移）
        catHolder.wantsLayer = true
        catHolder.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // 1) 放大 20% 保持 5 秒（开头放大 0.2s，结尾缩回 0.3s，中间稳定 4.5s）
        let scaleUp = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleUp.values = [1.0, 1.20, 1.20, 1.0]
        scaleUp.keyTimes = [0, 0.04, 0.94, 1.0]   // 5s 内的相对时间
        scaleUp.duration = 5.0
        scaleUp.fillMode = .forwards
        scaleUp.isRemovedOnCompletion = true
        catHolder.layer?.add(scaleUp, forKey: "alertScale")

        // 2) 上下浮动 5 秒，每秒 1 个完整 cycle (上 → 下 → 上)，共 5 cycle
        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        var bobValues: [CGFloat] = []
        var bobTimes:  [NSNumber] = []
        let cycles = 10                       // 5 秒 × 2 半 cycle/秒 = 10
        for i in 0...cycles {
            let t = Double(i) / Double(cycles)
            // 偶数索引 0，奇数索引 ±10
            let v: CGFloat = (i % 2 == 0) ? 0 : 10
            bobValues.append(v)
            bobTimes.append(NSNumber(value: t))
        }
        bob.values = bobValues
        bob.keyTimes = bobTimes
        bob.duration = 5.0
        bob.fillMode = .forwards
        bob.isRemovedOnCompletion = true
        catHolder.layer?.add(bob, forKey: "alertBob")

        // 3) 红色发光环呼应（贯穿 5s）
        let flash = CABasicAnimation(keyPath: "shadowColor")
        flash.fromValue = NSColor.systemRed.cgColor
        flash.toValue = NSColor.black.cgColor
        flash.duration = 0.5
        flash.autoreverses = true
        flash.repeatCount = 5
        catHolder.layer?.add(flash, forKey: "alertFlash")

        let flashR = CABasicAnimation(keyPath: "shadowRadius")
        flashR.fromValue = 14
        flashR.toValue = 6
        flashR.duration = 0.5
        flashR.autoreverses = true
        flashR.repeatCount = 5
        catHolder.layer?.add(flashR, forKey: "alertFlashR")
    }

    // MARK: - 打字响应

    @objc private func onTypingKey() {
        // 1. 每次按键都做一个轻微弹跳
        nudgeOnKey()

        // 2. 如果进入"快速打字"状态，切到数字模式
        if KeyTypingCounter.shared.isTyping {
            enterTypingMode()
            updateTypingNumber()
        }

        // 3. 重置 1.5s 复位计时器
        typingResetTimer?.invalidate()
        typingResetTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            self?.exitTypingMode()
        }
    }

    @objc private func onDayChanged() {
        // 0 点后 todayCount 自动归 0；如果当时刚好在数字模式，刷一下
        if isInTypingMode { updateTypingNumber() }
    }

    /// 每次按键的抖动 — 方向 / 强度 都按 FloatingWidgetSettings.shakeStyle 走
    private func nudgeOnKey() {
        let style = FloatingWidgetSettings.shared.shakeStyle
        guard style != .off, !style.keyPath.isEmpty else { return }
        let bump = CABasicAnimation(keyPath: style.keyPath)
        bump.fromValue = 0
        bump.toValue = style.amount
        bump.duration = style.duration / 2.0
        bump.autoreverses = true
        catHolder.layer?.add(bump, forKey: "keyNudge")
    }

    /// 计算"原始尺寸"：基于 settings 算的固定值，不随 panel 当前 frame 变化
    /// 这样无论 enter / exit 动画进行到哪一步，目标 frame 永远精确，不会累积放大
    private func computeOriginalSizes() -> (panel: CGFloat, holder: CGFloat) {
        let style = FloatingWidgetSettings.shared.style
        let panelSize = FloatingWidgetSettings.shared.size.panelSize
        let holderSize: CGFloat = (style == .penguin)
            ? max(20, panelSize * 0.6)
            : max(20, panelSize - 8)
        return (panelSize, holderSize)
    }

    private func enterTypingMode() {
        guard !isInTypingMode, let panel = window else { return }
        isInTypingMode = true
        spriteTimer?.invalidate()

        // 清掉残留 transform
        catHolder.layer?.removeAllAnimations()
        catHolder.layer?.transform = CATransform3DIdentity
        catImageView.layer?.removeAllAnimations()
        catImageView.layer?.transform = CATransform3DIdentity

        let original = computeOriginalSizes()
        let scale: CGFloat = 1.5
        // ★ 目标 = 原始尺寸 × 1.5（不读 panel.frame 当前值，避免累积）
        let newPanelSize = original.panel * scale
        // 中心固定：以当前 panel center 为锚算新 origin
        let curCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let newPanelFrame = NSRect(
            x: curCenter.x - newPanelSize / 2,
            y: curCenter.y - newPanelSize / 2,
            width: newPanelSize, height: newPanelSize)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(newPanelFrame, display: true)
            holderWConstraint?.animator().constant = original.holder * scale
            holderHConstraint?.animator().constant = original.holder * scale
        }
        AppLog.log("FloatingWidget: enterTypingMode → \(original.panel)→\(newPanelSize)")
    }

    private func exitTypingMode() {
        guard isInTypingMode, let panel = window else { return }
        isInTypingMode = false

        let original = computeOriginalSizes()
        // ★ 目标 = 原始尺寸（不是 saved frame）
        let curCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let newPanelFrame = NSRect(
            x: curCenter.x - original.panel / 2,
            y: curCenter.y - original.panel / 2,
            width: original.panel, height: original.panel)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(newPanelFrame, display: true)
            holderWConstraint?.animator().constant = original.holder
            holderHConstraint?.animator().constant = original.holder
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            let safeIdx = self.spriteFrames.indices.contains(self.spriteIndex) ? self.spriteIndex : 0
            self.catImageView.image = self.spriteFrames.indices.contains(safeIdx)
                ? self.spriteFrames[safeIdx]
                : self.spriteFrames.first
            if self.spriteFrames.count > 1 { self.startSpriteAnimation() }
            AppLog.log("FloatingWidget: exitTypingMode → \(original.panel)")
        })
    }

    /// 用今日按键数刷新 catImageView 的图（不再加 layer 弹跳动画——
    ///  之前每次都改 anchorPoint 但没调 layer.position，导致 layer 累积位置漂移）
    private func updateTypingNumber() {
        let count = KeyTypingCounter.shared.todayCount
        let size = NSSize(width: holderWConstraint?.constant ?? 64,
                          height: holderHConstraint?.constant ?? 64)
        catImageView.image = renderTypingNumberImage(count: count, size: size)
        // 弹跳交给 nudgeOnKey()（已经做了 ±2px y 小弹）就够了，避免重复动画堆叠
    }

    /// 把"今日 N"画成图，**N 越大字号越小**保证不溢出
    /// 数字图：**canvas 永远 = holder 大小**，避免每次按键 image aspect 变化引起视觉位置漂移。
    /// 字号优先用 0.55×holder.h，**装不下时自动缩字号**直到能塞进 holder
    private func renderTypingNumberImage(count: Int, size: NSSize) -> NSImage {
        let str = "\(count)" as NSString
        var fontSize = size.height * 0.55
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -4,
        ]
        var textSize = str.size(withAttributes: attrs)
        // 装不下就按 0.9 系数缩字号，最低 8pt
        let maxW = size.width - 8
        while textSize.width > maxW, fontSize > 8 {
            fontSize *= 0.9
            attrs[.font] = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
            textSize = str.size(withAttributes: attrs)
        }
        let p = NSPoint(x: (size.width - textSize.width) / 2,
                         y: (size.height - textSize.height) / 2)
        // canvas size 永远等于 holder size → 居中位置稳定 → 不再"往下飘"
        return Self.makePixelCanvas(size: size) { _ in
            str.draw(at: p, withAttributes: attrs)
        }
    }

    /// 按当前样式选帧
    static func framesForStyle(_ style: FloatingWidgetSettings.CatStyle, size: NSSize) -> [NSImage] {
        switch style {
        case .cat:
            return loadOrSynthesizeFrames(targetSize: size)
        case .orangeCat:
            return loadOrangeCatFrames(targetSize: size)
        case .penguin:
            return loadPenguinFrames(targetSize: size)
        case .custom:
            return loadCustomFrames(targetSize: size)
        }
    }

    /// 自定义图片加载：custom-01..24.png（24 帧）→ custom.png（单张轻摇）→ 占位灰方块
    static func loadCustomFrames(targetSize: NSSize) -> [NSImage] {
        let base = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        let baseURL = URL(fileURLWithPath: base)

        var explicit: [NSImage] = []
        for i in 1...24 {
            let candidates = [
                String(format: "custom-%02d.png", i),
                "custom-\(i).png",
                String(format: "custom_%02d.png", i),
            ]
            if let hit = candidates.lazy.compactMap({ name -> NSImage? in
                let u = baseURL.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: u.path)
                    ? NSImage(contentsOf: u) : nil
            }).first {
                explicit.append(resize(hit, to: targetSize))
            }
        }
        if explicit.count == 24 { return explicit }

        let singleURL = baseURL.appendingPathComponent("custom.png")
        if FileManager.default.fileExists(atPath: singleURL.path),
           let src = NSImage(contentsOf: singleURL) {
            // ★ 彻底放弃自己 trim / resize / synthesize —— 多版反复出 bug。
            //   直接把 NSImage 原样返出去，NSImageView 自带 .scaleProportionallyUpOrDown
            //   + .alignCenter 会正确 aspect-fit 居中渲染。透明 padding 不会让猫缩成一角，
            //   因为 aspect-fit 会把整张 PNG 等比放进 catImageView frame。
            AppLog.log("loadCustomFrames: 用原图 \(Int(src.size.width))x\(Int(src.size.height))，不预处理")
            return [src]
        }

        // 没图：返回一张占位（提示用户选图）
        return [placeholderImage(size: targetSize)]
    }

    private static func placeholderImage(size: NSSize) -> NSImage {
        return makePixelCanvas(size: size) { ctx in
            let inset = size.width * 0.1
            let rect = NSRect(x: inset, y: inset,
                               width: size.width - inset*2, height: size.height - inset*2)
            ctx.setFillColor(NSColor.gray.withAlphaComponent(0.2).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor.gray.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.stroke(rect)
            let text = "?" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size.width * 0.4, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (size.width - textSize.width) / 2,
                                   y: (size.height - textSize.height) / 2),
                      withAttributes: attrs)
        }
    }

    /// 橘猫加载顺序：
    /// 1) cat-orange-01..24.png（24 帧）
    /// 2) cat-orange.png 单张 → 24 帧合成（呼吸/扇翅膀/倾斜）
    /// 3) OrangeCatRenderer 程序化绘制 24 帧（兜底）
    static func loadOrangeCatFrames(targetSize: NSSize) -> [NSImage] {
        let base = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        let baseURL = URL(fileURLWithPath: base)

        // 1) 24 张显式帧
        var explicit: [NSImage] = []
        for i in 1...24 {
            let candidates = [
                String(format: "cat-orange-%02d.png", i),
                "cat-orange-\(i).png",
                String(format: "cat_orange_%02d.png", i),
            ]
            if let hit = candidates.lazy.compactMap({ name -> NSImage? in
                let u = baseURL.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: u.path)
                    ? NSImage(contentsOf: u) : nil
            }).first {
                explicit.append(resize(hit, to: targetSize))
            }
        }
        if explicit.count == 24 { return explicit }

        // 2) 用户自定义 cat-orange.png（覆盖优先级最高）
        //    ★ 直接返回单帧原图，让 NSImageView 自带 aspect-fit 等比缩放显示
        let userURL = baseURL.appendingPathComponent("cat-orange.png")
        if FileManager.default.fileExists(atPath: userURL.path),
           let src = NSImage(contentsOf: userURL) {
            return [downscaleIfHuge(src, maxDim: 512)]
        }

        // 3) Bundle 自带的 cat-orange.png（装包给陌生 Mac 也能直接看到橘猫真图）
        if let bundleURL = Bundle.main.url(forResource: "cat-orange", withExtension: "png"),
           let src = NSImage(contentsOf: bundleURL) {
            return [downscaleIfHuge(src, maxDim: 512)]
        }

        // 4) 程序绘制兜底
        return OrangeCatRenderer.makeFrames(size: targetSize)
    }

    /// 静态橘猫的"摇尾巴"轻动画：绕底部中心 ±1° 慢速摆动（2 秒一个 cycle）
    /// 不做水平缩放 / 不上下浮 / 不头部 tilt —— 只是坐着轻微晃身体
    private static func synthesize24TailWag(from src: NSImage, targetSize: NSSize) -> [NSImage] {
        var out: [NSImage] = []
        let w = targetSize.width, h = targetSize.height
        let safeFactor: CGFloat = 0.95   // 留少许边给 ±1° 旋转，避免被裁
        let safeW = w * safeFactor, safeH = h * safeFactor
        let aspect = src.size.height / max(src.size.width, 1)
        let fitW: CGFloat, fitH: CGFloat
        if aspect > 1 {
            fitH = safeH
            fitW = safeH / aspect
        } else {
            fitW = safeW
            fitH = safeW * aspect
        }
        let drawSize = NSSize(width: fitW, height: fitH)
        let srcRect = NSRect(origin: .zero, size: src.size)

        for i in 0..<24 {
            let t = Double(i) / 24.0
            // 一秒一 cycle、±1° 慢速摆 —— 模拟坐着摇尾巴时身体的微跟动
            let tilt = CGFloat(sin(t * .pi * 2) * 0.018)   // 0.018 rad ≈ 1°
            _ = h  // silence unused

            let img = makePixelCanvas(size: targetSize) { ctx in
                ctx.translateBy(x: w / 2, y: 0)
                ctx.rotate(by: tilt)
                let rect = NSRect(x: -drawSize.width / 2, y: 0,
                                   width: drawSize.width, height: drawSize.height)
                src.draw(in: rect, from: srcRect, operation: .sourceOver, fraction: 1.0)
            }
            out.append(img)
        }
        return out
    }

    /// 企鹅帧加载顺序：
    /// 1) penguin-01.png ~ penguin-24.png（24 张则全用，做动画）
    /// 2) ~/Library/Application Support/MyTodoApp/penguin.png（单张，静态显示）★ 用户最常用
    /// 3) PenguinRenderer 程序化绘制 24 帧
    static func loadPenguinFrames(targetSize: NSSize) -> [NSImage] {
        let base = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        let baseURL = URL(fileURLWithPath: base)

        // 1) 24 张显式帧
        var explicit: [NSImage] = []
        for i in 1...24 {
            let candidates = [
                String(format: "penguin-%02d.png", i),
                "penguin-\(i).png",
                String(format: "penguin_%02d.png", i),
            ]
            if let hit = candidates.lazy.compactMap({ name -> NSImage? in
                let u = baseURL.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: u.path)
                    ? NSImage(contentsOf: u) : nil
            }).first {
                explicit.append(resize(hit, to: targetSize))
            }
        }
        if explicit.count == 24 { return explicit }

        // 2) 用户自定义 penguin.png（覆盖优先级最高）—— 直接返回原图等 imageView 自动缩放
        let userURL = baseURL.appendingPathComponent("penguin.png")
        if FileManager.default.fileExists(atPath: userURL.path),
           let src = NSImage(contentsOf: userURL) {
            return [src]
        }

        // 3) Bundle 自带的 penguin.png（装包给陌生 Mac 也能直接看到这只 QQ 企鹅）
        if let bundleURL = Bundle.main.url(forResource: "penguin", withExtension: "png"),
           let src = NSImage(contentsOf: bundleURL) {
            return [src]
        }

        // 4) 程序绘制兜底
        return PenguinRenderer.makeFrames(size: targetSize)
    }

    // MARK: - 精灵帧加载 / 合成

    /// 优先 cat-01.png ~ cat-24.png；否则由 cat.png 派生；再否则用 CatRenderer 程序化生成
    static func loadOrSynthesizeFrames(targetSize: NSSize) -> [NSImage] {
        let base = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        let baseURL = URL(fileURLWithPath: base)

        // 1) 24 张显式帧（支持 cat-01.png / cat-1.png / cat_01.png 三种命名）
        var explicit: [NSImage] = []
        for i in 1...24 {
            let candidates = [
                String(format: "cat-%02d.png", i),
                "cat-\(i).png",
                String(format: "cat_%02d.png", i),
            ]
            if let hit = candidates.lazy.compactMap({ name -> NSImage? in
                let u = baseURL.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: u.path)
                    ? NSImage(contentsOf: u) : nil
            }).first {
                explicit.append(resize(hit, to: targetSize))
            }
        }
        if explicit.count == 24 { return explicit }

        // 2) 用户数据目录里的 cat.png（用户自己放进去的）派生 24 帧
        let singleURL = baseURL.appendingPathComponent("cat.png")
        if FileManager.default.fileExists(atPath: singleURL.path),
           let src = NSImage(contentsOf: singleURL) {
            return synthesize24(from: src, targetSize: targetSize)
        }

        // 3) bundle 内置的 Assets/cat.png（默认形象）
        if let bundleURL = Bundle.main.url(forResource: "cat", withExtension: "png"),
           let src = NSImage(contentsOf: bundleURL) {
            return synthesize24(from: src, targetSize: targetSize)
        }

        // 4) 程序化绘制圆胖白猫 24 帧 walk cycle（最后兜底）
        return CatRenderer.makeFrames(size: targetSize)
    }

    /// 从单张源图生成 24 帧 walk-cycle
    /// ★ 修：先 aspect-fit 到 safe area，避免大图被裁成"左上四分之一"；保留透明底
    private static func synthesize24(from rawSrc: NSImage, targetSize: NSSize) -> [NSImage] {
        // ★ 先把透明 padding 裁干净 —— 否则 PNG 周围一圈 alpha=0 会让猫缩在画布一角
        // 再压超大尺寸（>512pt）防 AppKit draw 路径偶发问题
        let trimmed = trimTransparentBorder(rawSrc)
        let src = downscaleIfHuge(trimmed, maxDim: 512)

        var out: [NSImage] = []
        let w = targetSize.width, h = targetSize.height
        // ★ safe 区 78%：给 bob/scale/rotate 三项叠加留够余量，不再每帧把猫顶出画布
        let safeFactor: CGFloat = 0.78
        let safeW = w * safeFactor, safeH = h * safeFactor
        // aspect-fit 到 safe 区
        let aspect = src.size.height / max(src.size.width, 1)
        let fitW: CGFloat, fitH: CGFloat
        if aspect > 1 {
            fitH = safeH
            fitW = safeH / aspect
        } else {
            fitW = safeW
            fitH = safeW * aspect
        }
        let drawSize = NSSize(width: fitW, height: fitH)
        let srcRect = NSRect(origin: .zero, size: src.size)
        // bob 按 canvas 高度的 5% 算（不再固定 8px）
        let bobAmp = h * 0.05

        for i in 0..<24 {
            let t = Double(i) / 24.0
            // 振幅全部砍小，且按比例：
            //   bob ±5% canvas、squash/stretch ±3%、整体倾斜 ±2.5°（含尾巴小波）
            let bob     = CGFloat(sin(t * .pi * 2)) * bobAmp
            let squash  = CGFloat(1.0 + sin(t * .pi * 4) * 0.03)
            let stretch = CGFloat(1.0 - sin(t * .pi * 4) * 0.03)
            let lean     = CGFloat(sin(t * .pi * 2) * 0.035)
            let tailSway = CGFloat(sin(t * .pi * 6) * 0.010)

            let img = makePixelCanvas(size: targetSize) { ctx in
                // 关键：先把原点平移到画布中心，再旋转/缩放，最后用「以中心为原点」的矩形画图
                ctx.translateBy(x: w / 2, y: h / 2 + bob)
                ctx.rotate(by: lean + tailSway)
                ctx.scaleBy(x: stretch, y: squash)
                let rect = NSRect(x: -drawSize.width / 2, y: -drawSize.height / 2,
                                  width: drawSize.width, height: drawSize.height)
                src.draw(in: rect, from: srcRect, operation: .sourceOver, fraction: 1.0)
            }
            out.append(img)
        }
        return out
    }

    /// 把单张企鹅 PNG 合成 24 帧动画：
    ///   - 图画在 canvas 的 85%，留 15% 边给 bob/rotate 用 → **跳动时不会被剃头**
    ///   - 水平缩放波 ±6%（扇翅膀感觉）
    ///   - 呼吸：垂直缩放 ±2%
    ///   - 头部小幅左右倾斜 ±2.5°
    ///   - 上下浮 = canvas 高度的 ±5%（按比例，而不是固定 ±2px）
    private static func synthesize24Penguin(from src: NSImage, targetSize: NSSize) -> [NSImage] {
        var out: [NSImage] = []
        let w = targetSize.width, h = targetSize.height
        // ★ 留出 padding：图画 85%，剩 15% 给 bob/scale 动画
        let safeFactor: CGFloat = 0.85
        let safeW = w * safeFactor, safeH = h * safeFactor

        // aspect-fit 到 safeW × safeH 内
        let aspect = src.size.height / max(src.size.width, 1)
        let fitW: CGFloat, fitH: CGFloat
        if aspect > 1 {
            fitH = safeH
            fitW = safeH / aspect
        } else {
            fitW = safeW
            fitH = safeW * aspect
        }
        let drawSize = NSSize(width: fitW, height: fitH)
        let srcRect = NSRect(origin: .zero, size: src.size)

        // bob 幅度按 canvas 高度的 5% 算 —— 这样大图小图都不会顶到边
        let bobAmp = h * 0.05

        for i in 0..<24 {
            let t = Double(i) / 24.0

            let wingX = CGFloat(1.0 + sin(t * .pi * 4) * 0.06)        // ±6%
            let breatheY = CGFloat(1.0 + sin(t * .pi * 2) * 0.02)     // ±2%
            let tilt = CGFloat(sin(t * .pi * 2) * 0.044)              // ±2.5°
            let bob  = CGFloat(sin(t * .pi * 2)) * bobAmp

            let img = makePixelCanvas(size: targetSize) { ctx in
                ctx.translateBy(x: w / 2, y: h / 2 + bob)
                ctx.rotate(by: tilt)
                ctx.scaleBy(x: wingX, y: breatheY)
                let rect = NSRect(x: -drawSize.width / 2, y: -drawSize.height / 2,
                                   width: drawSize.width, height: drawSize.height)
                src.draw(in: rect, from: srcRect, operation: .sourceOver, fraction: 1.0)
            }
            out.append(img)
        }
        return out
    }

    /// 像素级稳定画布：用 NSBitmapImageRep 显式控制 pixelsWide/Hi
    /// 关键点：`NSGraphicsContext(bitmapImageRep:)` 默认坐标系 **已经是 points**（按 rep.size），
    /// 所以 closure 直接按 points 画就行，**不要再 scaleBy** —— 之前那次 scaleBy 让画面被推到画布外。
    private static func makePixelCanvas(size: NSSize, draw: (CGContext) -> Void) -> NSImage {
        let scale: CGFloat = 2.0   // 2× DPI 给 retina 清晰
        let pxW = max(1, Int(size.width  * scale))
        let pxH = max(1, Int(size.height * scale))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pxW * 4, bitsPerPixel: 32) else {
            return NSImage(size: size)
        }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
            let img = NSImage(size: size); img.addRepresentation(rep); return img
        }
        NSGraphicsContext.current = gctx
        gctx.imageInterpolation = .high

        // ★ 显式清成透明（兜底：某些路径下 bitmap buffer 可能不是清零）
        gctx.cgContext.clear(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        draw(gctx.cgContext)

        let img = NSImage(size: size)
        img.addRepresentation(rep)
        return img
    }

    /// Robust 版裁透明边：按 NSBitmapImageRep.bitmapFormat 判断 alpha 索引（alphaFirst / 非）。
    /// 旧版假设 alpha 在最后 → 在 alphaFirst 格式下把蓝色通道当 alpha 用，包围框算错把猫切掉。
    /// 失败/全透明 → 返回 nil 让上游用原图。
    private static func trimTransparentBorderRobust(_ src: NSImage) -> NSImage? {
        // ★ 重新画一张已知 RGBA 8-bit 非 premult、alpha 在最后的标准 bitmap，
        //   规避源 NSBitmapImageRep 各种格式（alphaFirst/premult/16bit）造成的 alpha 索引混乱
        let pxW = max(1, Int(src.size.width))
        let pxH = max(1, Int(src.size.height))
        guard pxW > 0, pxH > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pxW, pixelsHigh: pxH,
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bitmapFormat: [],   // ← 默认：RGBA 顺序，非 premult，alpha 在最后
                bytesPerRow: pxW * 4, bitsPerPixel: 32),
              let data = rep.bitmapData
        else { return nil }

        // 把 src 重新画到这张已知格式的 bitmap 上
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = gctx
        gctx.cgContext.clear(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        src.draw(in: NSRect(x: 0, y: 0, width: pxW, height: pxH),
                 from: .zero, operation: .copy, fraction: 1.0)
        gctx.flushGraphics()

        // 现在 alpha 一定在 byte index 3
        let bpr = rep.bytesPerRow
        var minX = pxW, minY = pxH, maxX = -1, maxY = -1
        for y in 0..<pxH {
            for x in 0..<pxW {
                let p = y * bpr + x * 4
                if data[p + 3] > 16 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        // 全透明 / 没找到任何可见像素 → 返回 nil，上游用原图
        guard maxX >= minX, maxY >= minY else { return nil }
        let cropPxW = maxX - minX + 1
        let cropPxH = maxY - minY + 1
        // 已经紧凑（透明边 < 2%）→ 没必要折腾
        if cropPxW > Int(Double(pxW) * 0.96), cropPxH > Int(Double(pxH) * 0.96) { return src }

        // 切出对应像素区到新 bitmap
        guard let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: cropPxW, pixelsHigh: cropPxH,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: cropPxW * 4, bitsPerPixel: 32),
            let outData = outRep.bitmapData
        else { return nil }
        let outBpr = outRep.bytesPerRow
        for y in 0..<cropPxH {
            let srcRow = (minY + y) * bpr + minX * 4
            let dstRow = y * outBpr
            memcpy(outData + dstRow, data + srcRow, cropPxW * 4)
        }
        let img = NSImage(size: NSSize(width: cropPxW, height: cropPxH))
        img.addRepresentation(outRep)
        AppLog.log("trimRobust: \(pxW)x\(pxH) → \(cropPxW)x\(cropPxH) (alpha bbox)")
        return img
    }

    /// 把图裁到「非透明像素的最小包围框」。
    /// 用户的 PNG 经常带超大透明 padding（导入器抠完底之后猫只占左上角一小块），
    /// 不裁就会出现「猫挤一角」的视觉错觉。
    /// 阈值 alpha > 16（≈ 6%）才算"可见"。
    private static func trimTransparentBorder(_ src: NSImage) -> NSImage {
        guard let tiff = src.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return src }
        let pxW = rep.pixelsWide
        let pxH = rep.pixelsHigh
        guard pxW > 0, pxH > 0, let data = rep.bitmapData else { return src }
        let bpr = rep.bytesPerRow
        let spp = rep.samplesPerPixel
        // 没 alpha 通道 = 不透明图，直接返回
        guard rep.hasAlpha else { return src }

        var minX = pxW, minY = pxH, maxX = -1, maxY = -1
        for y in 0..<pxH {
            for x in 0..<pxW {
                let p = y * bpr + x * spp
                let a = data[p + (spp - 1)]   // 通常 alpha 在最后一个 sample
                if a > 16 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        // 全透明 → 原样返回
        guard maxX >= minX, maxY >= minY else { return src }
        let cropPxW = maxX - minX + 1
        let cropPxH = maxY - minY + 1
        // 已经是紧凑布局（透明边 < 2% 各方向），不必折腾
        if cropPxW > Int(Double(pxW) * 0.96), cropPxH > Int(Double(pxH) * 0.96) { return src }

        // 把对应像素区切出来作为新 NSImage（点 size 用 src.size 比例换算）
        let scaleW = src.size.width / CGFloat(pxW)
        let scaleH = src.size.height / CGFloat(pxH)
        let newSizePt = NSSize(width: CGFloat(cropPxW) * scaleW,
                               height: CGFloat(cropPxH) * scaleH)

        return makePixelCanvas(size: newSizePt) { _ in
            // src.size 坐标空间下 from rect（注意 NSImage 默认 y 从下往上）
            let fromX = CGFloat(minX) * scaleW
            let fromYTop = CGFloat(minY) * scaleH
            let fromYBottom = src.size.height - fromYTop - newSizePt.height
            src.draw(in: NSRect(origin: .zero, size: newSizePt),
                     from: NSRect(x: fromX, y: fromYBottom,
                                  width: newSizePt.width, height: newSizePt.height),
                     operation: .sourceOver, fraction: 1.0)
        }
    }

    /// 把可能超大的源图先 aspect-fit 缩到 maxDim × maxDim 内
    /// 避免 NSImage.draw(in:from:) 在巨型源 + 小目标时偶发裁剪/丢色
    private static func downscaleIfHuge(_ src: NSImage, maxDim: CGFloat = 512) -> NSImage {
        let s = src.size
        guard s.width > maxDim || s.height > maxDim else { return src }
        let scale = min(maxDim / s.width, maxDim / s.height)
        let newSize = NSSize(width: floor(s.width * scale), height: floor(s.height * scale))
        // 用 aspect-fit 居中 + 透明底
        return makePixelCanvas(size: newSize) { _ in
            src.draw(in: NSRect(origin: .zero, size: newSize),
                     from: NSRect(origin: .zero, size: s),
                     operation: .sourceOver, fraction: 1.0)
        }
    }

    /// Aspect-fit 居中缩放
    private static func resize(_ src: NSImage, to size: NSSize) -> NSImage {
        let srcW = src.size.width
        let srcH = src.size.height
        guard srcW > 0, srcH > 0 else { return NSImage(size: size) }

        let scale = min(size.width / srcW, size.height / srcH)
        let fitW = srcW * scale
        let fitH = srcH * scale
        let dstRect = NSRect(x: (size.width - fitW) / 2,
                              y: (size.height - fitH) / 2,
                              width: fitW, height: fitH)
        return makePixelCanvas(size: size) { _ in
            // NSGraphicsContext 已经设好；直接用 NSImage.draw 调 AppKit
            src.draw(in: dstRect, from: NSRect(origin: .zero, size: src.size),
                     operation: .sourceOver, fraction: 1.0)
        }
    }

    private static func rasterizeEmoji(_ s: String, size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        let fontSize = min(size.width, size.height) * 0.85
        let font = NSFont(name: "Apple Color Emoji", size: fontSize)
            ?? NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: ps,
        ]
        let astr = NSAttributedString(string: s, attributes: attrs)
        let strSize = astr.size()
        astr.draw(at: NSPoint(x: (size.width - strSize.width)/2,
                              y: (size.height - strSize.height)/2))
        img.unlockFocus()
        return img
    }
}

/// 悬浮窗行：☐ 颜色条 标题 @人（点击文字区打开详情）
final class FloatingRow: NSTableCellView {
    private let task: TodoItem
    private let onToggle: (UUID) -> Void

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if check.frame.contains(p) { super.mouseDown(with: event); return }
        TaskDetailController.present(taskId: task.id)
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
    private let check = CircularCheckBox()
    private let flag = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let sep = NSBox()

    init(task: TodoItem, onToggle: @escaping (UUID) -> Void) {
        self.task = task
        self.onToggle = onToggle
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        check.checked = false
        check.tintHex = task.priority == .none ? "#9AA0A6" : task.priority.colorHex
        check.onCommit = { [weak self] in
            guard let self = self else { return }
            self.onToggle(self.task.id)
        }
        check.translatesAutoresizingMaskIntoConstraints = false

        flag.wantsLayer = true
        flag.layer?.cornerRadius = 1.5
        flag.layer?.backgroundColor = NSColor(hex: task.priority.colorHex).cgColor
        flag.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = task.text.isEmpty ? "(仅图片)" : task.text
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .labelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        var metaParts: [String] = ["@\(task.person.isEmpty ? "未指定" : task.person)"]
        if let r = task.remindAt {
            metaParts.append("🕒 " + TaskRowView.smartDate(r))
        } else {
            metaParts.append(TaskRowView.smartDate(task.createdAt))
        }
        metaParts.append(task.priority.label)
        metaLabel.stringValue = metaParts.joined(separator: " · ")
        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = .tertiaryLabelColor
        metaLabel.maximumNumberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false

        addSubview(check)
        addSubview(flag)
        addSubview(titleLabel)
        addSubview(metaLabel)
        addSubview(sep)

        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 20),
            check.heightAnchor.constraint(equalToConstant: 20),

            flag.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 6),
            flag.centerYAnchor.constraint(equalTo: centerYAnchor),
            flag.widthAnchor.constraint(equalToConstant: 3),
            flag.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: flag.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            sep.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),
        ])
    }
}
