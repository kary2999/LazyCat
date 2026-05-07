import AppKit

/// Telegram bot 设置 sheet
final class TelegramSettingsViewController: NSViewController {

    private let titleLbl   = NSTextField(labelWithString: "Telegram 集成")
    private let descLbl    = NSTextField(wrappingLabelWithString:
        "在 @BotFather 创建 bot 拿到 token 后填到下面。\n" +
        "私聊机器人 → 自动建任务\n" +
        "群里 @机器人 → 自动建任务\n" +
        "每 30 秒自动同步一次")
    private let tokenField = NSTextField()
    private let enableSwitch = NSButton(checkboxWithTitle: "启用 Telegram 同步", target: nil, action: nil)
    private let testBtn    = NSButton(title: "测试连接", target: nil, action: nil)
    private let statusLbl  = NSTextField(labelWithString: "")
    private let saveBtn    = NSButton(title: "保存并启动", target: nil, action: nil)
    private let cancelBtn  = NSButton(title: "取消", target: nil, action: nil)

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        v.wantsLayer = true
        v.appearance = NSAppearance(named: .aqua)
        v.layer?.backgroundColor = NSColor.white.cgColor
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        build()
    }

    private func build() {
        titleLbl.font = LazyCatTheme.body(17, weight: .semibold)
        titleLbl.textColor = LazyCatTheme.tx1
        titleLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLbl)

        descLbl.font = LazyCatTheme.body(12)
        descLbl.textColor = LazyCatTheme.tx2
        descLbl.maximumNumberOfLines = 0
        descLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(descLbl)

        tokenField.placeholderString = "Bot Token (例：123456:ABC-xyz...)"
        tokenField.font = LazyCatTheme.mono(12)
        tokenField.bezelStyle = .roundedBezel
        tokenField.stringValue = TelegramSync.shared.token ?? ""
        tokenField.focusRingType = .none
        tokenField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tokenField)

        enableSwitch.state = TelegramSync.shared.enabled ? .on : .off
        enableSwitch.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(enableSwitch)

        LazyCatTheme.applyButtonStyle(testBtn, style: .secondary)
        testBtn.attributedTitle = LazyCatTheme.makeBtnTitle("测试连接", style: .secondary)
        testBtn.target = self
        testBtn.action = #selector(testTap)
        testBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(testBtn)

        statusLbl.font = LazyCatTheme.body(11)
        statusLbl.textColor = LazyCatTheme.tx3
        statusLbl.lineBreakMode = .byTruncatingTail
        statusLbl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLbl)
        updateStatus()

        LazyCatTheme.applyButtonStyle(saveBtn, style: .primary)
        saveBtn.attributedTitle = LazyCatTheme.makeBtnTitle("保存并启动", style: .primary)
        saveBtn.target = self
        saveBtn.action = #selector(saveTap)
        saveBtn.keyEquivalent = "\r"
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(saveBtn)

        LazyCatTheme.applyButtonStyle(cancelBtn, style: .secondary)
        cancelBtn.attributedTitle = LazyCatTheme.makeBtnTitle("取消", style: .secondary)
        cancelBtn.target = self
        cancelBtn.action = #selector(cancelTap)
        cancelBtn.keyEquivalent = "\u{1B}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelBtn)

        let pad: CGFloat = 24
        NSLayoutConstraint.activate([
            titleLbl.topAnchor.constraint(equalTo: view.topAnchor, constant: pad),
            titleLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),

            descLbl.topAnchor.constraint(equalTo: titleLbl.bottomAnchor, constant: 8),
            descLbl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            descLbl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),

            tokenField.topAnchor.constraint(equalTo: descLbl.bottomAnchor, constant: 16),
            tokenField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            tokenField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            tokenField.heightAnchor.constraint(equalToConstant: 26),

            enableSwitch.topAnchor.constraint(equalTo: tokenField.bottomAnchor, constant: 12),
            enableSwitch.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),

            testBtn.topAnchor.constraint(equalTo: enableSwitch.bottomAnchor, constant: 14),
            testBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: pad),
            testBtn.heightAnchor.constraint(equalToConstant: 30),
            testBtn.widthAnchor.constraint(equalToConstant: 100),

            statusLbl.leadingAnchor.constraint(equalTo: testBtn.trailingAnchor, constant: 12),
            statusLbl.centerYAnchor.constraint(equalTo: testBtn.centerYAnchor),
            statusLbl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),

            cancelBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),
            cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),
            cancelBtn.heightAnchor.constraint(equalToConstant: 30),
            cancelBtn.widthAnchor.constraint(equalToConstant: 80),

            saveBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -pad),
            saveBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -pad),
            saveBtn.heightAnchor.constraint(equalToConstant: 30),
            saveBtn.widthAnchor.constraint(equalToConstant: 130),
        ])
    }

    private func updateStatus() {
        let s = TelegramSync.shared
        var parts: [String] = []
        if let u = s.cachedBotUsername { parts.append("@\(u) ✓") } else { parts.append("机器人未连接") }
        parts.append(s.status)
        if let err = s.lastError { parts.append("⚠ \(err)") }
        statusLbl.stringValue = parts.joined(separator: " · ")
    }

    @objc private func testTap() {
        // 把当前输入的 token 临时存起来再测
        TelegramSync.shared.token = tokenField.stringValue.trimmingCharacters(in: .whitespaces)
        statusLbl.stringValue = "测试中…"
        TelegramSync.shared.testConnection { [weak self] result in
            switch result {
            case .success(let username):
                self?.statusLbl.stringValue = "✓ 连上了：@\(username)"
            case .failure(let err):
                self?.statusLbl.stringValue = "✗ \(err.localizedDescription)"
            }
        }
    }

    @objc private func saveTap() {
        let tk = tokenField.stringValue.trimmingCharacters(in: .whitespaces)
        TelegramSync.shared.token = tk.isEmpty ? nil : tk
        TelegramSync.shared.enabled = enableSwitch.state == .on
        TelegramSync.shared.startIfEnabled()
        dismiss(nil)
    }

    @objc private func cancelTap() {
        dismiss(nil)
    }
}

private extension TelegramSync {
    var cachedBotUsername: String? {
        // 暴露为 file-private 以便 settings vc 显示
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == "cachedBotUsername" {
                return child.value as? String
            }
        }
        return nil
    }
}
