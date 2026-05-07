import AppKit

/// LazyCat 主窗口 · UI v5 · 风格 A · macOS Notes 三栏式
///
///   ┌───────────────────────────────────────────────────────┐
///   │ [titlebar]                                            │
///   ├──────────┬──────────────┬─────────────────────────────┤
///   │ Sidebar  │  Mid (list)  │  Right (detail)             │
///   │ 220pt    │  320pt       │  flex                       │
///   │ vibrancy │  subtle bg   │  white bg                   │
///   └──────────┴──────────────┴─────────────────────────────┘
final class ContentViewController: NSViewController {

    private let outer = NSView()

    // 四栏
    private let sidebar = SidebarFilterView(frame: .zero)
    private let midPane = NSView()
    private let rightPane = RightDetailPaneView(frame: .zero)
    private let tgInbox = TGInboxView(frame: .zero)

    // mid pane 内部
    private let midHeader = NSView()
    private let midTitle = NSTextField(labelWithString: "今天")
    private let midCount = NSTextField(labelWithString: "0 个任务")
    private let addBtn = NSButton(title: "＋", target: nil, action: nil)
    private let listScroll = NSScrollView()
    private let listDoc = KeyboardListDocView()
    private let listStack = FlippedStack()
    private var listDocHeight: NSLayoutConstraint!

    // 数据 / 状态
    private var dataObserver: NSObjectProtocol?
    private var typingObserver: NSObjectProtocol?
    private var selectedTaskId: UUID?
    private var searchQuery: String = ""

    override func loadView() {
        outer.wantsLayer = true
        outer.appearance = NSAppearance(named: .aqua)
        outer.layer?.backgroundColor = NSColor(red: 0.96, green: 0.95, blue: 0.93, alpha: 1).cgColor
        view = outer
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        outer.addSubview(sidebar)
        outer.addSubview(midPane)
        outer.addSubview(rightPane)
        outer.addSubview(tgInbox)

        // 列竖分隔线
        let div1 = makeVerticalDivider()
        let div2 = makeVerticalDivider()
        let div3 = makeVerticalDivider()
        outer.addSubview(div1)
        outer.addSubview(div2)
        outer.addSubview(div3)

        // TG inbox callbacks
        tgInbox.onConvertToTask = { [weak self] item in
            self?.convertTGToTask(item)
        }
        tgInbox.onOpenSettings = { [weak self] in
            self?.openTGSettings()
        }

        // mid pane
        midPane.wantsLayer = true
        midPane.layer?.backgroundColor = NSColor(red: 0.972, green: 0.965, blue: 0.945, alpha: 1).cgColor
        midPane.translatesAutoresizingMaskIntoConstraints = false

        midHeader.translatesAutoresizingMaskIntoConstraints = false
        midPane.addSubview(midHeader)

        midTitle.font = LazyCatTheme.body(17, weight: .medium)
        midTitle.textColor = LazyCatTheme.tx1
        midTitle.translatesAutoresizingMaskIntoConstraints = false
        midHeader.addSubview(midTitle)

        midCount.font = LazyCatTheme.body(12, weight: .semibold)
        midCount.textColor = LazyCatTheme.tx3
        midCount.translatesAutoresizingMaskIntoConstraints = false
        midHeader.addSubview(midCount)

        // ＋ 按钮
        addBtn.bezelStyle = .regularSquare
        addBtn.isBordered = false
        addBtn.focusRingType = .none
        addBtn.wantsLayer = true
        addBtn.layer?.cornerRadius = 6
        addBtn.layer?.backgroundColor = LazyCatTheme.accent.cgColor
        addBtn.attributedTitle = NSAttributedString(string: "＋", attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 14, weight: .bold),
        ])
        addBtn.target = self
        addBtn.action = #selector(presentNewTaskEditor)
        addBtn.translatesAutoresizingMaskIntoConstraints = false
        midHeader.addSubview(addBtn)

        let midDivider = NSView()
        midDivider.wantsLayer = true
        midDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        midDivider.translatesAutoresizingMaskIntoConstraints = false
        midPane.addSubview(midDivider)

        // 列表
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.distribution = .fill
        listStack.spacing = 0
        listStack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        listStack.translatesAutoresizingMaskIntoConstraints = false

        listDoc.translatesAutoresizingMaskIntoConstraints = false
        listDoc.addSubview(listStack)
        listDocHeight = listDoc.heightAnchor.constraint(equalToConstant: 100)

        listScroll.documentView = listDoc
        listScroll.hasVerticalScroller = true
        listScroll.scrollerStyle = .overlay
        listScroll.autohidesScrollers = true
        listScroll.drawsBackground = false
        listScroll.translatesAutoresizingMaskIntoConstraints = false
        midPane.addSubview(listScroll)

        // sidebar callbacks
        sidebar.onChange = { [weak self] _ in self?.reload() }
        sidebar.onSearch = { [weak self] q in
            self?.searchQuery = q
            self?.reload()
        }

        // right detail callbacks
        rightPane.onEdit = { [weak self] id in
            self?.openMarkdownEditor(forEditing: id)
        }
        rightPane.onDelete = { [weak self] id in
            self?.confirmAndDelete(id)
        }
        rightPane.onToggleComplete = { id in
            Store.shared.toggleComplete(id)
        }

        // 约束布局
        NSLayoutConstraint.activate([
            // sidebar
            sidebar.topAnchor.constraint(equalTo: outer.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: outer.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 220),

            div1.topAnchor.constraint(equalTo: outer.topAnchor),
            div1.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            div1.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            div1.widthAnchor.constraint(equalToConstant: 0.5),

            // mid pane
            midPane.topAnchor.constraint(equalTo: outer.topAnchor),
            midPane.leadingAnchor.constraint(equalTo: div1.trailingAnchor),
            midPane.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            midPane.widthAnchor.constraint(equalToConstant: 320),

            div2.topAnchor.constraint(equalTo: outer.topAnchor),
            div2.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            div2.leadingAnchor.constraint(equalTo: midPane.trailingAnchor),
            div2.widthAnchor.constraint(equalToConstant: 0.5),

            // right pane
            rightPane.topAnchor.constraint(equalTo: outer.topAnchor),
            rightPane.leadingAnchor.constraint(equalTo: div2.trailingAnchor),
            rightPane.trailingAnchor.constraint(equalTo: div3.leadingAnchor),
            rightPane.bottomAnchor.constraint(equalTo: outer.bottomAnchor),

            // div3
            div3.topAnchor.constraint(equalTo: outer.topAnchor),
            div3.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            div3.trailingAnchor.constraint(equalTo: tgInbox.leadingAnchor),
            div3.widthAnchor.constraint(equalToConstant: 0.5),

            // tg inbox（最右第 4 栏，280pt 宽）
            tgInbox.topAnchor.constraint(equalTo: outer.topAnchor),
            tgInbox.trailingAnchor.constraint(equalTo: outer.trailingAnchor),
            tgInbox.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
            tgInbox.widthAnchor.constraint(equalToConstant: 280),
        ])

        // mid pane 内部约束
        NSLayoutConstraint.activate([
            midHeader.topAnchor.constraint(equalTo: midPane.topAnchor),
            midHeader.leadingAnchor.constraint(equalTo: midPane.leadingAnchor),
            midHeader.trailingAnchor.constraint(equalTo: midPane.trailingAnchor),
            midHeader.heightAnchor.constraint(equalToConstant: 50),

            midTitle.leadingAnchor.constraint(equalTo: midHeader.leadingAnchor, constant: 18),
            midTitle.bottomAnchor.constraint(equalTo: midHeader.bottomAnchor, constant: -8),

            midCount.leadingAnchor.constraint(equalTo: midTitle.trailingAnchor, constant: 8),
            midCount.firstBaselineAnchor.constraint(equalTo: midTitle.firstBaselineAnchor),

            addBtn.trailingAnchor.constraint(equalTo: midHeader.trailingAnchor, constant: -14),
            addBtn.centerYAnchor.constraint(equalTo: midTitle.centerYAnchor),
            addBtn.widthAnchor.constraint(equalToConstant: 26),
            addBtn.heightAnchor.constraint(equalToConstant: 26),

            midDivider.topAnchor.constraint(equalTo: midHeader.bottomAnchor),
            midDivider.leadingAnchor.constraint(equalTo: midPane.leadingAnchor),
            midDivider.trailingAnchor.constraint(equalTo: midPane.trailingAnchor),
            midDivider.heightAnchor.constraint(equalToConstant: 0.5),

            listScroll.topAnchor.constraint(equalTo: midDivider.bottomAnchor),
            listScroll.leadingAnchor.constraint(equalTo: midPane.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: midPane.trailingAnchor),
            listScroll.bottomAnchor.constraint(equalTo: midPane.bottomAnchor),

            listDoc.widthAnchor.constraint(equalTo: listScroll.widthAnchor),
            listDocHeight,
            listStack.topAnchor.constraint(equalTo: listDoc.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: listDoc.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listDoc.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: listDoc.bottomAnchor),
        ])

        // 键盘 ↑/↓/Enter
        listDoc.onArrow = { [weak self] dir in self?.moveSelection(dir) }
        listDoc.onEnter = { [weak self] in
            if let id = self?.selectedTaskId {
                TaskDetailController.present(taskId: id)
            }
        }

        // 监听
        dataObserver = NotificationCenter.default.addObserver(
            forName: Store.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reload()
        }
        typingObserver = NotificationCenter.default.addObserver(
            forName: .typingKeyDown, object: nil, queue: .main) { [weak self] _ in
                self?.sidebar.rebuild()
        }
        NotificationCenter.default.addObserver(
            forName: .focusQuickAdd, object: nil, queue: .main) { [weak self] _ in
                self?.presentNewTaskEditor()
        }

        sidebar.rebuild()
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(listDoc)
    }

    deinit {
        if let o = dataObserver { NotificationCenter.default.removeObserver(o) }
        if let o = typingObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func makeVerticalDivider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.10).cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }

    // MARK: - 数据 reload

    private func reload() {
        sidebar.rebuild()

        let all = Store.shared.data.tasks
        var pool = applyFilter(all, sidebar.current)

        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            pool = pool.filter {
                $0.text.lowercased().contains(q) || $0.person.lowercased().contains(q)
            }
        }

        // 排序
        pool.sort { a, b in
            if a.priority.rawValue != b.priority.rawValue {
                return a.priority.rawValue > b.priority.rawValue
            }
            let ka = a.remindAt ?? a.createdAt
            let kb = b.remindAt ?? b.createdAt
            return ka < kb
        }

        // 更新 mid header
        midTitle.stringValue = filterTitle(sidebar.current)
        midCount.stringValue = "\(pool.count) 个任务"

        // 列表重建
        for v in listStack.arrangedSubviews { listStack.removeArrangedSubview(v) }
        for v in listStack.subviews { v.removeFromSuperview() }

        var totalH: CGFloat = listStack.edgeInsets.top + listStack.edgeInsets.bottom
        for task in pool {
            let row = MidListRow(task: task)
            row.isSelected = (task.id == selectedTaskId)
            row.onClick = { [weak self] in
                guard let self = self else { return }
                self.selectedTaskId = task.id
                for v in self.listStack.arrangedSubviews {
                    if let r = v as? MidListRow {
                        r.isSelected = (r.task.id == task.id)
                    }
                }
                self.rightPane.show(task)
                self.view.window?.makeFirstResponder(self.listDoc)
            }
            row.onToggleCheck = { id in Store.shared.toggleComplete(id) }
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor,
                                       constant: -(listStack.edgeInsets.left + listStack.edgeInsets.right)).isActive = true
            totalH += 50
        }
        listDocHeight.constant = max(totalH + 6, 100)

        // 同步右侧 detail
        if let id = selectedTaskId, let t = pool.first(where: { $0.id == id }) ?? all.first(where: { $0.id == id }) {
            rightPane.show(t)
        } else if let firstTask = pool.first {
            selectedTaskId = firstTask.id
            for v in listStack.arrangedSubviews {
                if let r = v as? MidListRow {
                    r.isSelected = (r.task.id == firstTask.id)
                }
            }
            rightPane.show(firstTask)
        } else {
            selectedTaskId = nil
            rightPane.showEmpty()
        }
    }

    private func filterTitle(_ f: SidebarFilterView.Filter) -> String {
        switch f {
        case .today: return "今天"
        case .week:  return "本周"
        case .all:   return "全部"
        case .done:  return "已完成"
        case .byPerson(let n): return "@\(n)"
        case .byPriority(let p):
            switch p {
            case .top:  return "T0 紧急"
            case .mid:  return "T1 重要"
            case .low:  return "T2 一般"
            case .none: return "无优先级"
            }
        }
    }

    private func applyFilter(_ tasks: [TodoItem], _ f: SidebarFilterView.Filter) -> [TodoItem] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let weekEnd = cal.date(byAdding: .day, value: 7, to: today) ?? now
        switch f {
        case .today:
            return tasks.filter { !$0.completed && (cal.startOfDay(for: $0.remindAt ?? $0.createdAt)) <= today }
        case .week:
            return tasks.filter { !$0.completed && ($0.remindAt ?? $0.createdAt) <= weekEnd }
        case .all:
            return tasks.filter { !$0.completed }
        case .done:
            return tasks.filter { $0.completed }
        case .byPerson(let name):
            return tasks.filter { $0.person == name }
        case .byPriority(let p):
            return tasks.filter { !$0.completed && $0.priority == p }
        }
    }

    // MARK: - 操作

    @objc private func presentNewTaskEditor() {
        let vc = MarkdownEditorViewController()
        vc.preset(person: defaultPersonForFilter(), priority: .none)
        vc.onSave = { [weak self] task in
            _ = Store.shared.addTask(person: task.person, text: task.text,
                                     imageFiles: task.imageFiles, priority: task.priority,
                                     remindAt: task.remindAt)
            Store.shared.rememberPerson(task.person)
            // 自动选中新建的任务
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.selectedTaskId = Store.shared.data.tasks.last?.id
                self?.reload()
            }
        }
        presentAsSheet(vc)
    }

    private func defaultPersonForFilter() -> String {
        if case .byPerson(let name) = sidebar.current { return name }
        return ""
    }

    private func openMarkdownEditor(forEditing id: UUID) {
        // 简化：复用详情窗口（已有完整编辑能力）
        TaskDetailController.present(taskId: id)
    }

    private func openTGSettings() {
        let vc = TelegramLoginViewController()
        presentAsSheet(vc)
    }

    private func convertTGToTask(_ item: InboxMessage) {
        // 图片 import 进 images/(若有)
        var savedImage: String? = nil
        if let p = item.imageLocalPath, let img = NSImage(contentsOfFile: p),
           let saved = Store.shared.saveImage(img) {
            savedImage = saved
        }

        // 同人 + 私聊 + 24h 内已存在任务 → 追加到 messages[]; 否则建新任务
        let now = Date()
        let cutoff = now.addingTimeInterval(-24 * 3600)
        if item.isPrivate,
           let idx = Store.shared.data.tasks.firstIndex(where: {
               !$0.completed
                && $0.tgChatType == "private"
                && $0.person == item.senderName
                && $0.createdAt >= cutoff
           }) {
            // 追加
            var t = Store.shared.data.tasks[idx]
            t.messages.append(TaskMessage(
                from: item.senderName, text: item.text,
                date: item.date, imageFile: savedImage))
            if let img = savedImage { t.imageFiles.append(img) }
            Store.shared.updateTask(t)
            AppLog.log("TG → 追加到已有任务: \(t.text.prefix(30))")
        } else {
            // 新建。第一条 messages 也存进去，保证详情页"消息记录"分组始终有内容
            var attached: [String] = []
            if let img = savedImage { attached.append(img) }
            let prefix = item.isPrivate ? "📨 \(item.senderName)" : "📨 \(item.sourceLabel) @ "
            let title = "\(prefix) · \(item.text.prefix(30))"
            var t = TodoItem(person: item.senderName, text: title,
                             imageFiles: attached, priority: .none,
                             note: "", remindAt: nil)
            t.tgChatType = item.isPrivate ? "private" : "group"
            t.tgSourceLabel = item.sourceLabel
            t.messages = [TaskMessage(
                from: item.senderName, text: item.text,
                date: item.date, imageFile: savedImage)]
            Store.shared.addTaskRaw(t)
        }
        Store.shared.rememberPerson(item.senderName)
        TelegramTDLib.shared.dismiss(item.id)
    }

    /// 键盘上下移动选中
    fileprivate func moveSelection(_ dir: Int) {
        let rows = listStack.arrangedSubviews.compactMap { $0 as? MidListRow }
        guard !rows.isEmpty else { return }
        let curIdx = rows.firstIndex(where: { $0.task.id == selectedTaskId }) ?? 0
        let newIdx = max(0, min(rows.count - 1, curIdx + dir))
        let target = rows[newIdx]
        selectedTaskId = target.task.id
        for r in rows { r.isSelected = (r.task.id == target.task.id) }
        rightPane.show(target.task)
        // 滚动可见
        listScroll.contentView.scrollToVisible(target.frame.insetBy(dx: 0, dy: -8))
        // 始终保持 listDoc 焦点
        view.window?.makeFirstResponder(listDoc)
    }

    private func confirmAndDelete(_ id: UUID) {
        let alert = NSAlert()
        alert.messageText = "确定删除该任务？"
        alert.informativeText = "删除后无法恢复"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            if selectedTaskId == id { selectedTaskId = nil }
            Store.shared.deleteTask(id)
        }
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 中列 doc view：接收 ↑↓Enter
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
final class KeyboardListDocView: FlippedDocView {
    /// dir = -1 (上) / +1 (下)
    var onArrow: ((Int) -> Void)?
    var onEnter: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: onArrow?(-1)              // ↑
        case 125: onArrow?(+1)              // ↓
        case 36, 76: onEnter?()             // Return / Enter
        default: super.keyDown(with: event)
        }
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - PriorityDotPicker（MarkdownEditor 也用到）
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class PriorityDotPicker: NSView {
    var priority: Priority = .none {
        didSet { updateButtons() }
    }
    private var btns: [NSButton] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = LazyCatTheme.cornerSm
        layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let opts: [(Priority, NSColor)] = [
            (.none, LazyCatTheme.tx4),
            (.low, LazyCatTheme.green),
            (.mid, LazyCatTheme.accent),
            (.top, LazyCatTheme.red),
        ]
        for (p, color) in opts {
            let b = NSButton(title: "", target: self, action: #selector(pick(_:)))
            b.tag = p.rawValue
            b.bezelStyle = .circular
            b.isBordered = false
            b.focusRingType = .none
            b.wantsLayer = true
            b.layer?.cornerRadius = 7
            b.layer?.backgroundColor = color.cgColor
            b.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(b)
            NSLayoutConstraint.activate([
                b.widthAnchor.constraint(equalToConstant: 14),
                b.heightAnchor.constraint(equalToConstant: 14),
            ])
            btns.append(b)
        }

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateButtons()
    }

    @objc private func pick(_ sender: NSButton) {
        priority = Priority(rawValue: sender.tag) ?? .none
    }

    private func updateButtons() {
        for b in btns {
            let isOn = b.tag == priority.rawValue
            b.layer?.borderWidth = isOn ? 2 : 0
            b.layer?.borderColor = NSColor.white.cgColor
        }
    }
}


// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// MARK: - 中列任务行（带选中态、check、优先级竖条、人 / 时间）
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

final class MidListRow: NSView {
    let task: TodoItem
    var onClick: (() -> Void)?
    var onToggleCheck: ((UUID) -> Void)?

    var isSelected: Bool = false { didSet { restyle() } }

    private let bg = NSView()
    private let check = CheckCircleView()
    private let priBar = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")

    init(task: TodoItem) {
        self.task = task
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 6
        bg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bg)

        check.isOn = task.completed
        check.translatesAutoresizingMaskIntoConstraints = false
        check.onClick = { [weak self] in
            guard let self = self else { return }
            self.onToggleCheck?(self.task.id)
        }
        bg.addSubview(check)

        priBar.wantsLayer = true
        priBar.layer?.cornerRadius = 1.5
        // 严格按原型：每行都有色条，默认 (.none/.mid) 用 accent 橙、.top 红、.low 绿
        let barColor: NSColor = {
            switch task.priority {
            case .top: return LazyCatTheme.red
            case .low: return LazyCatTheme.green
            case .mid, .none: return LazyCatTheme.accent
            }
        }()
        priBar.layer?.backgroundColor = barColor.cgColor
        priBar.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(priBar)

        let firstLine = task.text.components(separatedBy: "\n").first ?? task.text
        titleLabel.stringValue = firstLine.isEmpty ? "(仅图片)" : firstLine.replacingOccurrences(of: "# ", with: "")
        titleLabel.font = LazyCatTheme.body(13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(titleLabel)

        var metaParts: [String] = []
        if !task.person.isEmpty { metaParts.append("@\(task.person)") }
        if let r = task.remindAt {
            metaParts.append("⏰ " + TaskRowView.smartDate(r))
        } else {
            metaParts.append(TaskRowView.smartDate(task.createdAt))
        }
        if !task.imageFiles.isEmpty { metaParts.append("🖼") }
        metaLabel.stringValue = metaParts.joined(separator: " · ")
        metaLabel.font = LazyCatTheme.body(11, weight: .medium)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(metaLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 50),

            bg.leadingAnchor.constraint(equalTo: leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: trailingAnchor),
            bg.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            bg.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            check.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 10),
            check.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 14),
            check.heightAnchor.constraint(equalToConstant: 14),

            priBar.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
            priBar.topAnchor.constraint(equalTo: bg.topAnchor, constant: 8),
            priBar.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -8),
            priBar.widthAnchor.constraint(equalToConstant: 3),

            titleLabel.leadingAnchor.constraint(equalTo: priBar.trailingAnchor, constant: 9),
            titleLabel.topAnchor.constraint(equalTo: bg.topAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -10),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -10),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
        ])

        restyle()
    }

    private func restyle() {
        if isSelected {
            bg.layer?.backgroundColor = LazyCatTheme.accent.cgColor
            titleLabel.textColor = .white
            metaLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        } else {
            bg.layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = task.completed ? LazyCatTheme.tx3 : LazyCatTheme.tx1
            metaLabel.textColor = LazyCatTheme.tx3
        }
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
            bg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        }
    }
    override func mouseExited(with event: NSEvent) {
        if !isSelected {
            bg.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            TaskDetailController.present(taskId: task.id)
        } else {
            onClick?()
        }
    }
}
