import AppKit

/// 顶部菜单栏（屏幕右上角）常驻图标，方便随时唤起主窗口
final class MenuBarController: NSObject, NSMenuDelegate {

    // 菜单弹出时需要实时刷新的项
    private weak var typingCountItem: NSMenuItem?

    static let shared = MenuBarController()

    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var popover: LazyCatMenuPopover!   // Style B 自定义弹窗，替代系统 NSMenu
    weak var appDelegate: AppDelegate?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let btn = item.button {
            // 无条件给一张图片；btn.title 在状态栏上经常渲染不出 emoji
            btn.image = menuBarIcon()
            btn.imagePosition = .imageOnly
            btn.toolTip = "LazyCat"
            // 关键：走显式 click handler，确保点击一定有反应（某些系统下
            // statusItem.menu 自动弹出会被 NSResponder chain 吃掉）
            btn.target = self
            btn.action = #selector(statusClicked(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // 旧版系统 NSMenu 留作兜底（虽然现在 statusClicked 走 popover，但保留这份能避免
        // 任何引用 statusMenu 的地方崩溃）
        let menu = NSMenu()
        menu.addItem(makeItem("打开主窗口", #selector(openMain)))
        menu.addItem(makeItem("新建事件 (聚焦输入框)", #selector(newEvent)))
        menu.addItem(.separator())
        menu.addItem(makeItem("桌面悬浮窗", #selector(toggleFloating)))

        // 悬浮形态（猫 / 橘猫 / 企鹅 / 自定义）
        do {
            let head = NSMenuItem(title: "  悬浮形态", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let cur = FloatingWidgetSettings.shared.style
            for s in FloatingWidgetSettings.CatStyle.allCases {
                let mi = NSMenuItem(title: s.title, action: #selector(pickFloatStyle(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = s.rawValue
                if s == cur { mi.state = .on }
                sub.addItem(mi)
            }
            sub.addItem(.separator())
            // 选择自定义图片入口（NSOpenPanel 选图 → 抠白底 → 自动切到 .custom）
            let pick = NSMenuItem(title: "选择自定义图片…",
                                   action: #selector(pickCustomImage),
                                   keyEquivalent: "")
            pick.target = self
            sub.addItem(pick)
            head.submenu = sub
            menu.addItem(head)
        }

        // 悬浮尺寸（10..100% 共 10 档）
        do {
            let head = NSMenuItem(title: "  悬浮尺寸", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let cur = FloatingWidgetSettings.shared.size
            // 倒序展示：100% 在最上面，往下越来越小
            for s in FloatingWidgetSettings.Size.presets.reversed() {
                let mi = NSMenuItem(title: s.title, action: #selector(pickFloatSize(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = s.percent
                if s == cur { mi.state = .on }
                sub.addItem(mi)
            }
            head.submenu = sub
            menu.addItem(head)
        }
        menu.addItem(makeItem("专注遮罩（全屏）  ⇧⌘D / ⌥⌘`", #selector(toggleFullscreenMask)))

        // 遮罩透明度子菜单 0..100
        do {
            let head = NSMenuItem(title: "  遮罩透明度", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let presets: [Int] = [100, 90, 82, 70, 60, 50, 40, 30, 20, 10, 5, 0]
            let cur = MaskSettings.shared.opacityPercent
            for pct in presets {
                let mi = NSMenuItem(title: "\(pct)%", action: #selector(pickMaskOpacity(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = pct
                if pct == cur { mi.state = .on }
                sub.addItem(mi)
            }
            head.submenu = sub
            menu.addItem(head)
        }

        // 遮罩字号子菜单
        do {
            let head = NSMenuItem(title: "  遮罩字号", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let cur = MaskSettings.shared.fontSize
            for f in MaskSettings.FontSize.allCases {
                let mi = NSMenuItem(title: f.title, action: #selector(pickMaskFontSize(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = f.rawValue
                if f == cur { mi.state = .on }
                sub.addItem(mi)
            }
            head.submenu = sub
            menu.addItem(head)
        }

        // 锁屏快捷键子菜单
        do {
            let head = NSMenuItem(title: "  锁屏快捷键", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let curId = LockHotKeySettings.shared.currentId
            for p in LockHotKeySettings.presets {
                let mi = NSMenuItem(title: p.title, action: #selector(pickLockHotKey(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = p.id
                if p.id == curId { mi.state = .on }
                sub.addItem(mi)
            }
            head.submenu = sub
            menu.addItem(head)
        }

        // 悬浮动画透明度（小红点不受影响）
        do {
            let head = NSMenuItem(title: "  悬浮透明度", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let curAlpha = FloatingWidgetSettings.shared.alpha
            for preset in FloatingWidgetSettings.alphaPresets {
                let mi = NSMenuItem(title: preset.label, action: #selector(pickFloatAlpha(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = Int((preset.value * 100).rounded())
                if abs(preset.value - curAlpha) < 0.01 { mi.state = .on }
                sub.addItem(mi)
            }
            head.submenu = sub
            menu.addItem(head)
        }

        // 打字抖动方向 + 强度
        do {
            let head = NSMenuItem(title: "  打字抖动", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let cur = FloatingWidgetSettings.shared.shakeStyle
            for s in FloatingWidgetSettings.ShakeStyle.allCases {
                let mi = NSMenuItem(title: s.title, action: #selector(pickShakeStyle(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = s.rawValue
                if s == cur { mi.state = .on }
                sub.addItem(mi)
            }
            head.submenu = sub
            menu.addItem(head)
        }

        menu.addItem(.separator())

        // ── 背景透明度子菜单 ──
        let opacityItem = NSMenuItem(title: "背景透明度", action: nil, keyEquivalent: "")
        let opacitySub = NSMenu()
        let presets: [(String, Int)] = [
            ("100%  不透明", 100), ("90%", 90), ("80%", 80), ("70%", 70),
            ("60%", 60), ("50%  半透明", 50), ("40%", 40), ("30%", 30),
            ("20%", 20), ("10%", 10), ("5%  几乎全透明", 5),
        ]
        let current = WindowOpacity.shared.percent
        for (label, pct) in presets {
            let mi = NSMenuItem(title: label, action: #selector(pickOpacity(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = pct
            if pct == current { mi.state = .on }
            opacitySub.addItem(mi)
        }
        opacityItem.submenu = opacitySub
        menu.addItem(opacityItem)

        menu.addItem(.separator())

        // 汇总提醒间隔
        do {
            let head = NSMenuItem(title: "未完成汇总提醒", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let presets: [(String, Int)] = [
                ("每 30 分钟",  30),
                ("每 1 小时（默认）",  60),
                ("每 2 小时", 120),
                ("每 4 小时", 240),
                ("关闭",        0),
            ]
            let cur = ReminderEngine.shared.intervalMinutes
            for (label, m) in presets {
                let mi = NSMenuItem(title: label, action: #selector(pickDigestInterval(_:)), keyEquivalent: "")
                mi.target = self
                mi.tag = m
                if m == cur { mi.state = .on }
                sub.addItem(mi)
            }
            sub.addItem(.separator())
            let now = NSMenuItem(title: "立刻汇总一次", action: #selector(fireDigestNow), keyEquivalent: "")
            now.target = self
            sub.addItem(now)
            head.submenu = sub
            menu.addItem(head)
        }

        menu.addItem(.separator())
        // 今日打字数（每次菜单弹出时由 menuWillOpen 刷新）
        let typingItem = NSMenuItem(title: "今日打字 0 次",
                                    action: nil, keyEquivalent: "")
        typingItem.isEnabled = false
        typingCountItem = typingItem
        menu.addItem(typingItem)
        // ★ 打字统计窗口（Top 5 按键 + 大字日数量统计）
        menu.addItem(makeItem("打字统计 / 排行 / 30 日图表…", #selector(showTypingStats)))
        // 重新申请输入监控权限（绕过 24h cooldown）
        menu.addItem(makeItem("申请打字监控权限…", #selector(requestTypingPermission)))
        // ★ 重置 TCC 记录 + 重弹官方对话框（修"权限给了但不生效"的死结）
        menu.addItem(makeItem("权限失效？重置并重新申请…", #selector(resetTypingPermission)))
        menu.addItem(.separator())

        menu.addItem(makeItem("关于 LazyCat（版本 / 构建信息）…", #selector(showAbout)))
        menu.addItem(makeItem("在 Finder 中显示数据", #selector(revealData)))
        menu.addItem(makeItem("打开自定义形象图片目录…  (放 cat.png / penguin.png)", #selector(openImageFolder)))
        menu.addItem(.separator())
        menu.addItem(makeItem("退出 LazyCat", #selector(quit)))
        menu.delegate = self
        statusMenu = menu

        // 状态栏图标旁实时显示今日打字数
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatusBarTitle),
                                               name: .typingKeyDown, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStatusBarTitle),
                                               name: .typingDayChanged, object: nil)
        refreshStatusBarTitle()

        // ★ Style B 自定义 popover —— 替代系统 NSMenu
        popover = LazyCatMenuPopover(menuController: self)
    }

    @objc private func refreshStatusBarTitle() {
        guard let btn = statusItem?.button else { return }
        let count = KeyTypingCounter.shared.todayCount
        if count > 0 {
            btn.title = " \(count)"
            btn.imagePosition = .imageLeft
            btn.font = .systemFont(ofSize: 11, weight: .medium)
        } else {
            btn.title = ""
            btn.imagePosition = .imageOnly
        }
    }

    // 菜单弹出前刷新动态项
    func menuWillOpen(_ menu: NSMenu) {
        typingCountItem?.title = "今日打字 \(KeyTypingCounter.shared.todayCount) 次"
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
        it.target = self
        return it
    }

    /// 点击菜单栏图标：左键 → Style B popover；右键 → 同样的 popover
    @objc private func statusClicked(_ sender: Any?) {
        guard let btn = statusItem.button else { return }
        popover?.toggle(at: btn)
    }

    // MARK: - Style B Popover · 声明性条目

    /// 构造 Style B 弹窗里的所有行 —— 跟 install() 里的 NSMenu 等价，但走自定义 UI
    func buildPopoverItems() -> [LazyCatPopoverItem] {
        let cur = KeyTypingCounter.shared.todayCount
        let isMaskOn = FullscreenMaskController.shared.isShown
        let isFloatOn = FloatingWidgetController.shared.isOpen

        var items: [LazyCatPopoverItem] = []

        // ── 主操作 ──
        items.append(LazyCatPopoverItem(
            icon: "📋", title: "打开主窗口",
            kind: .action(#selector(openMain))))
        items.append(LazyCatPopoverItem(
            icon: "＋", title: "新建事件（聚焦输入框）",
            kind: .action(#selector(newEvent))))

        items.append(LazyCatPopoverItem(kind: .separator))
        items.append(LazyCatPopoverItem(kind: .sectionLabel("桌面陪伴")))

        items.append(LazyCatPopoverItem(
            icon: "🐾", title: "桌面悬浮窗",
            trailing: isFloatOn ? "已开" : "关闭",
            kind: .action(#selector(toggleFloating)),
            highlighted: isFloatOn))
        items.append(LazyCatPopoverItem(
            icon: "🎭", title: "悬浮形态",
            kind: .submenu({ [weak self] in self?.buildFloatStyleMenu() ?? NSMenu() })))
        items.append(LazyCatPopoverItem(
            icon: "📐", title: "悬浮尺寸",
            kind: .submenu({ [weak self] in self?.buildFloatSizeMenu() ?? NSMenu() })))
        items.append(LazyCatPopoverItem(
            icon: "💧", title: "悬浮透明度",
            kind: .submenu({ [weak self] in self?.buildFloatAlphaMenu() ?? NSMenu() })))
        items.append(LazyCatPopoverItem(
            icon: "🌀", title: "打字抖动",
            kind: .submenu({ [weak self] in self?.buildShakeMenu() ?? NSMenu() })))

        items.append(LazyCatPopoverItem(kind: .separator))
        items.append(LazyCatPopoverItem(kind: .sectionLabel("专注模式")))

        let lockHK = LockHotKeySettings.presets.first(where: { $0.id == LockHotKeySettings.shared.currentId })?.title ?? "⌥1"
        items.append(LazyCatPopoverItem(
            icon: "🔒", title: "专注遮罩（全屏）",
            trailing: lockHK,
            kind: .action(#selector(toggleFullscreenMask)),
            highlighted: isMaskOn))
        items.append(LazyCatPopoverItem(
            icon: "🌫", title: "遮罩透明度",
            trailing: "\(MaskSettings.shared.opacityPercent)%",
            kind: .submenu({ [weak self] in self?.buildMaskOpacityMenu() ?? NSMenu() })))
        items.append(LazyCatPopoverItem(
            icon: "🔠", title: "遮罩字号",
            trailing: MaskSettings.shared.fontSize.title,
            kind: .submenu({ [weak self] in self?.buildMaskFontMenu() ?? NSMenu() })))
        items.append(LazyCatPopoverItem(
            icon: "⌨️", title: "锁屏快捷键",
            trailing: lockHK,
            kind: .submenu({ [weak self] in self?.buildLockHotKeyMenu() ?? NSMenu() })))
        items.append(LazyCatPopoverItem(
            icon: "💤", title: "自动锁屏（闲置）",
            trailing: AutoLockSettings.shared.currentTitle,
            kind: .submenu({ [weak self] in self?.buildAutoLockMenu() ?? NSMenu() }),
            highlighted: AutoLockSettings.shared.isEnabled))
        items.append(LazyCatPopoverItem(
            icon: "🖼", title: "重置自定义悬浮图",
            kind: .action(#selector(resetCustomFloatImage))))
        items.append(LazyCatPopoverItem(
            icon: "🛡", title: "申请辅助功能权限（强化遮罩拦截）",
            kind: .action(#selector(requestAccessibilityPermission))))

        items.append(LazyCatPopoverItem(kind: .separator))
        items.append(LazyCatPopoverItem(kind: .sectionLabel("外观与提醒")))

        items.append(LazyCatPopoverItem(
            icon: "🎨", title: "背景透明度",
            trailing: "\(WindowOpacity.shared.percent)%",
            kind: .submenu({ [weak self] in self?.buildWindowOpacityMenu() ?? NSMenu() })))
        let digestMin = ReminderEngine.shared.intervalMinutes
        items.append(LazyCatPopoverItem(
            icon: "🔔", title: "未完成汇总提醒",
            trailing: digestMin == 0 ? "关闭" : "每 \(digestMin) 分",
            kind: .submenu({ [weak self] in self?.buildDigestMenu() ?? NSMenu() })))

        items.append(LazyCatPopoverItem(kind: .separator))
        items.append(LazyCatPopoverItem(kind: .sectionLabel("打字统计")))

        items.append(LazyCatPopoverItem(
            icon: "📊", title: "今日打字 \(cur) 次 · 30 日图表",
            kind: .action(#selector(showTypingStats))))
        items.append(LazyCatPopoverItem(
            icon: "🔑", title: "申请打字监控权限",
            kind: .action(#selector(requestTypingPermission))))
        items.append(LazyCatPopoverItem(
            icon: "🛠", title: "权限失效？重置并重新申请",
            kind: .action(#selector(resetTypingPermission))))

        items.append(LazyCatPopoverItem(kind: .separator))

        items.append(LazyCatPopoverItem(
            icon: "ℹ️", title: "关于 LazyCat（版本 / 构建）",
            kind: .action(#selector(showAbout))))
        items.append(LazyCatPopoverItem(
            icon: "📁", title: "在 Finder 中显示数据",
            kind: .action(#selector(revealData))))
        items.append(LazyCatPopoverItem(
            icon: "🖼", title: "自定义形象图片目录",
            kind: .action(#selector(openImageFolder))))

        items.append(LazyCatPopoverItem(kind: .separator))
        items.append(LazyCatPopoverItem(
            icon: "🚪", title: "退出 LazyCat",
            trailing: "⌘Q",
            kind: .action(#selector(quit)),
            dangerous: true))
        return items
    }

    // MARK: - 各 sub-menu 的工厂（每次刷新都重建，保证 ✓ 标记跟得上当前选择）

    private func buildFloatStyleMenu() -> NSMenu {
        let m = NSMenu()
        let cur = FloatingWidgetSettings.shared.style
        for s in FloatingWidgetSettings.CatStyle.allCases {
            let mi = NSMenuItem(title: s.title, action: #selector(pickFloatStyle(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = s.rawValue
            if s == cur { mi.state = .on }
            m.addItem(mi)
        }
        m.addItem(.separator())
        let pick = NSMenuItem(title: "选择自定义图片…", action: #selector(pickCustomImage), keyEquivalent: "")
        pick.target = self
        m.addItem(pick)
        return m
    }
    private func buildFloatSizeMenu() -> NSMenu {
        let m = NSMenu()
        let cur = FloatingWidgetSettings.shared.size
        for s in FloatingWidgetSettings.Size.presets.reversed() {
            let mi = NSMenuItem(title: s.title, action: #selector(pickFloatSize(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = s.percent
            if s == cur { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildFloatAlphaMenu() -> NSMenu {
        let m = NSMenu()
        let curAlpha = FloatingWidgetSettings.shared.alpha
        for preset in FloatingWidgetSettings.alphaPresets {
            let mi = NSMenuItem(title: preset.label, action: #selector(pickFloatAlpha(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = Int((preset.value * 100).rounded())
            if abs(preset.value - curAlpha) < 0.01 { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildShakeMenu() -> NSMenu {
        let m = NSMenu()
        let cur = FloatingWidgetSettings.shared.shakeStyle
        for s in FloatingWidgetSettings.ShakeStyle.allCases {
            let mi = NSMenuItem(title: s.title, action: #selector(pickShakeStyle(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = s.rawValue
            if s == cur { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildMaskOpacityMenu() -> NSMenu {
        let m = NSMenu()
        let presets: [Int] = [100, 90, 82, 70, 60, 50, 40, 30, 20, 10, 5, 0]
        let cur = MaskSettings.shared.opacityPercent
        for pct in presets {
            let mi = NSMenuItem(title: "\(pct)%", action: #selector(pickMaskOpacity(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = pct
            if pct == cur { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildMaskFontMenu() -> NSMenu {
        let m = NSMenu()
        let cur = MaskSettings.shared.fontSize
        for f in MaskSettings.FontSize.allCases {
            let mi = NSMenuItem(title: f.title, action: #selector(pickMaskFontSize(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = f.rawValue
            if f == cur { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildLockHotKeyMenu() -> NSMenu {
        let m = NSMenu()
        let curId = LockHotKeySettings.shared.currentId
        for p in LockHotKeySettings.presets {
            let mi = NSMenuItem(title: p.title, action: #selector(pickLockHotKey(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = p.id
            if p.id == curId { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildAutoLockMenu() -> NSMenu {
        let m = NSMenu()
        let s = AutoLockSettings.shared
        let off = NSMenuItem(title: "关闭", action: #selector(pickAutoLock(_:)), keyEquivalent: "")
        off.target = self; off.tag = 0
        if !s.isEnabled { off.state = .on }
        m.addItem(off)
        m.addItem(.separator())
        for p in AutoLockSettings.presets {
            let mi = NSMenuItem(title: p.title, action: #selector(pickAutoLock(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = p.seconds
            if s.isEnabled && s.idleSeconds == p.seconds { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildWindowOpacityMenu() -> NSMenu {
        let m = NSMenu()
        let presets: [(String, Int)] = [
            ("100%  不透明", 100), ("90%", 90), ("80%", 80), ("70%", 70),
            ("60%", 60), ("50%  半透明", 50), ("40%", 40), ("30%", 30),
            ("20%", 20), ("10%", 10), ("5%  几乎全透明", 5),
        ]
        let current = WindowOpacity.shared.percent
        for (label, pct) in presets {
            let mi = NSMenuItem(title: label, action: #selector(pickOpacity(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = pct
            if pct == current { mi.state = .on }
            m.addItem(mi)
        }
        return m
    }
    private func buildDigestMenu() -> NSMenu {
        let m = NSMenu()
        let presets: [(String, Int)] = [
            ("每 30 分钟", 30), ("每 1 小时（默认）", 60),
            ("每 2 小时", 120), ("每 4 小时", 240), ("关闭", 0),
        ]
        let cur = ReminderEngine.shared.intervalMinutes
        for (label, mn) in presets {
            let mi = NSMenuItem(title: label, action: #selector(pickDigestInterval(_:)), keyEquivalent: "")
            mi.target = self; mi.tag = mn
            if mn == cur { mi.state = .on }
            m.addItem(mi)
        }
        m.addItem(.separator())
        let now = NSMenuItem(title: "立刻汇总一次", action: #selector(fireDigestNow), keyEquivalent: "")
        now.target = self
        m.addItem(now)
        return m
    }

    @objc private func openMain() {
        appDelegate?.showMainWindow()
    }

    @objc private func newEvent() {
        appDelegate?.showMainWindow()
        NotificationCenter.default.post(name: .focusQuickAdd, object: nil)
    }

    @objc private func toggleFloating() {
        FloatingWidgetController.shared.toggle()
    }

    @objc private func toggleFullscreenMask() {
        FullscreenMaskController.shared.toggle()
    }

    @objc private func pickMaskOpacity(_ sender: NSMenuItem) {
        MaskSettings.shared.setOpacity(sender.tag)
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func pickFloatStyle(_ sender: NSMenuItem) {
        if let s = FloatingWidgetSettings.CatStyle(rawValue: sender.tag) {
            FloatingWidgetSettings.shared.setStyle(s)
        }
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func pickCustomImage() {
        CustomImageImporter.pickAndInstall()
    }

    @objc private func pickFloatSize(_ sender: NSMenuItem) {
        FloatingWidgetSettings.shared.setSize(FloatingWidgetSettings.Size.clamp(sender.tag))
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func pickDigestInterval(_ sender: NSMenuItem) {
        ReminderEngine.shared.setInterval(sender.tag)
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag && m.action == sender.action) ? .on : .off }
        }
    }

    @objc private func fireDigestNow() {
        ReminderEngine.shared.fireNow()
    }

    @objc private func pickLockHotKey(_ sender: NSMenuItem) {
        LockHotKeySettings.shared.setCurrent(id: sender.tag)
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func pickAutoLock(_ sender: NSMenuItem) {
        if sender.tag == 0 {
            AutoLockSettings.shared.isEnabled = false
        } else {
            AutoLockSettings.shared.idleSeconds = sender.tag
            AutoLockSettings.shared.isEnabled = true
        }
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func requestAccessibilityPermission() {
        // 用户主动点 → prompt: true 触发系统对话框 + 打开"系统设置 → 隐私与安全性 → 辅助功能"
        let opts: CFDictionary = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        let a = NSAlert()
        if trusted {
            a.messageText = "已授权"
            a.informativeText = "辅助功能权限已开启。锁屏遮罩可以系统级吞键盘 / 鼠标 / 触摸板。"
        } else {
            a.messageText = "请去系统设置完成授权"
            a.informativeText = "系统已弹出对话框；如未弹出，去 系统设置 → 隐私与安全性 → 辅助功能 把 LazyCat 勾上。\n\n注意：每次 app 重新构建 CDHash 会变 → 旧授权失效 → 需要把列表里旧的 LazyCat 删掉再重新勾。"
        }
        a.runModal()
    }

    @objc private func resetCustomFloatImage() {
        // 删 ~/Library/Application Support/MyTodoApp/custom.png；
        // 形态切回默认 .regular 让 bundle 自带的橘猫立刻接管。用户嫌挤一角时一键自救。
        let base = (Store.shared.dataFilePath as NSString).deletingLastPathComponent
        let url = URL(fileURLWithPath: base).appendingPathComponent("custom.png")
        try? FileManager.default.removeItem(at: url)
        FloatingWidgetSettings.shared.setStyle(.cat)
        let a = NSAlert()
        a.messageText = "已重置"
        a.informativeText = "自定义图删除完成，已切回默认猫。"
        a.runModal()
    }

    @objc private func pickFloatAlpha(_ sender: NSMenuItem) {
        let alpha = CGFloat(sender.tag) / 100.0
        FloatingWidgetSettings.shared.setAlpha(alpha)
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func pickMaskFontSize(_ sender: NSMenuItem) {
        if let f = MaskSettings.FontSize(rawValue: sender.tag) {
            MaskSettings.shared.setFontSize(f)
        }
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func requestTypingPermission() {
        KeyTypingCounter.shared.ensurePermission(force: true)
    }

    @objc private func showTypingStats() {
        TypingStatsWindowController.shared.present()
    }

    /// 重置 + 诊断 一站式
    @objc private func resetTypingPermission() {
        let report = KeyTypingCounter.diagnosticReport()
        let alert = NSAlert()
        alert.messageText = "诊断：键盘监听 + 一键修复"
        alert.informativeText = """
        \(report)

        ━━━ 自动修法 ━━━
        点【自动重置】→ 跑 tccutil reset → 让系统弹官方对话框 → 你点「允许」

        ━━━ 自动失败时的手动修法（最稳）━━━
        1. 点【打开输入监控面板】
        2. 在列表里找 LazyCat 那条 → 点【—】把它删掉
        3. 退出 LazyCat 再重启（菜单栏猫 → 退出 → 重新打开）
        4. 系统会重新弹对话框，点【允许】
        5. 重启后敲键盘，状态栏图标右边数字应该开始涨
        """
        alert.addButton(withTitle: "自动重置")
        alert.addButton(withTitle: "打开输入监控面板")
        alert.addButton(withTitle: "关闭")
        // 复制诊断信息到剪贴板按钮
        let copyBtn = NSButton(title: "复制诊断", target: self, action: #selector(copyDiagToPasteboard(_:)))
        copyBtn.bezelStyle = .rounded
        alert.window.contentView?.addSubview(copyBtn)
        // 简单 layout：右上角
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        if let cv = alert.window.contentView {
            NSLayoutConstraint.activate([
                copyBtn.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
                copyBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -14),
            ])
        }

        // 把诊断文字临时存起来给「复制诊断」按钮用
        diagnosticText = report

        let resp = alert.runModal()
        switch resp {
        case .alertFirstButtonReturn:
            KeyTypingCounter.shared.resetTCCAndRequest()
        case .alertSecondButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private var diagnosticText: String = ""

    @objc private func copyDiagToPasteboard(_ sender: Any?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(diagnosticText, forType: .string)
    }

    @objc private func pickShakeStyle(_ sender: NSMenuItem) {
        if let s = FloatingWidgetSettings.ShakeStyle(rawValue: sender.tag) {
            FloatingWidgetSettings.shared.setShakeStyle(s)
        }
        if let sub = sender.menu {
            for m in sub.items { m.state = (m.tag == sender.tag) ? .on : .off }
        }
    }

    @objc private func showAbout() {
        AboutWindowController.shared.present()
    }

    @objc private func revealData() {
        let path = Store.shared.dataFilePath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// 打开 ~/Library/Application Support/MyTodoApp/，让用户拖入 cat.png / penguin.png 自定义形象
    @objc private func openImageFolder() {
        let dir = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        NSWorkspace.shared.open(URL(fileURLWithPath: dir))
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func pickOpacity(_ sender: NSMenuItem) {
        let pct = sender.tag
        WindowOpacity.shared.setPercent(pct)
        // 刷新菜单的 ✓ 标记（下次弹出生效）
        if let sub = sender.menu {
            for item in sub.items { item.state = (item.tag == pct) ? .on : .off }
        }
    }

    /// 菜单栏图标：优先 cat.png / cat-01.png；否则把 🐈 emoji 栅格化成一张图片
    /// （关键：在 NSStatusBar 上用 title 设 emoji 经常根本不显示，必须用 image）
    private func menuBarIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let support = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        let baseURL = URL(fileURLWithPath: support)

        @inline(__always) func rasterize(_ raw: NSImage) -> NSImage {
            // aspect-fit 居中绘到 size×size，避免拉伸
            let s = raw.size
            let scale = min(size.width / max(s.width, 1), size.height / max(s.height, 1))
            let fitW = s.width * scale, fitH = s.height * scale
            let dst = NSRect(x: (size.width - fitW) / 2, y: (size.height - fitH) / 2,
                             width: fitW, height: fitH)
            let out = NSImage(size: size)
            out.lockFocus()
            raw.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1.0)
            out.unlockFocus()
            out.isTemplate = false       // 保留颜色
            return out
        }

        // 1) 优先使用用户放的 cat.png / cat-01.png
        for name in ["cat.png", "cat-01.png", "cat-1.png"] {
            let url = baseURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path),
               let raw = NSImage(contentsOf: url) {
                return rasterize(raw)
            }
        }

        // 2) bundle 内置 Assets/cat.png
        if let bundleURL = Bundle.main.url(forResource: "cat", withExtension: "png"),
           let raw = NSImage(contentsOf: bundleURL) {
            return rasterize(raw)
        }

        // 3) 兜底：用 CatRenderer 画一只苗条白猫
        let cat = CatRenderer.makeStatic(size: size)
        cat.isTemplate = false
        return cat
    }
}

extension Notification.Name {
    static let focusQuickAdd = Notification.Name("MyTodo.focusQuickAdd")
}
