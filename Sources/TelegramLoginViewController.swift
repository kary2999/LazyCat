import AppKit

/// Telegram (TDLib) 登录 sheet
///
/// 状态机：
///   1. 没填 api_id/hash → 显示填 credentials + 「打开 my.telegram.org」按钮
///   2. 填了但没登录 → 显示手机号输入
///   3. 已发短信 → 显示验证码输入
///   4. 需要 2FA → 显示密码输入
///   5. 已登录 → 显示状态 + 「登出」
final class TelegramLoginViewController: NSViewController {

    private let titleLbl = NSTextField(labelWithString: "Telegram 登录")
    private let stateLbl = NSTextField(labelWithString: "")
    private let descLbl  = NSTextField(wrappingLabelWithString: "")
    private let input1Lbl = NSTextField(labelWithString: "")
    private let input1     = PasteableTextField()
    private let input2Lbl = NSTextField(labelWithString: "")
    private let input2     = PasteableTextField()
    private let helpBtn   = NSButton(title: "", target: nil, action: nil)
    private let actionBtn = NSButton(title: "", target: nil, action: nil)
    private let cancelBtn = NSButton(title: "关闭", target: nil, action: nil)

    private var observer: NSObjectProtocol?
    private var errObserver: NSObjectProtocol?

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 380))
        v.wantsLayer = true
        v.appearance = NSAppearance(named: .aqua)
        v.layer?.backgroundColor = NSColor.white.cgColor
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        build()
        TelegramTDLib.shared.start()
        observer = NotificationCenter.default.addObserver(
            forName: TelegramTDLib.authStateDidChange,
            object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        errObserver = NotificationCenter.default.addObserver(
            forName: TelegramTDLib.didReceiveError,
            object: nil, queue: .main) { [weak self] note in
                let msg = (note.userInfo?["message"] as? String) ?? "未知错误"
                let code = (note.userInfo?["code"] as? Int) ?? 0
                self?.showTdLibError(msg, code: code)
                // 错误后让按钮可点（refresh 会按当前 state 决定是否启用）
                self?.refresh()
        }
        refresh()
    }
    deinit {
        if let o = observer    { NotificationCenter.default.removeObserver(o) }
        if let o = errObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func showTdLibError(_ msg: String, code: Int) {
        // 用户友好翻译几条最常见的
        var hint = ""
        let lower = msg.lowercased()
        if lower.contains("api_id") || lower.contains("api id") || lower.contains("api_id_invalid") {
            hint = "\n\napi_id 错误：去 my.telegram.org 复制纯数字 api_id（不要带空格 / 引号）。"
        } else if lower.contains("api_hash") {
            hint = "\n\napi_hash 错误：去 my.telegram.org 复制 32 位十六进制字符串原样粘进来。"
        } else if lower.contains("phone_number_invalid") {
            hint = "\n\n手机号格式不对：必须带 + 国家码，如 +8613812345678。"
        } else if lower.contains("phone_number_banned") {
            hint = "\n\n这个手机号被 Telegram 封禁了。"
        } else if lower.contains("phone_code_invalid") {
            hint = "\n\n验证码不对，重试。"
        } else if lower.contains("password") {
            hint = "\n\n2FA 密码错。"
        } else if lower.contains("flood") {
            hint = "\n\n操作过频被限流，等几分钟再试。"
        }
        let a = NSAlert()
        a.messageText = "Telegram 报错"
        a.informativeText = "code=\(code) · \(msg)\(hint)"
        a.alertStyle = .warning
        a.runModal()
    }

    private func build() {
        titleLbl.font = LazyCatTheme.body(17, weight: .semibold)
        titleLbl.textColor = LazyCatTheme.tx1
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLbl)

        stateLbl.font = LazyCatTheme.body(11, weight: .semibold)
        stateLbl.textColor = LazyCatTheme.accent
        stateLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateLbl)

        descLbl.font = LazyCatTheme.body(12)
        descLbl.textColor = LazyCatTheme.tx2
        descLbl.maximumNumberOfLines = 0
        descLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLbl)

        input1Lbl.font = LazyCatTheme.body(11, weight: .semibold)
        input1Lbl.textColor = LazyCatTheme.tx2
        input1Lbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(input1Lbl)

        input1.font = LazyCatTheme.body(12)
        input1.bezelStyle = .roundedBezel
        input1.focusRingType = .none
        input1.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(input1)

        input2Lbl.font = LazyCatTheme.body(11, weight: .semibold)
        input2Lbl.textColor = LazyCatTheme.tx2
        input2Lbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(input2Lbl)

        input2.font = LazyCatTheme.body(12)
        input2.bezelStyle = .roundedBezel
        input2.focusRingType = .none
        input2.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(input2)

        LazyCatTheme.applyButtonStyle(helpBtn, style: .secondary)
        helpBtn.target = self
        helpBtn.action = #selector(helpTap)
        helpBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(helpBtn)

        LazyCatTheme.applyButtonStyle(actionBtn, style: .primary)
        actionBtn.target = self
        actionBtn.action = #selector(actionTap)
        actionBtn.keyEquivalent = "\r"
        actionBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionBtn)

        LazyCatTheme.applyButtonStyle(cancelBtn, style: .secondary)
        cancelBtn.attributedTitle = LazyCatTheme.makeBtnTitle("关闭", style: .secondary)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelTap)
        cancelBtn.keyEquivalent = "\u{1B}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelBtn)

        let pad: CGFloat = 22
        NSLayoutConstraint.activate([
            titleLbl.topAnchor.constraint(equalTo: view.topAnchor, constant: pad),
            titleLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            stateLbl.centerYAnchor.constraint(equalTo: titleLbl.centerYAnchor),
            stateLbl.leadingAnchor.constraint(equalTo: titleLbl.trailingAnchor, constant: 10),
            stateLbl.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -pad),

            descLbl.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 10),
            descLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            descLbl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),

            input1Lbl.topAnchor.constraint(equalTo: descLbl.bottomAnchor, constant: 16),
            input1Lbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),

            input1.topAnchor.constraint(equalTo: input1Lbl.bottomAnchor, constant: 4),
            input1.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            input1.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            input1.heightAnchor.constraint(equalToConstant: 26),

            input2Lbl.topAnchor.constraint(equalTo: input1.bottomAnchor, constant: 12),
            input2Lbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),

            input2.topAnchor.constraint(equalTo: input2Lbl.bottomAnchor, constant: 4),
            input2.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            input2.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            input2.heightAnchor.constraint(equalToConstant: 26),

            helpBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),
            helpBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            helpBtn.heightAnchor.constraint(equalToConstant: 30),

            cancelBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),
            cancelBtn.trailingAnchor.constraint(equalTo: actionBtn.leadingAnchor, constant: -8),
            cancelBtn.heightAnchor.constraint(equalToConstant: 30),
            cancelBtn.widthAnchor.constraint(equalToConstant: 70),

            actionBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),
            actionBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            actionBtn.heightAnchor.constraint(equalToConstant: 30),
            actionBtn.widthAnchor.constraint(equalToConstant: 130),
        ])
    }

    private func refresh() {
        let st = TelegramTDLib.shared.authState
        stateLbl.stringValue = "状态：\(st.rawValue)"
        // 每次刷新前先把 action 按钮置回可用，下面分支只有 .unknown/.waitingTdParams 才会再 disable
        actionBtn.isEnabled = true

        // 没 api 凭据
        if TelegramTDLib.shared.apiId == nil || TelegramTDLib.shared.apiHash == nil {
            descLbl.stringValue = "去 my.telegram.org 申请 API 凭据（一次性）：登录 → API development tools → 拿到 api_id 和 api_hash 填进来。"
            input1Lbl.stringValue = "API ID（数字）"
            input1Lbl.isHidden = false
            input1.isHidden = false
            input1.placeholderString = "如 1234567"
            input1.stringValue = TelegramTDLib.shared.apiId.map { "\($0)" } ?? ""
            input2Lbl.stringValue = "API Hash（32 位字符串）"
            input2Lbl.isHidden = false
            input2.isHidden = false
            input2.placeholderString = "如 abc123def456..."
            input2.stringValue = TelegramTDLib.shared.apiHash ?? ""
            helpBtn.attributedTitle = LazyCatTheme.makeBtnTitle("打开 my.telegram.org", style: .secondary)
            helpBtn.isHidden = false
            actionBtn.attributedTitle = LazyCatTheme.makeBtnTitle("保存凭据", style: .primary)
            return
        }

        switch st {
        case .waitingPhoneNumber:
            descLbl.stringValue = "输入你的 Telegram 手机号（带国家码，如 +8613812345678）。我们会让 TG 给你发验证码。"
            input1Lbl.stringValue = "手机号"
            input1Lbl.isHidden = false
            input1.isHidden = false
            input1.placeholderString = "+86..."
            // 不要每次 refresh 都清空，否则用户输入到一半收到状态推送会丢字
            if input1.stringValue.isEmpty {
                input1.stringValue = ""
            }
            input2Lbl.isHidden = true; input2.isHidden = true
            helpBtn.attributedTitle = LazyCatTheme.makeBtnTitle("改 API 凭据", style: .secondary)
            helpBtn.isHidden = false
            actionBtn.attributedTitle = LazyCatTheme.makeBtnTitle("发送验证码", style: .primary)
            actionBtn.isEnabled = true

        case .unknown, .waitingTdParams, .waitingEncryptionKey:
            // TDLib 还没就绪：不让用户填手机号，避免输入被吃掉
            descLbl.stringValue = "TDLib 在初始化（state=\(st.rawValue)）。日志：~/Library/Logs/MyTodoApp.log。\n• 卡住先点「重启 TDLib」；\n• 还卡 → 点「改 API 凭据」重填（api_id 是 7-8 位纯数字，不是 4 位）。"
            input1Lbl.isHidden = true; input1.isHidden = true
            input2Lbl.isHidden = true; input2.isHidden = true
            helpBtn.attributedTitle = LazyCatTheme.makeBtnTitle("改 API 凭据", style: .secondary)
            helpBtn.isHidden = false
            // ★ 把 actionBtn 复用成「重启 TDLib」—— 这是 waitingTdParams 卡死时的一键自救
            actionBtn.attributedTitle = LazyCatTheme.makeBtnTitle("重启 TDLib", style: .primary)
            actionBtn.isEnabled = true

        case .waitingCode:
            descLbl.stringValue = "TG 已经把验证码发给你（看 Telegram app 里的 「Telegram」官方账号通知，或短信）。"
            input1Lbl.stringValue = "验证码"
            input1Lbl.isHidden = false
            input1.isHidden = false
            input1.placeholderString = "5-6 位数字"
            input1.stringValue = ""
            input2Lbl.isHidden = true; input2.isHidden = true
            helpBtn.isHidden = true
            actionBtn.attributedTitle = LazyCatTheme.makeBtnTitle("提交验证码", style: .primary)

        case .waitingPassword:
            descLbl.stringValue = "你的账号开了二步验证，请输入密码。"
            input1Lbl.stringValue = "二步验证密码"
            input1Lbl.isHidden = false
            input1.isHidden = false
            input1.placeholderString = "你的 2FA 密码"
            input1.stringValue = ""
            input2Lbl.isHidden = true; input2.isHidden = true
            helpBtn.isHidden = true
            actionBtn.attributedTitle = LazyCatTheme.makeBtnTitle("提交密码", style: .primary)

        case .ready:
            descLbl.stringValue = "✓ 已登录。私聊 + 群里 @ 你 的消息会自动出现在主窗口右侧 TG 通知箱。"
            input1Lbl.isHidden = true; input1.isHidden = true
            input2Lbl.isHidden = true; input2.isHidden = true
            helpBtn.attributedTitle = LazyCatTheme.makeBtnTitle("登出", style: .secondary)
            helpBtn.isHidden = false
            actionBtn.attributedTitle = LazyCatTheme.makeBtnTitle("完成", style: .primary)

        case .loggingOut, .closed:
            descLbl.stringValue = "正在登出…"
            input1Lbl.isHidden = true; input1.isHidden = true
            input2Lbl.isHidden = true; input2.isHidden = true
            helpBtn.isHidden = true
            actionBtn.attributedTitle = LazyCatTheme.makeBtnTitle("关闭", style: .primary)
        }
    }

    @objc private func helpTap() {
        let st = TelegramTDLib.shared.authState
        if TelegramTDLib.shared.apiId == nil || TelegramTDLib.shared.apiHash == nil {
            NSWorkspace.shared.open(URL(string: "https://my.telegram.org")!)
            return
        }
        if st == .ready {
            TelegramTDLib.shared.logOut()
            return
        }
        // 任何还没登录成功的状态下，按 helpBtn 都允许回到改凭据界面
        if st != .ready {
            TelegramTDLib.shared.apiId = nil
            TelegramTDLib.shared.apiHash = nil
            refresh()
        }
    }

    @objc private func actionTap() {
        let st = TelegramTDLib.shared.authState
        // 立即禁用按钮，防止重复点击触发 "Another authorization query has started"
        // 下次 refresh()（authState 变化或 didReceiveError）会按状态重新打开
        actionBtn.isEnabled = false

        if TelegramTDLib.shared.apiId == nil || TelegramTDLib.shared.apiHash == nil {
            // 保存凭据
            let idStr = input1.stringValue.trimmingCharacters(in: .whitespaces)
            let hash = input2.stringValue.trimmingCharacters(in: .whitespaces)
            guard let id = Int32(idStr), id > 0 else {
                alert("API ID 必须是数字"); return
            }
            guard !hash.isEmpty else { alert("API Hash 不能为空"); return }
            TelegramTDLib.shared.setApiCredentials(id: id, hash: hash)
            // 重新 dispatch 一次：tdlib 现在能拿到参数
            TelegramTDLib.shared.start()
            refresh()
            return
        }

        switch st {
        case .waitingPhoneNumber:
            let phone = input1.stringValue.trimmingCharacters(in: .whitespaces)
            guard !phone.isEmpty else { alert("请填手机号"); return }
            TelegramTDLib.shared.setPhoneNumber(phone)
        case .unknown, .waitingTdParams, .waitingEncryptionKey:
            // 重启 TDLib：close → 重建 client → 重发参数
            TelegramTDLib.shared.restart()
            refresh()
        case .waitingCode:
            let code = input1.stringValue.trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty else { alert("请填验证码"); return }
            TelegramTDLib.shared.checkCode(code)
        case .waitingPassword:
            let pwd = input1.stringValue
            guard !pwd.isEmpty else { alert("请填 2FA 密码"); return }
            TelegramTDLib.shared.checkPassword(pwd)
        case .ready, .loggingOut, .closed:
            dismiss(nil)
        }
    }

    @objc private func cancelTap() { dismiss(nil) }

    private func alert(_ msg: String) {
        let a = NSAlert()
        a.messageText = msg
        a.runModal()
    }
}


// MARK: - 一定能粘贴的 NSTextField
//
// 默认 NSTextField 在 sheet / popover 里 Cmd+V 偶尔不响应，是因为 sheet 的 keyWindow
// 路由 + main menu 的 paste: action 偶尔被吃掉。这里直接在 performKeyEquivalent 里拦
// Cmd+V/C/X/A，把动作转给 currentEditor() (字段内嵌的 NSTextView 字段编辑器)。
// 同时挂一个右键菜单兜底鼠标场景。
final class PasteableTextField: NSTextField {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupContextMenu()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupContextMenu()
    }

    private func setupContextMenu() {
        let m = NSMenu()
        m.addItem(NSMenuItem(title: "剪切", action: #selector(cutFromMenu),       keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "复制", action: #selector(copyFromMenu),      keyEquivalent: ""))
        m.addItem(NSMenuItem(title: "粘贴", action: #selector(pasteFromMenu),     keyEquivalent: ""))
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "全选", action: #selector(selectAllFromMenu), keyEquivalent: ""))
        for it in m.items { it.target = self }
        self.menu = m
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 必须在 first responder 是自己（或它的字段编辑器）的时候才接管
        let isMineEditing: Bool = {
            guard let resp = window?.firstResponder else { return false }
            if resp === self { return true }
            // 字段编辑器是 NSTextView，它的 delegate 一般是宿主控件
            if let tv = resp as? NSTextView, tv.delegate === self { return true }
            return false
        }()
        guard isMineEditing,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let chars = event.charactersIgnoringModifiers?.lowercased()
        else { return super.performKeyEquivalent(with: event) }

        guard let editor = currentEditor() else {
            return super.performKeyEquivalent(with: event)
        }
        switch chars {
        case "v": editor.paste(nil);     return true
        case "c": editor.copy(nil);      return true
        case "x": editor.cut(nil);       return true
        case "a": editor.selectAll(nil); return true
        default:  return super.performKeyEquivalent(with: event)
        }
    }

    // 右键菜单回调：先确保自己拿到 first responder（即弹出字段编辑器）再操作
    @objc private func cutFromMenu()       { ensureEditing()?.cut(nil) }
    @objc private func copyFromMenu()      { ensureEditing()?.copy(nil) }
    @objc private func pasteFromMenu()     { ensureEditing()?.paste(nil) }
    @objc private func selectAllFromMenu() { ensureEditing()?.selectAll(nil) }

    private func ensureEditing() -> NSText? {
        if window?.firstResponder !== currentEditor() {
            window?.makeFirstResponder(self)
        }
        return currentEditor()
    }
}
