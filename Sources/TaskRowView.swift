import AppKit

// MARK: - 圆形复选框（需要双击才提交 "完成"）

final class CircularCheckBox: NSControl {
    var checked: Bool = false { didSet { needsDisplay = true } }
    var tintHex: String = "#C7C7CC" { didSet { needsDisplay = true } }
    /// 双击时触发
    var onCommit: (() -> Void)?
    /// 单击时触发（用来闪烁提示 "双击完成"）
    var onSingleHint: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(ovalIn: rect)
        let color = NSColor(hex: tintHex)
        if checked {
            color.setFill(); path.fill()
            // 白色对勾
            NSColor.white.setStroke()
            let check = NSBezierPath()
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            let x = rect.minX, y = rect.minY, w = rect.width, h = rect.height
            check.move(to: NSPoint(x: x + w * 0.26, y: y + h * 0.52))
            check.line(to: NSPoint(x: x + w * 0.44, y: y + h * 0.34))
            check.line(to: NSPoint(x: x + w * 0.76, y: y + h * 0.68))
            check.stroke()
        } else {
            color.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onCommit?()
        } else {
            onSingleHint?()
        }
    }
}

// MARK: - Section Header（暂未使用，保留）

final class SectionHeaderView: NSTableCellView {
    init(title: String, count: Int) {
        super.init(frame: .zero)
        wantsLayer = true
        let label = NSTextField(labelWithString: "\(title)  ·  \(count) 条")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Task Row（滴答清单风）

/// ● 标题                            🕒提醒时间  📎图片
/// @人  ·  时间  ·  备注                          [P1] [×]
final class TaskRowView: NSTableCellView {
    var onToggle: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSaveNote: ((UUID, String) -> Void)?
    var onChangePriority: ((UUID, Priority) -> Void)?
    var onEditReminder: ((UUID) -> Void)?
    var onViewImages: (([String]) -> Void)?
    var onOpenDetail: ((UUID) -> Void)?
    var onEditPerson: ((UUID) -> Void)?

    private let task: TodoItem
    private let check = CircularCheckBox()
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let reminderLabel = NSTextField(labelWithString: "")
    private let priorityBtn = NSButton()
    private let imageBtn = NSButton()
    private let delButton = NSButton(title: "×", target: nil, action: nil)
    private let hint = NSTextField(labelWithString: "双击完成")
    private let bottomLine = NSBox()

    init(task: TodoItem) {
        self.task = task
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true

        // 圆形复选框（双击完成）
        check.checked = task.completed
        check.tintHex = task.priority == .none ? "#9AA0A6" : task.priority.colorHex
        check.onCommit = { [weak self] in
            guard let self = self else { return }
            self.onToggle?(self.task.id)
        }
        check.onSingleHint = { [weak self] in self?.flashHint() }
        check.translatesAutoresizingMaskIntoConstraints = false

        // 标题
        let titleText = task.text.isEmpty ? "(仅图片)" : task.text
        if task.completed {
            titleLabel.attributedStringValue = NSAttributedString(
                string: titleText,
                attributes: [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 13.5),
                ])
        } else {
            titleLabel.stringValue = titleText
            titleLabel.font = LazyCatTheme.body(13.5, weight: .medium)
            titleLabel.textColor = LazyCatTheme.tx1
        }
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // meta —— 未填人名时，@未指定 部分用橘色警示，提示点击补填
        var tail: [String] = [Self.smartDate(task.createdAt)]
        if !task.note.isEmpty { tail.append("📝 \(task.note)") }
        if !task.imageFiles.isEmpty { tail.append("📎 \(task.imageFiles.count)") }
        if task.completed, let c = task.completedAt {
            tail.append("✓ " + Self.smartDate(c))
        }
        let personStr = task.person.isEmpty ? "@未指定（点击补填）" : "@\(task.person)"
        let full = personStr + "  ·  " + tail.joined(separator: "  ·  ")
        let attr = NSMutableAttributedString(string: full, attributes: [
            .font: LazyCatTheme.body(11),
            .foregroundColor: LazyCatTheme.tx3,
        ])
        if task.person.isEmpty {
            let range = (full as NSString).range(of: personStr)
            attr.addAttributes([
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)
        }
        metaLabel.attributedStringValue = attr
        metaLabel.maximumNumberOfLines = 1
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.translatesAutoresizingMaskIntoConstraints = false

        // 大号"滞留天数 / 完成耗时"徽章 —— 替代原来的提醒小标签
        // 未完成：⏳ N 天    （1-2天灰 / 3-6天橙 / 7+天红）
        // 已完成：✓ 当天完成 / ✓ N 天后完成 （绿色）
        configureAgingBadge()
        reminderLabel.translatesAutoresizingMaskIntoConstraints = false

        // 提示 "双击完成"
        hint.stringValue = "双击完成"
        hint.font = .systemFont(ofSize: 10, weight: .medium)
        hint.textColor = .systemOrange
        hint.alphaValue = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        // 优先级按钮
        configurePriorityButton()
        priorityBtn.translatesAutoresizingMaskIntoConstraints = false

        // 图片快览
        if !task.imageFiles.isEmpty,
           let img = Store.shared.loadImage(named: task.imageFiles[0]) {
            imageBtn.image = img
            imageBtn.imagePosition = .imageOnly
            imageBtn.imageScaling = .scaleProportionallyUpOrDown
            imageBtn.bezelStyle = .shadowlessSquare
            imageBtn.isBordered = false
            imageBtn.wantsLayer = true
            imageBtn.layer?.cornerRadius = 5
            imageBtn.layer?.masksToBounds = true
            imageBtn.target = self
            imageBtn.action = #selector(viewImages)
            imageBtn.toolTip = "点击用系统预览打开"
        } else {
            imageBtn.isHidden = true
        }
        imageBtn.translatesAutoresizingMaskIntoConstraints = false

        // 删除
        delButton.bezelStyle = .inline
        delButton.isBordered = false
        delButton.font = .systemFont(ofSize: 18, weight: .light)
        delButton.contentTintColor = .tertiaryLabelColor
        delButton.target = self
        delButton.action = #selector(deleteTapped)
        delButton.toolTip = "删除"
        delButton.translatesAutoresizingMaskIntoConstraints = false

        bottomLine.boxType = .custom
        bottomLine.borderWidth = 0
        bottomLine.fillColor = NSColor.separatorColor.withAlphaComponent(0.4)
        bottomLine.translatesAutoresizingMaskIntoConstraints = false

        addSubview(check)
        addSubview(titleLabel)
        addSubview(reminderLabel)
        addSubview(hint)
        addSubview(metaLabel)
        addSubview(priorityBtn)
        addSubview(imageBtn)
        addSubview(delButton)
        addSubview(bottomLine)

        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            check.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            check.widthAnchor.constraint(equalToConstant: 22),
            check.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: reminderLabel.leadingAnchor, constant: -8),

            reminderLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            reminderLabel.trailingAnchor.constraint(equalTo: imageBtn.leadingAnchor, constant: -10),
            reminderLabel.heightAnchor.constraint(equalToConstant: 22),

            hint.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            hint.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: priorityBtn.leadingAnchor, constant: -8),

            imageBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageBtn.trailingAnchor.constraint(equalTo: priorityBtn.leadingAnchor, constant: -10),
            imageBtn.widthAnchor.constraint(equalToConstant: 36),
            imageBtn.heightAnchor.constraint(equalToConstant: 36),

            priorityBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
            priorityBtn.trailingAnchor.constraint(equalTo: delButton.leadingAnchor, constant: -6),
            priorityBtn.widthAnchor.constraint(equalToConstant: 46),
            priorityBtn.heightAnchor.constraint(equalToConstant: 22),

            delButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            delButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            delButton.widthAnchor.constraint(equalToConstant: 22),
            delButton.heightAnchor.constraint(equalToConstant: 22),

            bottomLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottomLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            bottomLine.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 0.5),
        ])

        // 添加 hover 高亮
        addHoverArea()
    }

    private func addHoverArea() {
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
    }
    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// 点击文字/空白区域 → 打开详情（不拦截复选框/优先级/图片/删除按钮）
    /// 额外：如果点到 metaLabel 且人名为空，弹出补填对话框
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let interactive: [NSView] = [check, priorityBtn, imageBtn, delButton]
        for v in interactive where !v.isHidden && v.frame.contains(p) {
            super.mouseDown(with: event)
            return
        }
        if task.person.isEmpty && metaLabel.frame.contains(p) {
            onEditPerson?(task.id)
            return
        }
        onOpenDetail?(task.id)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func flashHint() {
        hint.alphaValue = 1
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 1.0
            hint.animator().alphaValue = 0
        })
    }

    /// 把 reminderLabel 当作一个大号彩色胶囊徽章使用
    private func configureAgingBadge() {
        reminderLabel.wantsLayer = true
        reminderLabel.layer?.cornerRadius = 10
        reminderLabel.layer?.masksToBounds = true
        reminderLabel.alignment = .center
        reminderLabel.isBezeled = false
        reminderLabel.drawsBackground = false
        reminderLabel.isEditable = false
        reminderLabel.isSelectable = false

        let cal = Calendar.current
        let fromStart = cal.startOfDay(for: task.createdAt)

        if task.completed, let done = task.completedAt {
            let toStart = cal.startOfDay(for: done)
            let days = cal.dateComponents([.day], from: fromStart, to: toStart).day ?? 0
            let text = days <= 0 ? "  ✓ 当天完成  " : "  ✓ \(days) 天后完成  "
            reminderLabel.stringValue = text
            reminderLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            reminderLabel.textColor = NSColor.white
            let green = NSColor(srgbRed: 0.20, green: 0.63, blue: 0.40, alpha: 1.0)
            reminderLabel.layer?.backgroundColor = green.cgColor
            return
        }

        // 未完成：计算到今天的天数
        let now = cal.startOfDay(for: Date())
        let days = cal.dateComponents([.day], from: fromStart, to: now).day ?? 0
        if days < 1 {
            // 当天建的，不显示胶囊
            reminderLabel.stringValue = ""
            reminderLabel.layer?.backgroundColor = NSColor.clear.cgColor
            return
        }

        let bg: NSColor
        if days >= 7 {
            bg = NSColor(srgbRed: 0.87, green: 0.25, blue: 0.22, alpha: 1.0)   // 红
        } else if days >= 3 {
            bg = NSColor(srgbRed: 0.94, green: 0.60, blue: 0.18, alpha: 1.0)   // 橙
        } else {
            bg = NSColor(srgbRed: 0.47, green: 0.47, blue: 0.50, alpha: 1.0)   // 灰
        }
        reminderLabel.stringValue = "  ⏳ \(days) 天未完成  "
        reminderLabel.font = .systemFont(ofSize: 12, weight: .bold)
        reminderLabel.textColor = .white
        reminderLabel.layer?.backgroundColor = bg.cgColor
    }

    private func configurePriorityButton() {
        let p = task.priority
        priorityBtn.title = p.label
        priorityBtn.font = .systemFont(ofSize: 11, weight: .semibold)
        priorityBtn.bezelStyle = .inline
        priorityBtn.isBordered = false
        priorityBtn.wantsLayer = true
        priorityBtn.layer?.cornerRadius = 10
        priorityBtn.layer?.backgroundColor = NSColor(hex: p.colorHex).withAlphaComponent(0.18).cgColor
        priorityBtn.contentTintColor = NSColor(hex: p.colorHex)
        priorityBtn.target = self
        priorityBtn.action = #selector(showPriorityMenu)
        priorityBtn.toolTip = "点击修改优先级"
    }

    @objc private func deleteTapped() {
        let alert = NSAlert()
        alert.messageText = "删除该事件？"
        alert.informativeText = "图片也会一并删除，不可撤销。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            onDelete?(task.id)
        }
    }

    @objc private func showPriorityMenu() {
        let menu = NSMenu()
        for p in [Priority.top, .mid, .low, .none] {
            let item = NSMenuItem(title: p.label, action: #selector(pickPriority(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.rawValue
            if p == task.priority { item.state = .on }
            item.image = NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
                NSColor(hex: p.colorHex).setFill()
                NSBezierPath(ovalIn: rect).fill()
                return true
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let editPerson = NSMenuItem(title: task.person.isEmpty ? "补填 @人名…" : "修改 @\(task.person)…",
                                    action: #selector(editPersonTapped),
                                    keyEquivalent: "")
        editPerson.target = self
        menu.addItem(editPerson)

        let remind = NSMenuItem(title: task.remindAt == nil ? "设置提醒…" : "修改提醒…",
                                action: #selector(editRemind),
                                keyEquivalent: "")
        remind.target = self
        menu.addItem(remind)
        if task.remindAt != nil {
            let clear = NSMenuItem(title: "取消提醒",
                                   action: #selector(clearRemind),
                                   keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }
        let origin = NSPoint(x: 0, y: priorityBtn.bounds.maxY + 2)
        menu.popUp(positioning: nil, at: origin, in: priorityBtn)
    }

    @objc private func pickPriority(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let p = Priority(rawValue: raw) else { return }
        onChangePriority?(task.id, p)
    }

    @objc private func editPersonTapped() { onEditPerson?(task.id) }
    @objc private func editRemind() { onEditReminder?(task.id) }
    @objc private func clearRemind() { Store.shared.setRemindAt(taskId: task.id, date: nil) }
    @objc private func viewImages() { onViewImages?(task.imageFiles) }
}

extension TaskRowView {
    /// 今天 HH:mm / 昨天 HH:mm / MM-dd HH:mm
    static func smartDate(_ d: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: todayStart)!
        let dStart = cal.startOfDay(for: d)
        let hm = DateFormatter(); hm.dateFormat = "HH:mm"
        let md = DateFormatter(); md.dateFormat = "MM-dd HH:mm"
        if dStart == todayStart { return "今天 " + hm.string(from: d) }
        if dStart == yesterday  { return "昨天 " + hm.string(from: d) }
        return md.string(from: d)
    }
}

// MARK: - Hex color

extension NSColor {
    convenience init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self.init(white: 0.5, alpha: 1); return
        }
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
