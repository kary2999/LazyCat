import AppKit

/// 三栏布局右侧详情面板：展示当前选中任务的完整信息
final class RightDetailPaneView: NSView {

    var onEdit: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onToggleComplete: ((UUID) -> Void)?
    var onChangePriority: ((UUID, Priority) -> Void)?
    var onPickReminder: ((UUID) -> Void)?
    var onEditPerson: ((UUID) -> Void)?

    private var task: TodoItem?

    private let scroll = NSScrollView()
    private let docContainer = FlippedDocView()
    private let stack = FlippedStack()
    private var docHeight: NSLayoutConstraint!

    // 内容元素
    private let emptyLabel = NSTextField(labelWithString: "选一条任务查看详情")
    private let titleLabel = NSTextField(labelWithString: "")
    private let metaRow = NSStackView()
    private let metaWho = NSTextField(labelWithString: "")
    private let metaTime = NSTextField(labelWithString: "")
    private let priChip = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")
    private let attachLabel = NSTextField(labelWithString: "附件")
    private let attachStack = NSStackView()
    private let propLabel = NSTextField(labelWithString: "属性")
    private let propGrid = NSGridView()
    private let actionRow = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = LazyCatTheme.bgPage.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        build()
        showEmpty()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // 滚动容器
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 26, bottom: 22, right: 26)
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

        emptyLabel.font = LazyCatTheme.body(13)
        emptyLabel.textColor = LazyCatTheme.tx3
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            docContainer.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            docHeight,
            stack.topAnchor.constraint(equalTo: docContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func showEmpty() {
        task = nil
        scroll.isHidden = true
        emptyLabel.isHidden = false
    }

    func show(_ task: TodoItem) {
        self.task = task
        scroll.isHidden = false
        emptyLabel.isHidden = true
        rebuild(task)
    }

    private func rebuild(_ t: TodoItem) {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }

        // 标题（使用第一行作为标题）
        let firstLine = t.text.components(separatedBy: "\n").first ?? t.text
        let title = firstLine.replacingOccurrences(of: "# ", with: "")
        titleLabel.stringValue = title.isEmpty ? "(仅图片)" : title
        titleLabel.font = LazyCatTheme.body(18, weight: .medium)
        titleLabel.textColor = LazyCatTheme.tx1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addRow(titleLabel)
        titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                          constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true

        // meta 行：@人 · 创建时间 · 优先级 chip
        let whoText = t.person.isEmpty ? "未指定" : "@\(t.person)"
        let metaText = "👤 \(whoText)   ·   创建 \(TaskRowView.smartDate(t.createdAt))"
        let meta = NSTextField(labelWithString: metaText)
        meta.font = LazyCatTheme.body(11.5, weight: .medium)
        meta.textColor = LazyCatTheme.tx3
        meta.translatesAutoresizingMaskIntoConstraints = false
        addRow(meta)

        // priority chip + status
        let priWrap = NSStackView()
        priWrap.orientation = .horizontal
        priWrap.spacing = 8
        priWrap.alignment = .centerY
        priWrap.translatesAutoresizingMaskIntoConstraints = false

        let priChip = makeChip(text: t.priority.label, color: LazyCatTheme.priorityColor(t.priority))
        priWrap.addArrangedSubview(priChip)
        let statusChip = makeChip(text: t.completed ? "✓ 已完成" : "⚡ 进行中",
                                  color: t.completed ? LazyCatTheme.green : LazyCatTheme.accent)
        priWrap.addArrangedSubview(statusChip)
        if let r = t.remindAt {
            let timeChip = makeChip(text: "⏰ " + TaskRowView.smartDate(r), color: LazyCatTheme.accent)
            priWrap.addArrangedSubview(timeChip)
        }
        addRow(priWrap)

        // 间隔
        addSpacer(height: 4)

        // 正文（可滚动 + 简单代码高亮）
        let body = makeBody(t.text)
        addRow(body)
        body.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                    constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true

        // 附件
        if !t.imageFiles.isEmpty {
            addSpacer(height: 4)
            let h = makeSectionHeader("附件 · \(t.imageFiles.count) · 点击查看")
            addRow(h)
            let imgs = NSStackView()
            imgs.orientation = .horizontal
            imgs.spacing = 8
            imgs.translatesAutoresizingMaskIntoConstraints = false
            let names = t.imageFiles
            for name in names {
                if let img = Store.shared.loadImage(named: name) {
                    let btn = NSButton(image: img, target: self,
                                       action: #selector(actImageTap(_:)))
                    btn.imageScaling = .scaleProportionallyUpOrDown
                    btn.bezelStyle = .shadowlessSquare
                    btn.isBordered = false
                    btn.focusRingType = .none
                    btn.wantsLayer = true
                    btn.layer?.cornerRadius = 6
                    btn.layer?.masksToBounds = true
                    btn.translatesAutoresizingMaskIntoConstraints = false
                    btn.widthAnchor.constraint(equalToConstant: 64).isActive = true
                    btn.heightAnchor.constraint(equalToConstant: 64).isActive = true
                    btn.toolTip = name
                    btn.identifier = NSUserInterfaceItemIdentifier(name)
                    imgs.addArrangedSubview(btn)
                }
            }
            addRow(imgs)
        }

        // 属性 grid
        addSpacer(height: 6)
        addRow(makeSectionHeader("属性"))
        let prop = makePropGrid(t)
        addRow(prop)
        prop.widthAnchor.constraint(equalTo: stack.widthAnchor,
                                    constant: -(stack.edgeInsets.left + stack.edgeInsets.right)).isActive = true

        // 操作按钮
        addSpacer(height: 12)
        let toggleBtn = NSButton(title: "", target: self, action: #selector(actToggle))
        LazyCatTheme.applyButtonStyle(toggleBtn, style: .primary)
        toggleBtn.attributedTitle = LazyCatTheme.makeBtnTitle(t.completed ? "↺ 重开" : "✓ 标记完成", style: .primary)
        toggleBtn.translatesAutoresizingMaskIntoConstraints = false

        let editBtn = NSButton(title: "", target: self, action: #selector(actEdit))
        LazyCatTheme.applyButtonStyle(editBtn, style: .secondary)
        editBtn.attributedTitle = LazyCatTheme.makeBtnTitle("📝 编辑", style: .secondary)
        editBtn.translatesAutoresizingMaskIntoConstraints = false

        let delBtn = NSButton(title: "", target: self, action: #selector(actDelete))
        LazyCatTheme.applyButtonStyle(delBtn, style: .dangerGhost)
        delBtn.attributedTitle = LazyCatTheme.makeBtnTitle("🗑 删除", style: .dangerGhost)
        delBtn.translatesAutoresizingMaskIntoConstraints = false

        let actions = NSStackView(views: [toggleBtn, editBtn, delBtn])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.alignment = .centerY
        actions.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            toggleBtn.heightAnchor.constraint(equalToConstant: 30),
            toggleBtn.widthAnchor.constraint(equalToConstant: 130),
            editBtn.heightAnchor.constraint(equalToConstant: 30),
            editBtn.widthAnchor.constraint(equalToConstant: 90),
            delBtn.heightAnchor.constraint(equalToConstant: 30),
            delBtn.widthAnchor.constraint(equalToConstant: 90),
        ])
        addRow(actions)

        // 重算 docHeight
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var h: CGFloat = self.stack.edgeInsets.top + self.stack.edgeInsets.bottom
            for v in self.stack.arrangedSubviews {
                h += v.fittingSize.height + self.stack.spacing
            }
            self.docHeight.constant = max(h, 100)
        }
    }

    private func addRow(_ v: NSView) {
        v.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(v)
    }
    private func addSpacer(height: CGFloat) {
        let s = NSView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.heightAnchor.constraint(equalToConstant: height).isActive = true
        stack.addArrangedSubview(s)
    }

    private func makeChip(text: String, color: NSColor) -> NSView {
        // 用单个 NSTextField 自带 padding（attributed string 前后空格）+ wantsLayer 着色
        let chip = NSTextField(labelWithString: "")
        chip.attributedStringValue = NSAttributedString(string: "  \(text)  ", attributes: [
            .foregroundColor: NSColor.white,
            .font: LazyCatTheme.body(11, weight: .medium),
        ])
        chip.alignment = .center
        chip.isBezeled = false
        chip.drawsBackground = false
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 4
        chip.layer?.backgroundColor = color.cgColor
        chip.layer?.masksToBounds = true
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return chip
    }

    private func makeSectionHeader(_ s: String) -> NSView {
        let lbl = NSTextField(labelWithString: s.uppercased())
        lbl.font = LazyCatTheme.body(10.5, weight: .medium)
        lbl.textColor = LazyCatTheme.tx3
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }

    /// 把正文按行解析：
    ///   - `- [ ] xxx` / `- [x] xxx`  → 渲染为可点击 checkbox + 文字（点击 toggle 并保存）
    ///   - 其它行                      → 走普通 wrapping label
    /// 这样勾子列表能直接被打钩，源文 markdown 同步更新
    private func makeBody(_ raw: String) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        container.translatesAutoresizingMaskIntoConstraints = false

        let lines = raw.components(separatedBy: "\n")
        var plainBuf: [String] = []

        func flushPlain() {
            guard !plainBuf.isEmpty else { return }
            let s = plainBuf.joined(separator: "\n")
            let lbl = NSTextField(wrappingLabelWithString: s)
            lbl.font = LazyCatTheme.body(13, weight: .regular)
            lbl.textColor = LazyCatTheme.tx1
            lbl.lineBreakMode = .byWordWrapping
            lbl.maximumNumberOfLines = 0
            lbl.preferredMaxLayoutWidth = 320
            lbl.translatesAutoresizingMaskIntoConstraints = false
            container.addArrangedSubview(lbl)
            plainBuf.removeAll()
        }

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 匹配 - [ ] / - [x] / * [ ] / * [X] / 1. [ ] 之类
            // 简化只识别：开头空白 + (- 或 *) + 空格 + [ x|X|空格 ] + 空格 + 内容
            if let m = checklistMatch(trimmed) {
                flushPlain()
                let row = makeChecklistRow(checked: m.checked, text: m.text, lineIndex: idx)
                container.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
            } else {
                plainBuf.append(line)
            }
        }
        flushPlain()
        return container
    }

    private struct ChecklistMatch { let checked: Bool; let text: String }
    private func checklistMatch(_ s: String) -> ChecklistMatch? {
        // - [ ] xxx  /  - [x] xxx  /  * [ ] xxx
        guard s.count >= 5 else { return nil }
        let prefixes = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "* [X] "]
        for p in prefixes {
            if s.hasPrefix(p) {
                let checked = p.contains("[x]") || p.contains("[X]")
                let text = String(s.dropFirst(p.count))
                return ChecklistMatch(checked: checked, text: text)
            }
        }
        return nil
    }

    private func makeChecklistRow(checked: Bool, text: String, lineIndex: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let cb = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleChecklist(_:)))
        cb.state = checked ? .on : .off
        cb.tag = lineIndex
        cb.focusRingType = .none
        cb.translatesAutoresizingMaskIntoConstraints = false

        let lbl = NSTextField(wrappingLabelWithString: text)
        lbl.font = LazyCatTheme.body(13, weight: .regular)
        lbl.textColor = checked ? LazyCatTheme.tx3 : LazyCatTheme.tx1
        if checked {
            // 删除线
            let attr = NSMutableAttributedString(string: text, attributes: [
                .font: LazyCatTheme.body(13, weight: .regular),
                .foregroundColor: LazyCatTheme.tx3,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: LazyCatTheme.tx3,
            ])
            lbl.attributedStringValue = attr
        }
        lbl.lineBreakMode = .byWordWrapping
        lbl.maximumNumberOfLines = 0
        lbl.preferredMaxLayoutWidth = 290
        lbl.translatesAutoresizingMaskIntoConstraints = false

        row.addArrangedSubview(cb)
        row.addArrangedSubview(lbl)
        lbl.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor).isActive = true
        return row
    }

    @objc private func toggleChecklist(_ sender: NSButton) {
        guard let t = task else { return }
        let lineIdx = sender.tag
        var lines = t.text.components(separatedBy: "\n")
        guard lineIdx >= 0 && lineIdx < lines.count else { return }
        let original = lines[lineIdx]
        let trimmedLeading = original.prefix(while: { $0 == " " || $0 == "\t" })
        let body = original.dropFirst(trimmedLeading.count)
        let newBody: String
        if body.hasPrefix("- [ ] ") {
            newBody = "- [x] " + body.dropFirst(6)
        } else if body.hasPrefix("- [x] ") || body.hasPrefix("- [X] ") {
            newBody = "- [ ] " + body.dropFirst(6)
        } else if body.hasPrefix("* [ ] ") {
            newBody = "* [x] " + body.dropFirst(6)
        } else if body.hasPrefix("* [x] ") || body.hasPrefix("* [X] ") {
            newBody = "* [ ] " + body.dropFirst(6)
        } else {
            return
        }
        lines[lineIdx] = String(trimmedLeading) + newBody
        let updated = lines.joined(separator: "\n")
        Store.shared.updateText(taskId: t.id, text: updated)
    }

    private func makePropGrid(_ t: TodoItem) -> NSView {
        // 简单 grid: 2 列，每行 [label] [value]
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4

        let pairs: [(String, String, NSColor)] = [
            ("人员",   t.person.isEmpty ? "未指定" : "@\(t.person)", LazyCatTheme.tx1),
            ("优先级", t.priority.label, LazyCatTheme.priorityColor(t.priority)),
            ("提醒",   t.remindAt.map { TaskRowView.smartDate($0) } ?? "未设置",
                       t.remindAt != nil ? LazyCatTheme.accent : LazyCatTheme.tx3),
            ("状态",   t.completed ? "已完成" : "进行中", LazyCatTheme.tx1),
            ("创建于", TaskRowView.smartDate(t.createdAt), LazyCatTheme.tx2),
        ]
        for (k, v, c) in pairs {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 12
            let kL = NSTextField(labelWithString: k)
            kL.font = LazyCatTheme.body(12, weight: .medium)
            kL.textColor = LazyCatTheme.tx3
            kL.translatesAutoresizingMaskIntoConstraints = false
            kL.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let vL = NSTextField(labelWithString: v)
            vL.font = LazyCatTheme.body(12, weight: .medium)
            vL.textColor = c
            vL.translatesAutoresizingMaskIntoConstraints = false
            row.addArrangedSubview(kL)
            row.addArrangedSubview(vL)
            container.addArrangedSubview(row)
        }
        return container
    }

    @objc private func actImageTap(_ sender: NSButton) {
        guard let t = task else { return }
        // 优先用 sender 的 identifier 定位；fallback 全部图
        if let name = sender.identifier?.rawValue,
           let idx = t.imageFiles.firstIndex(of: name) {
            // 把这张图放到第一位，其它顺序保留
            var ordered = t.imageFiles
            ordered.swapAt(0, idx)
            ImageViewerController.present(imageNames: ordered)
        } else {
            ImageViewerController.present(imageNames: t.imageFiles)
        }
    }

    @objc private func actEdit() {
        guard let t = task else { return }
        onEdit?(t.id)
    }
    @objc private func actToggle() {
        guard let t = task else { return }
        onToggleComplete?(t.id)
    }
    @objc private func actDelete() {
        guard let t = task else { return }
        onDelete?(t.id)
    }
}
