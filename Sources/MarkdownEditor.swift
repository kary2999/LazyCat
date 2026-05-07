import AppKit

/// Markdown 长文 / 多图 任务编辑器（modal sheet）
///
/// 布局：
///   ┌──────────────────────────────────────────────────┐
///   │ 标题 + 👤选人 + 优先级 dot + 🕒时间               │
///   ├──────────────────────────────────────────────────┤
///   │ B I S | H ≡ ¹⁾ " | {} 🔗 🖼 | 仅编辑[+预览]仅预览 │
///   ├──────────────────────────────────────────────────┤
///   │ Editor (text)         │  Preview (rendered)      │
///   ├──────────────────────────────────────────────────┤
///   │ 🖼 图片附件 (拖拽 / 粘贴 / Cmd+V)                 │
///   ├──────────────────────────────────────────────────┤
///   │ 312 / 2000 字   [取消] [存草稿] [+ 添加]          │
///   └──────────────────────────────────────────────────┘
///
/// 复制 / 粘贴：
///   - 键盘 Cmd+C / Cmd+V / Cmd+X / Cmd+A —— NSTextView 默认支持
///   - 鼠标右键 —— NSTextView 默认 contextMenu
///   - 粘贴图片 —— PasteAwareTextView 拦 readSelection(from:type:) → 加入附件区
///   - 拖拽 —— editor 接受 .fileURL / .png / .tiff，编辑器 / 附件区任一都行
///   - 工具条 B/I/H 等 —— 修改 selectedRange 周围的 markdown 语法
final class MarkdownEditorViewController: NSViewController {

    /// 提交时返回的数据
    struct Result {
        var person: String
        var text: String
        var imageFiles: [String]
        var priority: Priority
        var remindAt: Date?
    }

    var onSave: ((Result) -> Void)?

    // 元信息
    private let titleField = NSTextField()
    private let personCombo = NSComboBox()
    private let priDots = PriorityDotPicker()
    private let timeBtn = NSButton(title: "🕒", target: nil, action: nil)
    private var pendingRemindAt: Date?

    // 工具栏
    private let toolbar = NSStackView()
    private let viewToggle = ViewModeToggle()

    // 编辑 + 预览
    private let editor: MarkdownTextView = {
        // ★ NSTextView 必须用 init(frame:textContainer:) 才能正常显示
        let tc = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        let lm = NSLayoutManager()
        lm.addTextContainer(tc)
        let ts = NSTextStorage()
        ts.addLayoutManager(lm)
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                                  textContainer: tc)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        return tv
    }()
    private let editorScroll = NSScrollView()
    private let preview = MarkdownPreviewView()
    private let split = NSStackView()

    // 附件
    private let attachments = ImageAttachmentsView()
    private var pendingImages: [NSImage] = []

    // 底部
    private let charCountLabel = NSTextField(labelWithString: "0 / 5000 字")
    private let cancelBtn = NSButton(title: "取消", target: nil, action: nil)
    private let draftBtn  = NSButton(title: "存草稿", target: nil, action: nil)
    private let submitBtn = NSButton(title: "＋ 添加任务", target: nil, action: nil)

    private let charLimit = 5000
    private var personSuggestions: [String] = []

    // 自动草稿（防意外退出丢内容）
    private static let draftKey = "MyTodo.markdownDraft"
    private var draftSaveTimer: Timer?

    func preset(person: String, priority: Priority) {
        _ = view   // 触发 loadView（兼容 macOS 12+，loadViewIfNeeded 只 macOS 14+）
        personCombo.stringValue = person
        priDots.priority = priority
    }

    /// 进入编辑器时检查是否有草稿，问用户要不要恢复
    private func checkAndRestoreDraft() {
        guard let payload = UserDefaults.standard.dictionary(forKey: Self.draftKey),
              let title = payload["title"] as? String,
              let person = payload["person"] as? String,
              let text = payload["text"] as? String,
              !(title.isEmpty && text.isEmpty)   // 空草稿不打扰
        else { return }

        let priority = (payload["priority"] as? Int).flatMap { Priority(rawValue: $0) } ?? .none
        let savedAt = payload["savedAt"] as? String ?? "之前"

        let alert = NSAlert()
        alert.messageText = "发现草稿（\(savedAt)）"
        let preview: String = {
            if !title.isEmpty { return title }
            return String(text.prefix(40)) + (text.count > 40 ? "…" : "")
        }()
        alert.informativeText = "「\(preview)」\n\n要恢复继续编辑吗？"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "舍弃")
        alert.addButton(withTitle: "稍后再说")
        let resp = alert.runModal()
        switch resp {
        case .alertFirstButtonReturn:   // 恢复
            titleField.stringValue = title
            personCombo.stringValue = person
            editor.string = text
            priDots.priority = priority
            updateAfterEdit()
        case .alertSecondButtonReturn:  // 舍弃
            UserDefaults.standard.removeObject(forKey: Self.draftKey)
        default: break  // 稍后：保持草稿不变
        }
    }

    /// 写当前内容到草稿（覆盖式，单草稿）
    private func writeDraft(silent: Bool) {
        let title = titleField.stringValue
        let person = personCombo.stringValue
        let text = editor.string
        // 全空就清掉草稿
        if title.isEmpty && text.isEmpty && pendingImages.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.draftKey)
            return
        }
        let df = DateFormatter()
        df.dateFormat = "M/d HH:mm"
        df.locale = Locale(identifier: "zh_CN")
        let payload: [String: Any] = [
            "title": title,
            "person": person,
            "text": text,
            "priority": priDots.priority.rawValue,
            "savedAt": df.string(from: Date()),
        ]
        UserDefaults.standard.set(payload, forKey: Self.draftKey)
        if !silent {
            let alert = NSAlert()
            alert.messageText = "草稿已保存"
            alert.informativeText = "下次打开「✍️ 长文」会问你要不要恢复。"
            alert.runModal()
        }
    }

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 660))
        v.appearance = NSAppearance(named: .aqua)
        v.wantsLayer = true
        v.layer?.backgroundColor = LazyCatTheme.bg.cgColor
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildMetaRow()
        buildToolbar()
        buildEditorSplit()
        buildAttachments()
        buildFooter()
        layoutAll()
        wireCallbacks()
        updateCharCount()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // sheet 第一次出现时检查草稿（preset 之后跑，所以恢复会覆盖 preset 值）
        checkAndRestoreDraft()
        // 启动自动草稿计时器：每 3 秒静默存一次（如果有内容）
        draftSaveTimer?.invalidate()
        draftSaveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.writeDraft(silent: true)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        draftSaveTimer?.invalidate()
        draftSaveTimer = nil
    }

    private func buildMetaRow() {
        // 标题
        titleField.placeholderString = "任务标题（必填）"
        titleField.font = LazyCatTheme.body(15, weight: .heavy)
        titleField.bezelStyle = .roundedBezel
        titleField.isBezeled = true
        titleField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleField)

        // 人
        personCombo.placeholderString = "👤 选人"
        personCombo.font = LazyCatTheme.body(13)
        personCombo.usesDataSource = true
        personCombo.dataSource = self
        personCombo.delegate = self
        personCombo.completes = false
        personCombo.numberOfVisibleItems = 8
        personCombo.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(personCombo)

        // 优先级
        priDots.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(priDots)

        // 时间
        timeBtn.bezelStyle = .rounded
        timeBtn.isBordered = false
        timeBtn.wantsLayer = true
        timeBtn.layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
        timeBtn.layer?.cornerRadius = 8
        timeBtn.target = self
        timeBtn.action = #selector(pickReminder)
        timeBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timeBtn)
        updateTimeBtnTitle()
    }

    private func buildToolbar() {
        toolbar.orientation = .horizontal
        toolbar.spacing = 2
        toolbar.alignment = .centerY
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.white.cgColor
        toolbar.layer?.cornerRadius = LazyCatTheme.cornerSm
        toolbar.layer?.borderWidth = 1
        toolbar.layer?.borderColor = LazyCatTheme.border.cgColor
        toolbar.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        view.addSubview(toolbar)

        let bold = mdToolBtn("B", action: #selector(mdBold), tooltip: "粗体  ⌘B")
        bold.font = .systemFont(ofSize: 13, weight: .heavy)
        let italic = mdToolBtn("I", action: #selector(mdItalic), tooltip: "斜体  ⌘I")
        italic.font = NSFontManager.shared.font(withFamily: "Helvetica", traits: .italicFontMask, weight: 5, size: 13) ?? .systemFont(ofSize: 13)
        let strike = mdToolBtn("S", action: #selector(mdStrike), tooltip: "删除线  ⌘⇧X")
        let h = mdToolBtn("H", action: #selector(mdHeading), tooltip: "标题")
        let ul = mdToolBtn("≡", action: #selector(mdUL), tooltip: "无序列表")
        let ol = mdToolBtn("¹⁾", action: #selector(mdOL), tooltip: "有序列表")
        let quo = mdToolBtn("\"", action: #selector(mdQuote), tooltip: "引用")
        let code = mdToolBtn("{}", action: #selector(mdCode), tooltip: "代码  ⌘⇧C")
        let link = mdToolBtn("🔗", action: #selector(mdLink), tooltip: "链接")
        let img = mdToolBtn("🖼", action: #selector(mdImage), tooltip: "插入图片")

        for v in [bold, italic, strike] { toolbar.addArrangedSubview(v) }
        toolbar.addArrangedSubview(makeToolbarSep())
        for v in [h, ul, ol, quo] { toolbar.addArrangedSubview(v) }
        toolbar.addArrangedSubview(makeToolbarSep())
        for v in [code, link, img] { toolbar.addArrangedSubview(v) }

        // 撑满后右边放 viewToggle
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolbar.addArrangedSubview(spacer)

        viewToggle.translatesAutoresizingMaskIntoConstraints = false
        viewToggle.onChange = { [weak self] mode in self?.applyViewMode(mode) }
        toolbar.addArrangedSubview(viewToggle)
    }

    private func mdToolBtn(_ title: String, action: Selector, tooltip: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 5
        b.font = .systemFont(ofSize: 13, weight: .semibold)
        b.toolTip = tooltip
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }
    private func makeToolbarSep() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = LazyCatTheme.border.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return v
    }

    private func buildEditorSplit() {
        // editor
        editor.editorOwner = self
        editor.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textColor = LazyCatTheme.textPrimary
        editor.insertionPointColor = LazyCatTheme.textPrimary
        editor.isEditable = true
        editor.isSelectable = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.importsGraphics = false   // 我们自己处理图片
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.usesFindBar = true
        editor.delegate = self

        editorScroll.documentView = editor
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .noBorder
        editorScroll.drawsBackground = true
        editorScroll.backgroundColor = NSColor.white
        editorScroll.wantsLayer = true
        editorScroll.layer?.cornerRadius = LazyCatTheme.cornerSm
        editorScroll.layer?.borderColor = LazyCatTheme.border.cgColor
        editorScroll.layer?.borderWidth = 1
        editorScroll.translatesAutoresizingMaskIntoConstraints = false

        // preview
        preview.translatesAutoresizingMaskIntoConstraints = false

        // 拼成 split
        split.orientation = .horizontal
        split.distribution = .fillEqually
        split.spacing = 8
        split.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(editorScroll)
        split.addArrangedSubview(preview)
        view.addSubview(split)
    }

    private func buildAttachments() {
        attachments.translatesAutoresizingMaskIntoConstraints = false
        attachments.onPick = { [weak self] in self?.pickImageFromDisk() }
        attachments.onRemove = { [weak self] idx in
            self?.removeAttachment(at: idx)
        }
        attachments.onDropImages = { [weak self] imgs in
            self?.addImages(imgs)
        }
        view.addSubview(attachments)
    }

    private func buildFooter() {
        charCountLabel.font = LazyCatTheme.body(11, weight: .heavy)
        charCountLabel.textColor = LazyCatTheme.textTer
        charCountLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(charCountLabel)

        for b in [cancelBtn, draftBtn, submitBtn] {
            b.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(b)
        }
        // ★ 严格 4 种按钮 token：cancel/draft = secondary，submit = primary
        LazyCatTheme.applyButtonStyle(cancelBtn, style: .secondary)
        cancelBtn.attributedTitle = LazyCatTheme.makeBtnTitle("取消", style: .secondary)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelAndClose)
        cancelBtn.keyEquivalent = "\u{1B}"   // ESC

        LazyCatTheme.applyButtonStyle(draftBtn, style: .secondary)
        draftBtn.attributedTitle = LazyCatTheme.makeBtnTitle("存草稿", style: .secondary)
        draftBtn.target = self
        draftBtn.action = #selector(saveDraft)

        LazyCatTheme.applyButtonStyle(submitBtn, style: .primary)
        submitBtn.attributedTitle = LazyCatTheme.makeBtnTitle("＋ 添加任务  ⌘↵", style: .primary)
        submitBtn.target = self
        submitBtn.action = #selector(submitTask)
        submitBtn.keyEquivalent = "\r"
        submitBtn.keyEquivalentModifierMask = [.command]
    }

    private func layoutAll() {
        let pad: CGFloat = 16
        NSLayoutConstraint.activate([
            // 第一行：标题 + 人 + 优先级 + 时间
            titleField.topAnchor.constraint(equalTo: view.topAnchor, constant: pad),
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            titleField.heightAnchor.constraint(equalToConstant: 30),

            personCombo.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            personCombo.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 10),
            personCombo.widthAnchor.constraint(equalToConstant: 130),
            personCombo.heightAnchor.constraint(equalToConstant: 30),

            priDots.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            priDots.leadingAnchor.constraint(equalTo: personCombo.trailingAnchor, constant: 8),
            priDots.widthAnchor.constraint(equalToConstant: 96),
            priDots.heightAnchor.constraint(equalToConstant: 30),

            timeBtn.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            timeBtn.leadingAnchor.constraint(equalTo: priDots.trailingAnchor, constant: 8),
            timeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            timeBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            timeBtn.heightAnchor.constraint(equalToConstant: 30),

            // toolbar
            toolbar.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            toolbar.heightAnchor.constraint(equalToConstant: 32),

            // split
            split.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            split.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            split.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            split.heightAnchor.constraint(equalToConstant: 320),

            // attachments
            attachments.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 12),
            attachments.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            attachments.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            attachments.heightAnchor.constraint(equalToConstant: 100),

            // footer
            charCountLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            charCountLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),

            submitBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            submitBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),
            submitBtn.widthAnchor.constraint(equalToConstant: 130),
            submitBtn.heightAnchor.constraint(equalToConstant: 32),

            draftBtn.trailingAnchor.constraint(equalTo: submitBtn.leadingAnchor, constant: -8),
            draftBtn.bottomAnchor.constraint(equalTo: submitBtn.bottomAnchor),
            draftBtn.heightAnchor.constraint(equalToConstant: 32),

            cancelBtn.trailingAnchor.constraint(equalTo: draftBtn.leadingAnchor, constant: -8),
            cancelBtn.bottomAnchor.constraint(equalTo: submitBtn.bottomAnchor),
            cancelBtn.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func wireCallbacks() {
        editor.onPasteImages = { [weak self] imgs in self?.addImages(imgs) }
        attachments.refresh(images: pendingImages)
    }

    // MARK: - Markdown 操作（工具栏 + 快捷键）

    @objc func mdBold() { wrapSelection("**") }
    @objc func mdItalic() { wrapSelection("*") }
    @objc func mdStrike() { wrapSelection("~~") }
    @objc func mdHeading() { prefixLine("## ") }
    @objc func mdUL() { prefixLine("- ") }
    @objc func mdOL() { prefixLine("1. ") }
    @objc func mdQuote() { prefixLine("> ") }
    @objc func mdCode() { wrapSelection("`") }
    @objc func mdLink() {
        guard let textStorage = editor.textStorage else { return }
        let r = editor.selectedRange()
        let sel = (textStorage.string as NSString).substring(with: r)
        let replacement = "[\(sel.isEmpty ? "链接文字" : sel)](https://)"
        editor.insertText(replacement, replacementRange: r)
        // 选中 url 让用户改
        let urlStart = (editor.string as NSString).range(of: "](https://", options: .backwards)
        if urlStart.location != NSNotFound {
            let s = urlStart.location + 2
            editor.setSelectedRange(NSRange(location: s, length: 8))
        }
        updateAfterEdit()
    }
    @objc func mdImage() {
        // 插入 ![alt](filename) 占位 + 同时触发文件选择
        let r = editor.selectedRange()
        editor.insertText("![](image.png)", replacementRange: r)
        updateAfterEdit()
        pickImageFromDisk()
    }

    private func wrapSelection(_ wrap: String) {
        guard let ts = editor.textStorage else { return }
        let r = editor.selectedRange()
        if r.length == 0 {
            editor.insertText("\(wrap)\(wrap)", replacementRange: r)
            // 把光标移到中间
            editor.setSelectedRange(NSRange(location: r.location + wrap.count, length: 0))
        } else {
            let sel = (ts.string as NSString).substring(with: r)
            editor.insertText("\(wrap)\(sel)\(wrap)", replacementRange: r)
        }
        updateAfterEdit()
    }
    private func prefixLine(_ prefix: String) {
        guard let ts = editor.textStorage else { return }
        let r = editor.selectedRange()
        let s = ts.string as NSString
        // 找到行首
        let lineStart = s.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: r.location)).upperBound
        let safe = lineStart == NSNotFound ? 0 : lineStart
        editor.insertText(prefix, replacementRange: NSRange(location: safe, length: 0))
        updateAfterEdit()
    }

    // MARK: - 视图模式切换

    enum ViewMode { case editOnly, split, previewOnly }
    private func applyViewMode(_ mode: ViewMode) {
        switch mode {
        case .editOnly:
            editorScroll.isHidden = false
            preview.isHidden = true
        case .split:
            editorScroll.isHidden = false
            preview.isHidden = false
        case .previewOnly:
            editorScroll.isHidden = true
            preview.isHidden = false
        }
        split.layoutSubtreeIfNeeded()
    }

    // MARK: - 图片 / 附件

    private func addImages(_ imgs: [NSImage]) {
        // 大图缩到合理尺寸再存（避免 5MB+ 大图把 data.json 撑爆）
        for img in imgs {
            pendingImages.append(downsize(img, maxDim: 2000))
        }
        attachments.refresh(images: pendingImages)
    }
    private func removeAttachment(at idx: Int) {
        guard pendingImages.indices.contains(idx) else { return }
        pendingImages.remove(at: idx)
        attachments.refresh(images: pendingImages)
    }
    private func pickImageFromDisk() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "tiff", "bmp", "gif"]
        panel.beginSheetModal(for: view.window!) { [weak self] resp in
            guard resp == .OK, let self = self else { return }
            var imgs: [NSImage] = []
            for url in panel.urls {
                if let img = NSImage(contentsOf: url) {
                    imgs.append(img)
                }
            }
            self.addImages(imgs)
        }
    }
    /// 把图压缩到 maxDim × maxDim 以内（保持等比）
    private func downsize(_ img: NSImage, maxDim: CGFloat) -> NSImage {
        let s = img.size
        if s.width <= maxDim && s.height <= maxDim { return img }
        let scale = min(maxDim / s.width, maxDim / s.height)
        let newSize = NSSize(width: floor(s.width * scale), height: floor(s.height * scale))
        let dst = NSImage(size: newSize)
        dst.lockFocus()
        img.draw(in: NSRect(origin: .zero, size: newSize),
                 from: NSRect(origin: .zero, size: s),
                 operation: .copy, fraction: 1)
        dst.unlockFocus()
        return dst
    }

    // MARK: - 提醒

    @objc private func pickReminder() {
        ReminderPickerUI.present(current: pendingRemindAt, anchor: timeBtn) { [weak self] d in
            self?.pendingRemindAt = d
            self?.updateTimeBtnTitle()
        }
    }
    private func updateTimeBtnTitle() {
        if let d = pendingRemindAt {
            timeBtn.attributedTitle = NSAttributedString(
                string: "🕒 " + TaskRowView.smartDate(d),
                attributes: [
                    .foregroundColor: LazyCatTheme.accent,
                    .font: LazyCatTheme.body(12, weight: .heavy),
                ])
            timeBtn.layer?.backgroundColor = LazyCatTheme.accent.withAlphaComponent(0.15).cgColor
        } else {
            timeBtn.attributedTitle = NSAttributedString(
                string: "🕒 设置提醒",
                attributes: [
                    .foregroundColor: LazyCatTheme.textSec,
                    .font: LazyCatTheme.body(12, weight: .semibold),
                ])
            timeBtn.layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
        }
    }

    // MARK: - 提交 / 取消

    @objc private func cancelAndClose() {
        // ★ 退出前先静默存草稿（不弹 alert），用户取消的内容下次还能找回
        if !editor.string.isEmpty || !pendingImages.isEmpty || !titleField.stringValue.isEmpty {
            writeDraft(silent: true)
            let alert = NSAlert()
            alert.messageText = "放弃当前内容？"
            alert.informativeText = "已自动保存到草稿。下次打开「✍️ 长文」会问你要不要恢复。"
            alert.addButton(withTitle: "确定退出")
            alert.addButton(withTitle: "继续编辑")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        dismiss(nil)
    }

    @objc private func saveDraft() {
        writeDraft(silent: false)   // 用户手动点「存草稿」，弹确认
    }

    @objc private func submitTask() {
        let titleText = titleField.stringValue.trimmingCharacters(in: .whitespaces)
        let person = personCombo.stringValue.trimmingCharacters(in: .whitespaces)
        let body = editor.string.trimmingCharacters(in: .whitespacesAndNewlines)

        // ★ 显式 alert 提示哪里出了问题，不再静默 beep
        guard !person.isEmpty else {
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "请填写人名"
            alert.informativeText = "「为谁记的这条事？」要必填。\n\n你的内容已自动存草稿，不会丢。"
            alert.runModal()
            writeDraft(silent: true)
            view.window?.makeFirstResponder(personCombo)
            return
        }
        let combinedText: String = {
            if titleText.isEmpty { return body }
            if body.isEmpty { return titleText }
            return "# \(titleText)\n\n\(body)"
        }()
        guard !combinedText.isEmpty || !pendingImages.isEmpty else {
            NSSound.beep()
            let alert = NSAlert()
            alert.messageText = "标题或正文 至少填一个"
            alert.informativeText = "也可以只贴图片。"
            alert.runModal()
            view.window?.makeFirstResponder(titleField)
            return
        }

        // 字数硬上限
        let safe = String(combinedText.prefix(charLimit))

        // 存图片
        var imageNames: [String] = []
        for img in pendingImages {
            if let n = Store.shared.saveImage(img) { imageNames.append(n) }
        }

        let result = Result(person: person, text: safe, imageFiles: imageNames,
                            priority: priDots.priority, remindAt: pendingRemindAt)
        // ★ 提交成功 → 清掉草稿
        UserDefaults.standard.removeObject(forKey: Self.draftKey)
        onSave?(result)
        dismiss(nil)
    }

    // MARK: - 字数 + 实时预览

    fileprivate func updateAfterEdit() {
        updateCharCount()
        renderPreview()
        applyEditorSyntaxHighlight()
    }

    private func updateCharCount() {
        let n = editor.string.count
        charCountLabel.stringValue = "\(n) / \(charLimit) 字"
        charCountLabel.textColor = n > charLimit
            ? NSColor(red: 0.83, green: 0.19, blue: 0.16, alpha: 1)
            : LazyCatTheme.textTer
    }

    private func renderPreview() {
        // 把当前编辑器的 markdown 解析成 NSAttributedString 喂 preview
        let combined: String = {
            let titleText = titleField.stringValue.trimmingCharacters(in: .whitespaces)
            let body = editor.string
            if titleText.isEmpty { return body }
            return "# \(titleText)\n\n\(body)"
        }()
        preview.setMarkdown(combined, attachedImageNames: nil, pendingImages: pendingImages)
    }

    private func applyEditorSyntaxHighlight() {
        guard let ts = editor.textStorage else { return }
        let full = NSRange(location: 0, length: ts.length)
        ts.beginEditing()
        ts.setAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: LazyCatTheme.textPrimary,
        ], range: full)

        let s = ts.string as NSString
        // 标题: ^#+ .*$
        regex(s, "^#{1,6}\\s.+$", options: [.anchorsMatchLines]) { range in
            ts.addAttributes([
                .foregroundColor: NSColor(red: 0.83, green: 0.31, blue: 0.05, alpha: 1),
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .heavy),
            ], range: range)
        }
        // 粗体 **xxx**
        regex(s, "\\*\\*[^\\*\\n]+\\*\\*") { range in
            ts.addAttributes([
                .foregroundColor: NSColor(red: 0.72, green: 0.37, blue: 0.00, alpha: 1),
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .heavy),
            ], range: range)
        }
        // 斜体 *xxx*
        regex(s, "(?<!\\*)\\*[^\\*\\n]+\\*(?!\\*)") { range in
            ts.addAttributes([
                .foregroundColor: NSColor(red: 0.72, green: 0.37, blue: 0.00, alpha: 1),
            ], range: range)
        }
        // 行内代码 `xxx`
        regex(s, "`[^`\\n]+`") { range in
            ts.addAttributes([
                .foregroundColor: NSColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1),
                .backgroundColor: NSColor(red: 0.97, green: 0.94, blue: 0.89, alpha: 1),
            ], range: range)
        }
        // 链接 [xx](url)
        regex(s, "\\[[^\\]]+\\]\\([^)]+\\)") { range in
            ts.addAttributes([
                .foregroundColor: NSColor(red: 0.10, green: 0.46, blue: 0.82, alpha: 1),
            ], range: range)
        }
        ts.endEditing()
    }

    private func regex(_ s: NSString, _ pattern: String,
                       options: NSRegularExpression.Options = [],
                       _ handler: (NSRange) -> Void) {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        re.enumerateMatches(in: s as String, range: NSRange(location: 0, length: s.length)) { m, _, _ in
            if let r = m?.range { handler(r) }
        }
    }
}

// MARK: - NSTextViewDelegate / 字数限制

extension MarkdownEditorViewController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        if editor.string.count > charLimit {
            editor.string = String(editor.string.prefix(charLimit))
        }
        updateAfterEdit()
    }
}

// MARK: - NSComboBox

extension MarkdownEditorViewController: NSComboBoxDataSource, NSComboBoxDelegate {
    func numberOfItems(in comboBox: NSComboBox) -> Int { personSuggestions.count }
    func comboBox(_ cb: NSComboBox, objectValueForItemAt i: Int) -> Any? {
        personSuggestions.indices.contains(i) ? personSuggestions[i] : nil
    }
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSComboBox, f === personCombo else { return }
        personSuggestions = Store.shared.suggestPersons(for: f.stringValue)
        personCombo.reloadData()
    }
    func controlTextDidBeginEditing(_ obj: Notification) {
        personSuggestions = Store.shared.suggestPersons(for: personCombo.stringValue)
        personCombo.reloadData()
    }
}

// MARK: - 编辑器 (NSTextView)：粘贴图片 + 快捷键拦截

final class MarkdownTextView: NSTextView {
    weak var editorOwner: MarkdownEditorViewController?
    var onPasteImages: (([NSImage]) -> Void)?

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.tiff, .png, .fileURL]
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        // 优先处理图片：从 pasteboard 读 NSImage，扔给附件区，文字不变
        var images: [NSImage] = []
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [
            NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true,
            NSPasteboard.ReadingOptionKey.urlReadingContentsConformToTypes: [
                "public.png", "public.jpeg", "public.tiff",
                "public.image",
            ],
        ]) as? [URL] {
            for u in urls {
                if let img = NSImage(contentsOf: u) { images.append(img) }
            }
        }
        if images.isEmpty, let imgs = pboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            images.append(contentsOf: imgs)
        }
        if !images.isEmpty {
            onPasteImages?(images)
            return true
        }
        return super.readSelection(from: pboard, type: type)
    }

    /// 拦快捷键：⌘B / ⌘I / ⌘⇧X / ⌘⇧C
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let owner = editorOwner else { return super.performKeyEquivalent(with: event) }
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if cmd && !shift && chars == "b" { owner.mdBold(); return true }
        if cmd && !shift && chars == "i" { owner.mdItalic(); return true }
        if cmd && shift && chars == "x"  { owner.mdStrike(); return true }
        if cmd && shift && chars == "c"  { owner.mdCode(); return true }
        return super.performKeyEquivalent(with: event)
    }

    /// 接受拖拽图片
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return looksLikeImageDrag(sender) ? .copy : super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if looksLikeImageDrag(sender) {
            var imgs: [NSImage] = []
            if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                for u in urls {
                    if let img = NSImage(contentsOf: u) { imgs.append(img) }
                }
            }
            if imgs.isEmpty, let arr = sender.draggingPasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
                imgs = arr
            }
            if !imgs.isEmpty { onPasteImages?(imgs); return true }
        }
        return super.performDragOperation(sender)
    }
    private func looksLikeImageDrag(_ s: NSDraggingInfo) -> Bool {
        s.draggingPasteboard.canReadObject(forClasses: [NSImage.self], options: nil) ||
            s.draggingPasteboard.types?.contains(.fileURL) == true
    }
}

// MARK: - 视图模式 toggle

private final class ViewModeToggle: NSView {
    var onChange: ((MarkdownEditorViewController.ViewMode) -> Void)?
    private var btns: [NSButton] = []
    private let titles = ["仅编辑", "编辑+预览", "仅预览"]

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
        layer?.cornerRadius = 6
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for (i, title) in titles.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(pick(_:)))
            b.tag = i
            b.bezelStyle = .rounded
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.cornerRadius = 5
            b.font = LazyCatTheme.body(11, weight: .heavy)
            b.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(b)
            btns.append(b)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        select(1)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func pick(_ sender: NSButton) { select(sender.tag) }
    private func select(_ i: Int) {
        for (j, b) in btns.enumerated() {
            let on = i == j
            b.layer?.backgroundColor = on ? NSColor.white.cgColor : NSColor.clear.cgColor
            b.contentTintColor = on ? LazyCatTheme.accent : LazyCatTheme.textSec
            b.attributedTitle = NSAttributedString(string: titles[j], attributes: [
                .foregroundColor: on ? LazyCatTheme.accent : LazyCatTheme.textSec,
                .font: LazyCatTheme.body(11, weight: .heavy),
            ])
        }
        let mode: MarkdownEditorViewController.ViewMode = i == 0 ? .editOnly : (i == 2 ? .previewOnly : .split)
        onChange?(mode)
    }
}

// MARK: - 图片附件区

final class ImageAttachmentsView: NSView {
    var onPick: (() -> Void)?
    var onRemove: ((Int) -> Void)?
    var onDropImages: (([NSImage]) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "🖼  图片附件")
    private let countLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private let docContainer = NSView()
    private let hint = NSTextField(labelWithString: "支持 拖拽 / 粘贴 / Cmd+V · 点击 ＋ 选文件")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = LazyCatTheme.cornerSm
        layer?.borderWidth = 1
        layer?.borderColor = LazyCatTheme.border.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL, .tiff, .png])
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        titleLabel.font = LazyCatTheme.body(11, weight: .heavy)
        titleLabel.textColor = LazyCatTheme.textSec
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        countLabel.font = LazyCatTheme.body(11, weight: .semibold)
        countLabel.textColor = LazyCatTheme.textTer
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(countLabel)

        hint.font = LazyCatTheme.body(10, weight: .semibold)
        hint.textColor = LazyCatTheme.textTer
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        docContainer.addSubview(stack)
        docContainer.translatesAutoresizingMaskIntoConstraints = false

        scroll.documentView = docContainer
        scroll.hasHorizontalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            hint.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            docContainer.heightAnchor.constraint(equalTo: scroll.heightAnchor),
            stack.topAnchor.constraint(equalTo: docContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: docContainer.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: docContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: docContainer.trailingAnchor),
        ])
    }

    func refresh(images: [NSImage]) {
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        countLabel.stringValue = images.isEmpty ? "" : "· \(images.count) 张"

        for (i, img) in images.enumerated() {
            stack.addArrangedSubview(thumb(img: img, index: i))
        }
        // + 按钮
        let plus = NSButton(title: "＋", target: self, action: #selector(addClicked))
        plus.bezelStyle = .rounded
        plus.isBordered = false
        plus.wantsLayer = true
        plus.layer?.cornerRadius = 8
        plus.layer?.borderWidth = 1.5
        plus.layer?.borderColor = LazyCatTheme.border.cgColor
        plus.layer?.backgroundColor = LazyCatTheme.bgSurface.cgColor
        plus.font = .systemFont(ofSize: 22, weight: .light)
        plus.translatesAutoresizingMaskIntoConstraints = false
        plus.widthAnchor.constraint(equalToConstant: 64).isActive = true
        plus.heightAnchor.constraint(equalToConstant: 64).isActive = true
        plus.toolTip = "选图片文件"
        stack.addArrangedSubview(plus)
    }

    private func thumb(img: NSImage, index: Int) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 64).isActive = true
        v.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let iv = NSImageView()
        iv.image = img
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 6
        iv.layer?.masksToBounds = true
        iv.layer?.borderWidth = 1
        iv.layer?.borderColor = NSColor.white.cgColor
        iv.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(iv)

        let x = NSButton(title: "×", target: self, action: #selector(removeClicked(_:)))
        x.tag = index
        x.bezelStyle = .circular
        x.isBordered = false
        x.wantsLayer = true
        x.layer?.backgroundColor = NSColor(red: 0.83, green: 0.19, blue: 0.16, alpha: 1).cgColor
        x.layer?.cornerRadius = 9
        x.contentTintColor = .white
        x.font = .systemFont(ofSize: 9, weight: .heavy)
        x.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(x)

        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: v.topAnchor),
            iv.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            iv.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            x.topAnchor.constraint(equalTo: v.topAnchor, constant: -4),
            x.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: 4),
            x.widthAnchor.constraint(equalToConstant: 18),
            x.heightAnchor.constraint(equalToConstant: 18),
        ])
        return v
    }

    @objc private func addClicked() { onPick?() }
    @objc private func removeClicked(_ sender: NSButton) { onRemove?(sender.tag) }

    // MARK: - Drag-and-drop
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = LazyCatTheme.accent.cgColor
        layer?.borderWidth = 2
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = LazyCatTheme.border.cgColor
        layer?.borderWidth = 1
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = LazyCatTheme.border.cgColor
        layer?.borderWidth = 1
        var imgs: [NSImage] = []
        if let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for u in urls {
                if let img = NSImage(contentsOf: u) { imgs.append(img) }
            }
        }
        if imgs.isEmpty, let arr = sender.draggingPasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            imgs = arr
        }
        if !imgs.isEmpty { onDropImages?(imgs); return true }
        return false
    }
}

// MARK: - Markdown 预览渲染

final class MarkdownPreviewView: NSScrollView {
    private let textView: NSTextView = {
        let tc = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        tc.widthTracksTextView = true
        let lm = NSLayoutManager()
        lm.addTextContainer(tc)
        let ts = NSTextStorage()
        ts.addLayoutManager(lm)
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300),
                            textContainer: tc)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        return tv
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        documentView = textView
        hasVerticalScroller = true
        borderType = .noBorder
        drawsBackground = true
        backgroundColor = NSColor.white
        wantsLayer = true
        layer?.cornerRadius = LazyCatTheme.cornerSm
        layer?.borderColor = LazyCatTheme.border.cgColor
        layer?.borderWidth = 1

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.allowsImageEditing = false
        textView.usesFindBar = true
    }

    func setMarkdown(_ md: String, attachedImageNames: [String]?, pendingImages: [NSImage]) {
        textView.textStorage?.setAttributedString(MarkdownRenderer.render(md, pendingImages: pendingImages))
    }
}

/// 简易 Markdown → NSAttributedString 渲染器
/// 支持：# 标题、**粗体**、*斜体*、`code`、```fenced```、>引用、- list、1. list、[link](url)、![alt](filename)
enum MarkdownRenderer {
    static func render(_ md: String, pendingImages: [NSImage]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = md.components(separatedBy: "\n")
        var i = 0
        var inFence = false
        var fenceBuf: [String] = []

        while i < lines.count {
            let line = lines[i]

            // fenced code block ``` ... ```
            if line.hasPrefix("```") {
                if inFence {
                    // close
                    let code = fenceBuf.joined(separator: "\n")
                    result.append(makeCodeBlock(code))
                    fenceBuf.removeAll()
                    inFence = false
                } else {
                    inFence = true
                }
                i += 1
                continue
            }
            if inFence {
                fenceBuf.append(line)
                i += 1
                continue
            }

            // headings
            if let m = line.firstMatch(of: #"^(#{1,6})\s+(.+)$"#) {
                let level = m.captures[0].count
                let text = m.captures[1]
                result.append(makeHeading(text, level: level))
                i += 1; continue
            }
            // quote
            if line.hasPrefix("> ") {
                let text = String(line.dropFirst(2))
                result.append(makeQuote(text))
                i += 1; continue
            }
            // list - / 1.
            if let m = line.firstMatch(of: #"^[-*]\s+(.+)$"#) {
                result.append(makeListItem(m.captures[0], ordered: false))
                i += 1; continue
            }
            if let m = line.firstMatch(of: #"^\d+\.\s+(.+)$"#) {
                result.append(makeListItem(m.captures[0], ordered: true))
                i += 1; continue
            }
            // image ![](file)
            if let m = line.firstMatch(of: #"^!\[([^\]]*)\]\(([^)]+)\)$"#) {
                let alt = m.captures[0]
                let src = m.captures[1]
                result.append(makeImageBlock(src: src, alt: alt, pendingImages: pendingImages))
                i += 1; continue
            }
            // 普通段落
            result.append(makeParagraph(line))
            i += 1
        }
        return result
    }

    private static func bodyAttrs(_ size: CGFloat = 13) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        p.paragraphSpacing = 6
        return [
            .font: NSFont.systemFont(ofSize: size, weight: .regular),
            .foregroundColor: LazyCatTheme.textPrimary,
            .paragraphStyle: p,
        ]
    }

    private static func makeHeading(_ s: String, level: Int) -> NSAttributedString {
        let size: CGFloat = [22, 18, 16, 14, 13, 13][min(level - 1, 5)]
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = 8
        p.paragraphSpacing = 6
        let a: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .heavy),
            .foregroundColor: LazyCatTheme.textPrimary,
            .paragraphStyle: p,
        ]
        let str = NSMutableAttributedString(string: s + "\n", attributes: a)
        applyInline(to: str)
        return str
    }

    private static func makeParagraph(_ s: String) -> NSAttributedString {
        let str = NSMutableAttributedString(string: s + "\n", attributes: bodyAttrs())
        applyInline(to: str)
        return str
    }

    private static func makeQuote(_ s: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = 12
        p.headIndent = 12
        let a: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: LazyCatTheme.textSec,
            .obliqueness: 0.15,
            .paragraphStyle: p,
        ]
        let str = NSMutableAttributedString(string: "▍ " + s + "\n", attributes: a)
        // 替换 "▍" 为橙色
        let r = (str.string as NSString).range(of: "▍")
        if r.location != NSNotFound {
            str.addAttribute(.foregroundColor, value: LazyCatTheme.accent, range: r)
        }
        applyInline(to: str)
        return str
    }

    private static func makeListItem(_ s: String, ordered: Bool) -> NSAttributedString {
        let bullet = ordered ? "1.  " : "•  "
        let str = NSMutableAttributedString(string: bullet + s + "\n", attributes: bodyAttrs())
        applyInline(to: str)
        return str
    }

    private static func makeCodeBlock(_ code: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = 12
        p.headIndent = 12
        p.paragraphSpacing = 6
        p.paragraphSpacingBefore = 6
        let a: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor(red: 1.0, green: 0.91, blue: 0.75, alpha: 1),
            .backgroundColor: NSColor(red: 0.17, green: 0.09, blue: 0.06, alpha: 1),
            .paragraphStyle: p,
        ]
        return NSAttributedString(string: code + "\n", attributes: a)
    }

    private static func makeImageBlock(src: String, alt: String, pendingImages: [NSImage]) -> NSAttributedString {
        // 试着按 src 在 pendingImages 中找；若找不到就走 Store
        var image: NSImage?
        if let idx = Int(src.prefix(while: { $0.isNumber })), pendingImages.indices.contains(idx) {
            image = pendingImages[idx]
        }
        if image == nil {
            image = Store.shared.loadImage(named: src) ?? pendingImages.first
        }
        guard let img = image else {
            return NSAttributedString(string: "🖼 [\(alt.isEmpty ? src : alt)]\n", attributes: bodyAttrs())
        }
        let attachment = NSTextAttachment()
        let cell = NSTextAttachmentCell(imageCell: img)
        // 限制最大宽度 480pt
        let maxW: CGFloat = 480
        let s = img.size
        let scale = s.width > maxW ? (maxW / s.width) : 1
        cell.image?.size = NSSize(width: s.width * scale, height: s.height * scale)
        attachment.attachmentCell = cell
        let str = NSMutableAttributedString()
        str.append(NSAttributedString(attachment: attachment))
        str.append(NSAttributedString(string: "\n", attributes: bodyAttrs()))
        return str
    }

    /// 行内 markdown：**bold** *italic* `code` [text](url)
    private static func applyInline(to str: NSMutableAttributedString) {
        let s = str.string as NSString
        // **bold**
        regex(s, "\\*\\*([^\\*\\n]+)\\*\\*") { full, inner in
            let baseFontSize = (str.attribute(.font, at: full.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 13
            str.addAttributes([
                .font: NSFont.systemFont(ofSize: baseFontSize, weight: .heavy),
            ], range: full)
        }
        // *italic*
        regex(s, "(?<!\\*)\\*([^\\*\\n]+)\\*(?!\\*)") { full, _ in
            str.addAttribute(.obliqueness, value: 0.18, range: full)
        }
        // `code`
        regex(s, "`([^`\\n]+)`") { full, _ in
            str.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .backgroundColor: NSColor(red: 1.0, green: 0.95, blue: 0.88, alpha: 1),
                .foregroundColor: NSColor(red: 0.83, green: 0.31, blue: 0.05, alpha: 1),
            ], range: full)
        }
        // [text](url)
        regex(s, "\\[([^\\]]+)\\]\\(([^)]+)\\)") { full, _ in
            // 简单处理：把整个链接文本设为 underline + accent
            str.addAttributes([
                .foregroundColor: LazyCatTheme.accent,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: full)
        }
        // 删除原始 markdown 标记会让索引乱跑，预览里保留 markdown 字符不影响阅读。
    }

    private static func regex(_ s: NSString, _ pattern: String, _ handler: (NSRange, [NSRange]) -> Void) {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return }
        re.enumerateMatches(in: s as String, range: NSRange(location: 0, length: s.length)) { m, _, _ in
            guard let m = m else { return }
            var groups: [NSRange] = []
            for g in 1..<m.numberOfRanges { groups.append(m.range(at: g)) }
            handler(m.range, groups)
        }
    }
}

// MARK: - 字符串 helper

private struct RegexCapture {
    let captures: [String]
}
private extension String {
    func firstMatch(of pattern: String) -> RegexCapture? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let s = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: s.length)) else { return nil }
        var caps: [String] = []
        for g in 1..<m.numberOfRanges {
            let r = m.range(at: g)
            caps.append(r.location == NSNotFound ? "" : s.substring(with: r))
        }
        return RegexCapture(captures: caps)
    }
}
