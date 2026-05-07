import AppKit

private let APP_DISPLAY_NAME = "LazyCat"

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.log("App.didFinishLaunching")

        // 强制深色外观：所有子窗口 / 控件都按 darkAqua 渲染，避免浅色背景 + 浅色文字的
        // 低对比度事故
        NSApp.appearance = NSAppearance(named: .darkAqua)

        // Dock / 任务切换器里的 Logo（128×128 圆胖白猫）
        NSApp.applicationIconImage = CatRenderer.makeAppIcon(size: NSSize(width: 512, height: 512))

        installMainMenu()

        let vc = ContentViewController()
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        w.title = APP_DISPLAY_NAME
        w.contentViewController = vc
        w.contentMinSize = NSSize(width: 1100, height: 560)
        // 4 栏布局，留宽点
        w.contentMaxSize = NSSize(width: 1500, height: 4000)
        // 关键：关闭窗口时不要释放，否则菜单栏再唤起会崩溃（野指针）
        w.isReleasedWhenClosed = false
        w.center()
        // ★ 改 autosave 名 V3，作废之前用户可能拉到全屏的尺寸
        w.setFrameAutosaveName("MyTodoMainWindowV4")
        self.window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 顶栏常驻图标
        MenuBarController.shared.appDelegate = self
        MenuBarController.shared.install()

        // 定时提醒引擎
        ReminderEngine.shared.start()

        // 全局键盘计数器：监听 keyDown，每天 0 点自动重置
        // 首次启动 macOS 会请求"输入监控"权限，用户须在 系统设置 > 隐私 与 安全 > 输入监控 里勾选 LazyCat
        KeyTypingCounter.shared.start()

        // ★ Telegram (TDLib) — 启动后台接收循环；如果用户没配 api_id/hash 也无害，会停在 waitingTdParams
        TelegramTDLib.shared.start()

        // 自动锁屏：默认关；用户在菜单里开启后，闲置满阈值秒数自动展开遮罩
        IdleLockMonitor.shared.start()

        // 全局热键：从 LockHotKeySettings 取当前预设；监听变化重新注册
        applyLockHotKey()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyLockHotKey),
            name: LockHotKeySettings.didChangeNotification, object: nil)

        // 启动时自动打开小猫悬浮徽标（在桌面右上角常驻）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            FloatingWidgetController.shared.showCollapsed()
        }

        AppLog.log("App.window shown")
    }

    /// 退出前 graceful 停 TDLib，避免 receive 线程和 exit() 静态析构撞车崩溃
    func applicationWillTerminate(_ notification: Notification) {
        TelegramTDLib.shared.shutdownBeforeTerminate()
    }

    /// 关闭主窗口后保留菜单栏图标，从图标可以再唤回
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func showMainWindow() {
        // 若窗口曾被系统回收（或首次唤起），重建一个
        if window == nil {
            let vc = ContentViewController()
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            w.title = APP_DISPLAY_NAME
            w.contentViewController = vc
            w.contentMinSize = NSSize(width: 720, height: 620)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("MyTodoMainWindowV2")
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Top menu bar (左上 App 菜单)
    private func installMainMenu() {
        let mainMenu = NSMenu()
        let name = APP_DISPLAY_NAME

        // App menu
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: name)
        appItem.submenu = appMenu
        let aboutItem = NSMenuItem(title: "关于 \(name)",
            action: #selector(showAboutWindow(_:)), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏 \(name)",
            action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: "隐藏其它",
            action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: "显示全部",
            action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 \(name)",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // 文件菜单（新建事件 = 聚焦输入框）
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "文件")
        fileItem.submenu = fileMenu
        fileMenu.addItem(NSMenuItem(title: "新建事件",
            action: #selector(newEvent(_:)), keyEquivalent: "n"))

        // Edit menu（粘贴 / 撤销 / 全选 必备）
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        // Window menu
        let winItem = NSMenuItem()
        mainMenu.addItem(winItem)
        let winMenu = NSMenu(title: "窗口")
        winItem.submenu = winMenu
        winMenu.addItem(NSMenuItem(title: "最小化",
            action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        winMenu.addItem(NSMenuItem(title: "缩放",
            action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        winMenu.addItem(.separator())
        winMenu.addItem(NSMenuItem(title: "显示主窗口",
            action: #selector(showWindowAction(_:)), keyEquivalent: "0"))
        let toggleFloating = NSMenuItem(title: "桌面悬浮窗",
            action: #selector(toggleFloating(_:)), keyEquivalent: "f")
        toggleFloating.keyEquivalentModifierMask = [.command, .shift]
        winMenu.addItem(toggleFloating)

        let toggleMask = NSMenuItem(title: "专注遮罩（全屏）",
            action: #selector(toggleFullscreenMask(_:)), keyEquivalent: "d")
        toggleMask.keyEquivalentModifierMask = [.command, .shift]
        winMenu.addItem(toggleMask)

        NSApp.mainMenu = mainMenu
    }

    @objc private func newEvent(_ sender: Any?) {
        showMainWindow()
        NotificationCenter.default.post(name: .focusQuickAdd, object: nil)
    }

    @objc private func showWindowAction(_ sender: Any?) {
        showMainWindow()
    }

    @objc func toggleFloating(_ sender: Any?) {
        FloatingWidgetController.shared.toggle()
    }

    @objc func toggleFullscreenMask(_ sender: Any?) {
        FullscreenMaskController.shared.toggle()
    }

    @objc private func showAboutWindow(_ sender: Any?) {
        AboutWindowController.shared.present()
    }

    @objc private func applyLockHotKey() {
        let preset = LockHotKeySettings.shared.current
        if preset.keyCode < 0 {
            // 用户选择"关闭"
            GlobalHotKey.shared.unregister()
            AppLog.log("LockHotKey: disabled")
            return
        }
        GlobalHotKey.shared.register(keyCode: preset.keyCode,
                                     carbonModifiers: preset.modifiers) {
            FullscreenMaskController.shared.toggle()
        }
        AppLog.log("LockHotKey applied: \(preset.title)")
    }
}
