import AppKit

/// Style B · 治愈系暖橘 风格的菜单弹窗（替代系统 NSMenu）
///   - 顶部状态卡：🐈 LazyCat 在守候 + 今日键数 + 连续天数
///   - 主操作按 section 分组
///   - 子菜单（多档透明度 / 字号 / 形态…）仍走系统 NSMenu，但通过 attributedTitle 染色
///     在用户点击该行时 popUp
final class LazyCatMenuPopover: NSObject {

    private let popover = NSPopover()
    private let vc: LazyCatPopoverVC

    init(menuController: MenuBarController) {
        vc = LazyCatPopoverVC(menuController: menuController)
        super.init()
        popover.behavior = .transient
        popover.animates = false   // 关掉默认淡入动画，点击立刻出，避免"悬停延迟感"
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = vc
        vc.popover = self
    }

    func toggle(at button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // ★ 必须先触发 viewDidLoad，否则 refresh() 访问 docHeight! 会 nil 崩溃
        _ = vc.view
        vc.refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func close() { popover.performClose(nil) }

    /// 在 popover 行点击 submenu 时调 —— 不关 popover，直接在它之上 popUp NSMenu。
    /// 临时把 popover.behavior 改成 .applicationDefined 防止 NSMenu 拉起时
    /// .transient 把 popover 误判为"应该关闭"。popUp 是阻塞的，返回后恢复。
    func showSubmenu(_ menu: NSMenu, atScreenPoint pt: NSPoint) {
        let prev = popover.behavior
        popover.behavior = .applicationDefined
        menu.popUp(positioning: nil, at: pt, in: nil)
        popover.behavior = prev
        // 用户挑完后，刷新 popover 让状态徽章（如"82%"、"中（默认）"）跟上
        vc.refresh()
    }
}

// FlippedStack / FlippedDocView 已在 MainWindowComponents.swift 中声明（internal），这里直接复用

// MARK: - 菜单条目模型

struct LazyCatPopoverItem {
    enum Kind {
        case action(Selector)              // 直接调 menuController 上的 @objc 方法
        case submenu(() -> NSMenu)         // 点击时弹出 NSMenu
        case info                          // 灰底信息行（不可点）
        case separator
        case sectionLabel(String)
    }
    var icon: String? = nil
    var title: String = ""
    var trailing: String? = nil    // 右侧文字（快捷键 / "已开" 等）
    var kind: Kind = .info
    var highlighted: Bool = false  // 暖橙高亮（如启用中的功能）
    var dangerous: Bool = false    // 红色（退出）
}

// MARK: - 内容控制器

final class LazyCatPopoverVC: NSViewController {

    fileprivate weak var popover: LazyCatMenuPopover?
    private weak var menuController: MenuBarController?

    private let header = LazyCatPopoverHeaderView()
    private let stack = FlippedStack()
    private let docContainer = FlippedDocView()   // ★ 包一层翻转容器当 documentView，确保 (0,0)=top-left
    private let scroll = NSScrollView()
    private var docHeight: NSLayoutConstraint!     // 文档容器高度，每次 refresh 时按真实内容算

    /// 上次 refresh 时的"结构指纹"——只比 kind+title+icon，不比 trailing/highlighted
    /// 结构没变就只更新可变字段（trailing 文字 / 高亮态），不重建 NSView，免去全局 layout 抖动
    private var lastStructureFingerprint: String = ""
    /// 当前活动的行（与 stack.arrangedSubviews 一一对应），便于只更新 trailing 等
    private var currentRows: [LazyCatPopoverRow] = []

    init(menuController: MenuBarController) {
        self.menuController = menuController
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 640))
        v.wantsLayer = true
        v.layer?.backgroundColor = LazyCatTheme.bg.cgColor
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        docContainer.translatesAutoresizingMaskIntoConstraints = false
        docContainer.addSubview(stack)

        scroll.documentView = docContainer
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = false
        scroll.automaticallyAdjustsContentInsets = false
        view.addSubview(scroll)

        docHeight = docContainer.heightAnchor.constraint(equalToConstant: 100)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 72),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // doc container 宽度跟 scroll 走，高度由 refresh() 计算并设置 docHeight
            docContainer.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            docHeight,

            // stack 在 docContainer 里铺满
            stack.topAnchor.constraint(equalTo: docContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor),
        ])
    }

    func refresh() {
        guard let mc = menuController else { return }
        header.refresh()

        let items = mc.buildPopoverItems()

        // 结构指纹：kind 类型 + icon + title。只比静态部分。
        // trailing / highlighted 是可变状态，不进指纹（这样状态变化也不重建结构）
        let fp = items.map { it -> String in
            let k: String
            switch it.kind {
            case .separator:    k = "sep"
            case .sectionLabel(let s): k = "sec:\(s)"
            case .action:       k = "act"
            case .submenu:      k = "sub"
            case .info:         k = "info"
            }
            // 把 trailing「是否存在」也计入指纹（影响是否要画右边的 pill），但 trailing 的具体文字不计入
            return "\(k)|\(it.icon ?? "")|\(it.title)|\(it.trailing == nil ? 0 : 1)"
        }.joined(separator: "\n")

        // 结构没变 → 只滚动 trailing/高亮，省掉 20+ 行 NSView 拆装
        if fp == lastStructureFingerprint, currentRows.count == items.count {
            for (i, it) in items.enumerated() {
                currentRows[i].updateMutable(item: it)
            }
            return
        }
        lastStructureFingerprint = fp

        // 结构变了：清空 + 全部重建
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        currentRows.removeAll(keepingCapacity: true)

        // 按声明性配置渲染 + 手算总高度（不依赖 NSStackView.fittingSize，那玩意时机不稳）
        var contentH: CGFloat = stack.edgeInsets.top + stack.edgeInsets.bottom
        for it in items {
            let row = LazyCatPopoverRow(item: it, controller: mc, popover: self)
            stack.addArrangedSubview(row)
            currentRows.append(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                       constant: -stack.edgeInsets.left - stack.edgeInsets.right).isActive = true
            // 每行类型对应的实际高度（跟 LazyCatPopoverRow.build() 里的约束一致）
            switch it.kind {
            case .separator:    contentH += 13   // 6 top + 1 line + 6 bottom
            case .sectionLabel: contentH += 26   // 10 top + ~14 label + 2 bottom
            default:            contentH += 32   // 显式 heightAnchor = 32
            }
        }
        if items.count > 1 {
            contentH += stack.spacing * CGFloat(items.count - 1)
        }

        // ★ 设置 docContainer 高度 = 真实内容高度（让 scroll 知道整个文档多高）
        docHeight.constant = contentH

        // popover 主体高度上限（NSPopover 太高会拖出屏幕）
        let maxBody: CGFloat = 620
        let bodyH = min(contentH, maxBody)
        let total = bodyH + 72
        let newSize = NSSize(width: 320, height: total)
        view.frame.size = newSize
        preferredContentSize = newSize

        // 翻转文档里 (0,0) 是 top —— 强制滚到顶
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.scroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
            self.scroll.reflectScrolledClipView(self.scroll.contentView)
        }
    }
}

// MARK: - 顶部状态卡

private final class LazyCatPopoverHeaderView: NSView {

    private let avatar = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "LazyCat 在守候")
    private let subLabel = NSTextField(labelWithString: "")
    private let bgCard = NSView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = LazyCatTheme.bg.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        bgCard.wantsLayer = true
        bgCard.layer?.cornerRadius = LazyCatTheme.cornerLg
        bgCard.layer?.backgroundColor = NSColor.clear.cgColor
        // 渐变橙底
        let g = CAGradientLayer()
        g.colors = [
            LazyCatTheme.accentLight.cgColor,
            LazyCatTheme.bgSurface.cgColor,
        ]
        g.startPoint = CGPoint(x: 0, y: 0.5)
        g.endPoint = CGPoint(x: 1, y: 0.5)
        g.cornerRadius = LazyCatTheme.cornerLg
        bgCard.layer?.insertSublayer(g, at: 0)
        bgCard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bgCard)

        // 优先用户数据目录里的 cat.png；否则 bundle 自带的 Assets/cat.png
        let support = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        let userCat = URL(fileURLWithPath: support).appendingPathComponent("cat.png")
        if FileManager.default.fileExists(atPath: userCat.path),
           let img = NSImage(contentsOf: userCat) {
            avatar.image = img
        } else if let url = Bundle.main.url(forResource: "cat", withExtension: "png"),
                  let img = NSImage(contentsOf: url) {
            avatar.image = img
        }
        avatar.imageScaling = .scaleProportionallyUpOrDown
        avatar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatar)

        nameLabel.font = LazyCatTheme.body(14, weight: .heavy)
        nameLabel.textColor = LazyCatTheme.textPrimary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        subLabel.font = LazyCatTheme.body(11, weight: .medium)
        subLabel.textColor = LazyCatTheme.textSec
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subLabel)

        NSLayoutConstraint.activate([
            bgCard.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            bgCard.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            bgCard.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            bgCard.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            avatar.leadingAnchor.constraint(equalTo: bgCard.leadingAnchor, constant: 14),
            avatar.centerYAnchor.constraint(equalTo: bgCard.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 38),
            avatar.heightAnchor.constraint(equalToConstant: 38),

            nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: bgCard.topAnchor, constant: 12),

            subLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            subLabel.trailingAnchor.constraint(lessThanOrEqualTo: bgCard.trailingAnchor, constant: -10),
        ])
    }

    override func layout() {
        super.layout()
        // 渐变层尺寸跟着卡片
        if let g = bgCard.layer?.sublayers?.first as? CAGradientLayer {
            g.frame = bgCard.bounds
        }
    }

    func refresh() {
        let n = KeyTypingCounter.shared.todayCount
        // 一句话副标题：今日键数 + 友好语
        let mood: String
        switch n {
        case 0:        mood = "等你回来 🐾"
        case 1...499:  mood = "刚开始热身 ☕"
        case 500..<2000:  mood = "状态在线 💪"
        case 2000..<5000: mood = "手很热 🔥"
        case 5000..<10000:mood = "高产中 ⚡"
        default:       mood = "停不下来啦 🚀"
        }
        subLabel.stringValue = "今日 \(n) 键 · \(mood)"
    }
}

// MARK: - 单行

private final class LazyCatPopoverRow: NSView {

    private(set) var item: LazyCatPopoverItem
    weak var controller: MenuBarController?
    weak var popover: LazyCatPopoverVC?

    private var iconLabel: NSTextField?
    private var titleLabel: NSTextField?
    private var trailingLabel: NSTextField?
    private var chevron: NSTextField?

    private var isHover = false
    private var trackingArea: NSTrackingArea?

    init(item: LazyCatPopoverItem, controller: MenuBarController, popover: LazyCatPopoverVC) {
        self.item = item
        self.controller = controller
        self.popover = popover
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 结构未变时调：只更新可变状态（trailing 文字、高亮态），免去拆装 NSView 的开销
    func updateMutable(item newItem: LazyCatPopoverItem) {
        self.item = newItem
        // trailing pill 文字
        if let tl = trailingLabel {
            tl.stringValue = newItem.trailing ?? ""
        }
        // 高亮（启用中的功能 = 暖橙加粗）
        if let t = titleLabel {
            t.font = LazyCatTheme.body(13, weight: newItem.highlighted ? .bold : .medium)
            t.textColor = newItem.dangerous
                ? NSColor(red: 0.8, green: 0.25, blue: 0.20, alpha: 1)
                : (newItem.highlighted ? LazyCatTheme.accent : LazyCatTheme.textPrimary)
        }
    }

    private func build() {
        switch item.kind {
        case .separator:
            let line = NSView()
            line.wantsLayer = true
            line.layer?.backgroundColor = LazyCatTheme.border.cgColor
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                line.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                line.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                line.heightAnchor.constraint(equalToConstant: 1),
                line.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            ])
            return
        case .sectionLabel(let s):
            let l = NSTextField(labelWithString: s)
            l.font = LazyCatTheme.body(10, weight: .heavy)
            l.textColor = LazyCatTheme.textTer
            l.translatesAutoresizingMaskIntoConstraints = false
            addSubview(l)
            NSLayoutConstraint.activate([
                l.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                l.topAnchor.constraint(equalTo: topAnchor, constant: 10),
                l.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            ])
            return
        default: break
        }

        layer?.cornerRadius = LazyCatTheme.cornerSm
        layer?.backgroundColor = NSColor.clear.cgColor

        // 图标
        let ico = NSTextField(labelWithString: item.icon ?? "")
        ico.font = .systemFont(ofSize: 14)
        ico.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ico); iconLabel = ico

        // 标题
        let t = NSTextField(labelWithString: item.title)
        t.font = LazyCatTheme.body(13, weight: item.highlighted ? .bold : .medium)
        t.textColor = item.dangerous
            ? NSColor(red: 0.8, green: 0.25, blue: 0.20, alpha: 1)
            : (item.highlighted ? LazyCatTheme.accent : LazyCatTheme.textPrimary)
        t.lineBreakMode = .byTruncatingTail
        t.translatesAutoresizingMaskIntoConstraints = false
        addSubview(t); titleLabel = t

        // 右侧
        if let trailing = item.trailing {
            let tl = NSTextField(labelWithString: trailing)
            tl.font = LazyCatTheme.body(10.5, weight: .semibold)
            tl.textColor = LazyCatTheme.textTer
            tl.alignment = .right
            tl.wantsLayer = true
            tl.layer?.cornerRadius = 4
            tl.layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
            tl.drawsBackground = true
            tl.backgroundColor = LazyCatTheme.bgSurface
            tl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(tl); trailingLabel = tl
        }

        // submenu 用 ▶ chevron
        if case .submenu = item.kind {
            let c = NSTextField(labelWithString: "›")
            c.font = LazyCatTheme.body(14, weight: .heavy)
            c.textColor = LazyCatTheme.textTer
            c.translatesAutoresizingMaskIntoConstraints = false
            addSubview(c); chevron = c
        }

        // 约束
        var cons: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 32),
            ico.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            ico.centerYAnchor.constraint(equalTo: centerYAnchor),
            ico.widthAnchor.constraint(equalToConstant: 22),

            t.leadingAnchor.constraint(equalTo: ico.trailingAnchor, constant: 6),
            t.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        if let chev = chevron {
            cons += [
                chev.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                chev.centerYAnchor.constraint(equalTo: centerYAnchor),
            ]
            if let tl = trailingLabel {
                cons += [
                    tl.trailingAnchor.constraint(equalTo: chev.leadingAnchor, constant: -6),
                    tl.centerYAnchor.constraint(equalTo: centerYAnchor),
                    tl.heightAnchor.constraint(equalToConstant: 18),
                ]
                cons += [t.trailingAnchor.constraint(lessThanOrEqualTo: tl.leadingAnchor, constant: -6)]
            } else {
                cons += [t.trailingAnchor.constraint(lessThanOrEqualTo: chev.leadingAnchor, constant: -6)]
            }
        } else if let tl = trailingLabel {
            cons += [
                tl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                tl.centerYAnchor.constraint(equalTo: centerYAnchor),
                tl.heightAnchor.constraint(equalToConstant: 18),
                t.trailingAnchor.constraint(lessThanOrEqualTo: tl.leadingAnchor, constant: -6),
            ]
        } else {
            cons += [t.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10)]
        }
        NSLayoutConstraint.activate(cons)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let t = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        isHover = true
        layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        guard isInteractive else { return }
        isHover = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    private var isInteractive: Bool {
        switch item.kind {
        case .action, .submenu: return true
        default: return false
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let mc = controller else { return }
        switch item.kind {
        case .action(let sel):
            popover?.popover?.close()
            // 异步派发，让 popover 关闭动画先跑
            DispatchQueue.main.async {
                _ = mc.perform(sel)
            }
        case .submenu(let builder):
            // ★ 不关 popover —— 让 NSMenu 像 macOS 原生 cascade 子菜单 fly-out 在 popover 右侧
            //   行的屏幕坐标先抓好；popover.behavior 在 showSubmenu 里临时切成 .applicationDefined
            //   防止 NSMenu 出现时把 popover 误关
            let menu = builder()
            let rowBoundsInWin = self.convert(self.bounds, to: nil)
            let screenRect = self.window?.convertToScreen(rowBoundsInWin) ?? .zero
            let screenPoint = NSPoint(x: screenRect.maxX + 4, y: screenRect.midY)
            popover?.popover?.showSubmenu(menu, atScreenPoint: screenPoint)
        default: break
        }
    }
}
