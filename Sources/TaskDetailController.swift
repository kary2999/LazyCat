import AppKit

/// 点击任务行正文 → 弹出详情面板（可滚动长文 / 看图 / 改备注 / 改优先级 / 改提醒）
final class TaskDetailController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    /// 防止控制器被释放：活的 controller 都在这里
    private static var active: [UUID: TaskDetailController] = [:]

    private let taskId: UUID

    private let metaLabel  = NSTextField(labelWithString: "")
    private let statusChip = NSTextField(labelWithString: "")
    private let textView: NSTextView = {
        let tc = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        let lm = NSLayoutManager()
        lm.addTextContainer(tc)
        let ts = NSTextStorage()
        ts.addLayoutManager(lm)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300),
                            textContainer: tc)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        return tv
    }()
    private let noteField = NSTextField()
    private let priorityBtn = NSButton()
    private let reminderBtn = NSButton()
    private let imagesStack = NSStackView()
    private let imagesScroll = NSScrollView()
    private var imagesHeightC: NSLayoutConstraint!

    private let completeBtn = NSButton(title: "标记完成", target: nil, action: nil)
    private let deleteBtn   = NSButton(title: "删除", target: nil, action: nil)
    private let closeBtn    = NSButton(title: "关闭", target: nil, action: nil)

    /// 用户正在编辑正文时，refresh() 不能覆盖未保存的内容
    private var userIsEditing = false
    /// 延迟保存计时器，避免每敲一个字就写盘
    private var saveDebounce: Timer?

    init(taskId: UUID) {
        self.taskId = taskId
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        w.title = "事件详情"
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 480, height: 360)
        // ★ Style B：强制浅色，跟主窗口一致
        w.appearance = NSAppearance(named: .aqua)
        w.backgroundColor = LazyCatTheme.bg
        super.init(window: w)
        w.delegate = self
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                               name: Store.didChangeNotification, object: nil)
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func windowWillClose(_ notification: Notification) {
        commitTextEditIfNeeded()
        TaskDetailController.active.removeValue(forKey: taskId)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var task: TodoItem? {
        Store.shared.data.tasks.first(where: { $0.id == taskId })
    }

    private func build() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = LazyCatTheme.bg.cgColor

        // meta: @人 · 创建时间（点击 metaLabel 可修改人名）
        metaLabel.font = LazyCatTheme.body(12, weight: .semibold)
        metaLabel.textColor = LazyCatTheme.textSec
        metaLabel.maximumNumberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        // 覆盖一个透明按钮，整段可点击
        let metaBtn = NSButton(title: "", target: self, action: #selector(editPerson))
        metaBtn.isBordered = false
        metaBtn.isTransparent = true
        metaBtn.toolTip = "点击修改 @人名"
        metaBtn.translatesAutoresizingMaskIntoConstraints = false

        // 右上角状态彩色胶囊（小号 chip 风，不再像按钮）
        statusChip.font = LazyCatTheme.body(10.5, weight: .heavy)
        statusChip.textColor = .white
        statusChip.alignment = .center
        statusChip.isBezeled = false
        statusChip.drawsBackground = false
        statusChip.wantsLayer = true
        statusChip.layer?.cornerRadius = 5
        statusChip.layer?.masksToBounds = true
        statusChip.translatesAutoresizingMaskIntoConstraints = false

        // 正文滚动（主体，可编辑，失焦 / 命令+S 自动保存）
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.white            // ★ 强制白底（不跟系统暗色走）
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = LazyCatTheme.textPrimary       // ★ 暖深棕字
        textView.insertionPointColor = LazyCatTheme.accent  // ★ 橙色光标
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.typingAttributes = [
            .font: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: LazyCatTheme.textPrimary,
        ]
        textView.delegate = self
        let textScroll = NSScrollView()
        textScroll.documentView = textView
        textScroll.hasVerticalScroller = true
        textScroll.hasHorizontalScroller = false
        textScroll.borderType = .noBorder
        textScroll.drawsBackground = true
        textScroll.backgroundColor = NSColor.white
        textScroll.wantsLayer = true
        textScroll.layer?.cornerRadius = LazyCatTheme.cornerSm
        textScroll.layer?.borderColor = LazyCatTheme.border.cgColor
        textScroll.layer?.borderWidth = 1
        textScroll.translatesAutoresizingMaskIntoConstraints = false

        // 工具行：优先级 / 提醒 / 备注 —— Secondary 按钮样
        LazyCatTheme.applyButtonStyle(priorityBtn, style: .secondary)
        priorityBtn.target = self
        priorityBtn.action = #selector(changePriority)
        priorityBtn.translatesAutoresizingMaskIntoConstraints = false

        LazyCatTheme.applyButtonStyle(reminderBtn, style: .secondary)
        reminderBtn.target = self
        reminderBtn.action = #selector(changeReminder)
        reminderBtn.translatesAutoresizingMaskIntoConstraints = false

        noteField.placeholderString = "备注 (50 字，回车保存)"
        noteField.font = LazyCatTheme.body(12)
        noteField.bezelStyle = .roundedBezel
        noteField.textColor = LazyCatTheme.tx1
        noteField.target = self
        noteField.action = #selector(saveNote)
        noteField.translatesAutoresizingMaskIntoConstraints = false

        let toolsRow = NSStackView(views: [priorityBtn, reminderBtn, noteField])
        toolsRow.orientation = .horizontal
        toolsRow.spacing = 8
        toolsRow.distribution = .fill
        toolsRow.translatesAutoresizingMaskIntoConstraints = false

        // 图片横排（无图时彻底折叠）
        imagesStack.orientation = .horizontal
        imagesStack.spacing = 8
        imagesStack.alignment = .centerY
        imagesStack.translatesAutoresizingMaskIntoConstraints = false
        imagesScroll.documentView = imagesStack
        imagesScroll.drawsBackground = false
        imagesScroll.borderType = .noBorder
        imagesScroll.hasVerticalScroller = false
        imagesScroll.hasHorizontalScroller = false
        imagesScroll.translatesAutoresizingMaskIntoConstraints = false
        imagesHeightC = imagesScroll.heightAnchor.constraint(equalToConstant: 0)
        imagesHeightC.isActive = true

        // 底部动作 —— 严格 4 种 token
        // ✓ 标记完成 = primary（橙底白字）
        LazyCatTheme.applyButtonStyle(completeBtn, style: .primary)
        completeBtn.attributedTitle = LazyCatTheme.makeBtnTitle("✓ 标记完成", style: .primary)
        completeBtn.target = self
        completeBtn.action = #selector(markComplete)
        completeBtn.translatesAutoresizingMaskIntoConstraints = false

        // 🗑 删除 = dangerGhost（白底红字红边）
        LazyCatTheme.applyButtonStyle(deleteBtn, style: .dangerGhost)
        deleteBtn.attributedTitle = LazyCatTheme.makeBtnTitle("🗑 删除", style: .dangerGhost)
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteTask)
        deleteBtn.translatesAutoresizingMaskIntoConstraints = false

        // 关闭 = secondary
        LazyCatTheme.applyButtonStyle(closeBtn, style: .secondary)
        closeBtn.attributedTitle = LazyCatTheme.makeBtnTitle("关闭", style: .secondary)
        closeBtn.keyEquivalent = "\u{1b}"
        closeBtn.target = self
        closeBtn.action = #selector(closeWindow)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let bottomRow = NSStackView(views: [deleteBtn, spacer, completeBtn, closeBtn])
        bottomRow.orientation = .horizontal
        bottomRow.spacing = 8
        bottomRow.distribution = .fill
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(metaLabel)
        content.addSubview(metaBtn)
        content.addSubview(statusChip)
        content.addSubview(textScroll)
        content.addSubview(toolsRow)
        content.addSubview(imagesScroll)
        content.addSubview(bottomRow)

        NSLayoutConstraint.activate([
            // 顶部一行
            metaLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            metaLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusChip.leadingAnchor, constant: -8),

            metaBtn.leadingAnchor.constraint(equalTo: metaLabel.leadingAnchor),
            metaBtn.trailingAnchor.constraint(equalTo: metaLabel.trailingAnchor),
            metaBtn.topAnchor.constraint(equalTo: metaLabel.topAnchor),
            metaBtn.bottomAnchor.constraint(equalTo: metaLabel.bottomAnchor),

            statusChip.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            statusChip.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            statusChip.heightAnchor.constraint(equalToConstant: 18),
            statusChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 36),

            // 正文（顶到底骨干）
            textScroll.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 10),
            textScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            textScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            textScroll.bottomAnchor.constraint(equalTo: toolsRow.topAnchor, constant: -10),

            // 工具行
            toolsRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            toolsRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            toolsRow.bottomAnchor.constraint(equalTo: imagesScroll.topAnchor, constant: -8),
            toolsRow.heightAnchor.constraint(equalToConstant: 26),

            // 图片条（高度 0 或 80）
            imagesScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            imagesScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            imagesScroll.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -10),

            imagesStack.leadingAnchor.constraint(equalTo: imagesScroll.leadingAnchor),
            imagesStack.topAnchor.constraint(equalTo: imagesScroll.topAnchor),
            imagesStack.bottomAnchor.constraint(equalTo: imagesScroll.bottomAnchor),

            // 底部按钮栏
            bottomRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            bottomRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            bottomRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            bottomRow.heightAnchor.constraint(equalToConstant: 32),
        ])
        // 给底部按钮固定宽度，避免 fill 导致拉得过大
        deleteBtn.widthAnchor.constraint(equalToConstant: 86).isActive = true
        completeBtn.widthAnchor.constraint(equalToConstant: 110).isActive = true
        closeBtn.widthAnchor.constraint(equalToConstant: 70).isActive = true
    }

    @objc private func refresh() {
        guard let t = task else { close(); return }

        // meta
        var meta = ["@\(t.person.isEmpty ? "未指定" : t.person)",
                    "创建 " + TaskRowView.smartDate(t.createdAt)]
        if let c = t.completedAt { meta.append("完成 " + TaskRowView.smartDate(c)) }
        if let r = t.remindAt { meta.append("🕒 " + TaskRowView.smartDate(r)) }
        metaLabel.stringValue = meta.joined(separator: "   ·   ")

        // status chip
        let color = NSColor(hex: t.priority.colorHex)
        statusChip.stringValue = "  \(t.priority.label)\(t.completed ? " · 已完成" : "")  "
        statusChip.layer?.backgroundColor = color.cgColor

        // body —— 仅在用户非编辑时重写（否则会把正在输入的字覆盖掉）
        if !userIsEditing {
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            let attr = NSAttributedString(string: t.text, attributes: [
                .font: font,
                .foregroundColor: LazyCatTheme.tx1,        // ★ 暖深棕，不再用 labelColor
            ])
            textView.textStorage?.setAttributedString(attr)
            textView.textColor = LazyCatTheme.tx1
        }

        // fields
        noteField.stringValue = t.note

        // ★ 用 attributedTitle 保持 Style B 颜色（直接用 .title 会覆盖颜色）
        let completeText = t.completed ? "↺ 取消完成" : "✓ 标记完成"
        completeBtn.attributedTitle = LazyCatTheme.makeBtnTitle(completeText, style: .primary)

        priorityBtn.attributedTitle = LazyCatTheme.makeBtnTitle("优先级: \(t.priority.label)", style: .secondary)
        let reminderText: String = {
            if let r = t.remindAt { return "🕒 " + TaskRowView.smartDate(r) }
            return "🕒 设置提醒"
        }()
        reminderBtn.attributedTitle = LazyCatTheme.makeBtnTitle(reminderText, style: .secondary)

        // images
        imagesStack.arrangedSubviews.forEach {
            imagesStack.removeArrangedSubview($0); $0.removeFromSuperview()
        }
        if t.imageFiles.isEmpty {
            imagesHeightC.constant = 0
        } else {
            imagesHeightC.constant = 80
            for (idx, name) in t.imageFiles.enumerated() {
                if let img = Store.shared.loadImage(named: name) {
                    let btn = NSButton(image: img, target: self, action: #selector(openImage(_:)))
                    btn.tag = idx
                    btn.imageScaling = .scaleProportionallyUpOrDown
                    btn.bezelStyle = .shadowlessSquare
                    btn.isBordered = false
                    btn.wantsLayer = true
                    btn.layer?.cornerRadius = 6
                    btn.layer?.masksToBounds = true
                    btn.translatesAutoresizingMaskIntoConstraints = false
                    btn.widthAnchor.constraint(equalToConstant: 72).isActive = true
                    btn.heightAnchor.constraint(equalToConstant: 72).isActive = true
                    imagesStack.addArrangedSubview(btn)
                }
            }
        }
    }

    // MARK: actions

    @objc private func saveNote() {
        Store.shared.updateNote(taskId: taskId, note: noteField.stringValue)
    }

    @objc private func editPerson() {
        guard let t = task else { return }
        PersonEditor.present(anchorWindow: window, current: t.person) { [weak self] name in
            guard let self = self else { return }
            Store.shared.setPerson(taskId: self.taskId, person: name)
        }
    }

    @objc private func changePriority() {
        let menu = NSMenu()
        for p in [Priority.top, .mid, .low, .none] {
            let item = NSMenuItem(title: p.label, action: #selector(pickPriority(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.rawValue
            if p == task?.priority { item.state = .on }
            item.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                NSColor(hex: p.colorHex).setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: priorityBtn.bounds.maxY + 2),
                   in: priorityBtn)
    }
    @objc private func pickPriority(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let p = Priority(rawValue: raw) else { return }
        Store.shared.setPriority(taskId: taskId, priority: p)
    }

    @objc private func changeReminder() {
        ReminderPickerUI.present(current: task?.remindAt, anchor: reminderBtn) { [weak self] newDate in
            guard let self = self else { return }
            Store.shared.setRemindAt(taskId: self.taskId, date: newDate)
        }
    }

    @objc private func openImage(_ sender: NSButton) {
        guard let t = task else { return }
        ImageViewerController.present(imageNames: t.imageFiles)
    }

    @objc private func markComplete() {
        commitTextEditIfNeeded()
        Store.shared.toggleComplete(taskId)
        close()
    }

    @objc private func deleteTask() {
        let alert = NSAlert()
        alert.messageText = "删除该事件？"
        alert.informativeText = "图片也会一并删除，不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            Store.shared.deleteTask(taskId)
            close()
        }
    }

    @objc private func closeWindow() {
        commitTextEditIfNeeded()
        close()
    }

    // MARK: NSTextViewDelegate —— 正文编辑

    func textDidBeginEditing(_ notification: Notification) {
        userIsEditing = true
    }

    func textDidChange(_ notification: Notification) {
        userIsEditing = true
        // 2000 字硬上限
        if textView.string.count > 2000 {
            textView.string = String(textView.string.prefix(2000))
        }
        // 0.6s 无操作就落盘；多次输入会被合并
        saveDebounce?.invalidate()
        saveDebounce = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            self?.commitTextEditIfNeeded()
        }
    }

    func textDidEndEditing(_ notification: Notification) {
        commitTextEditIfNeeded()
        userIsEditing = false
    }

    /// 关窗 / 失焦 / 标记完成 / 删除 都需先落盘
    private func commitTextEditIfNeeded() {
        saveDebounce?.invalidate(); saveDebounce = nil
        let current = textView.string
        guard let t = task else { return }
        if current != t.text {
            Store.shared.updateText(taskId: taskId, text: current)
        }
    }

    static func present(taskId: UUID) {
        // 复用已开的窗口，避免重复
        if let existing = active[taskId] {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = TaskDetailController(taskId: taskId)
        active[taskId] = ctrl
        ctrl.window?.center()
        ctrl.showWindow(nil)
        ctrl.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
