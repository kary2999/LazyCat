import AppKit

/// 自定义"关于 LazyCat"面板。
/// 把这一份**当前真实在跑的版本信息**直接亮出来 —— 用户可以在每次更新后立即比对：
///   · CFBundleShortVersionString   = 1.5.0  (语义版本)
///   · LazyCatBuildDate             = 2026-04-28 12:34:56 CST  (build.sh 注入)
///   · LazyCatGitHash               = a1b2c3d  (build.sh 注入)
///   · Bundle Path                  = /Applications/自研项目/LazyCat.app  (验证 dock 指向哪份)
///   · Process PID                  = 12345
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private convenience init() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        win.title = "关于 LazyCat"
        win.isReleasedWhenClosed = false
        win.center()
        self.init(window: win)
        // ★ 不在 init 里建 contentView：那样会让 makeContentView → Self.shared
        //   在 shared 还没构造完时再次访问 shared，导致 dispatch_once 递归锁死崩溃。
        //   present() 第一次被调时再造内容即可。
    }

    func present() {
        // 每次打开都重新生成内容，确保信息是即时的
        window?.contentView = makeContentView()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build content

    /// 改为实例方法，按钮 target 可以直接用 self —— 避免再次访问 Self.shared
    private func makeContentView() -> NSView {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let buildVer = info["CFBundleVersion"] as? String ?? "?"
        let buildDate = info["LazyCatBuildDate"] as? String ?? "(未注入 — build.sh 太老？)"
        let gitHash  = info["LazyCatGitHash"]  as? String ?? "—"
        let bundlePath = Bundle.main.bundlePath
        let exePath = Bundle.main.executablePath ?? "?"
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "?"

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 320))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).cgColor

        // 图标
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        // 标题
        let titleLabel = NSTextField(labelWithString: "LazyCat")
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        // 大版本
        let versionLabel = NSTextField(labelWithString: "v\(version) (build \(buildVer))")
        versionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        versionLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        versionLabel.isBezeled = false
        versionLabel.drawsBackground = false
        versionLabel.isEditable = false
        versionLabel.isSelectable = true   // 可选中复制
        versionLabel.translatesAutoresizingMaskIntoConstraints = false

        // 详细信息（多行 monospaced，可选中）
        let detail = NSTextView()
        detail.string = """
        构建时间   \(buildDate)
        Git 提交   \(gitHash)
        Bundle ID  \(bundleId)
        Bundle 路径
          \(bundlePath)
        可执行路径
          \(exePath)
        进程 PID   \(pid)
        """
        detail.isEditable = false
        detail.isSelectable = true
        detail.drawsBackground = false
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = NSColor.white.withAlphaComponent(0.78)
        detail.textContainerInset = NSSize(width: 4, height: 4)

        let detailScroll = NSScrollView()
        detailScroll.documentView = detail
        detailScroll.hasVerticalScroller = false
        detailScroll.drawsBackground = false
        detailScroll.borderType = .noBorder
        detailScroll.translatesAutoresizingMaskIntoConstraints = false

        // 复制按钮 —— 一键拷贝整段诊断信息
        let copyBtn = NSButton(title: "复制信息", target: nil, action: nil)
        copyBtn.bezelStyle = .rounded
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        copyBtn.target = self                    // ★ 直接用 self，不要 Self.shared
        copyBtn.action = #selector(copyDiagnostics(_:))

        let revealBtn = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
        revealBtn.bezelStyle = .rounded
        revealBtn.translatesAutoresizingMaskIntoConstraints = false
        revealBtn.target = self                  // ★ 同上
        revealBtn.action = #selector(revealInFinder(_:))

        root.addSubview(iconView)
        root.addSubview(titleLabel)
        root.addSubview(versionLabel)
        root.addSubview(detailScroll)
        root.addSubview(copyBtn)
        root.addSubview(revealBtn)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            iconView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),

            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            versionLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),

            detailScroll.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            detailScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            detailScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            detailScroll.heightAnchor.constraint(equalToConstant: 160),

            copyBtn.topAnchor.constraint(equalTo: detailScroll.bottomAnchor, constant: 12),
            copyBtn.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),

            revealBtn.topAnchor.constraint(equalTo: detailScroll.bottomAnchor, constant: 12),
            revealBtn.leadingAnchor.constraint(equalTo: copyBtn.trailingAnchor, constant: 8),
        ])

        return root
    }

    @objc private func copyDiagnostics(_ sender: Any?) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let buildDate = info["LazyCatBuildDate"] as? String ?? "?"
        let gitHash = info["LazyCatGitHash"] as? String ?? "—"
        let text = """
        LazyCat v\(version) (build \(build))
        构建时间: \(buildDate)
        Git: \(gitHash)
        Bundle: \(Bundle.main.bundlePath)
        Exe:    \(Bundle.main.executablePath ?? "?")
        PID:    \(ProcessInfo.processInfo.processIdentifier)
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func revealInFinder(_ sender: Any?) {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
