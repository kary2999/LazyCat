import AppKit
import Carbon.HIToolbox      // cmdKey / shiftKey / optionKey / controlKey

/// 独立的全屏遮罩 / 专注模式：
///   - 每个连接的屏幕都盖一扇 borderless 窗口，level=CGShieldingWindowLevel
///   - 背景 NSVisualEffectView 毛玻璃 + 半透明黑 + 大时钟 + 当前任务
///   - **进入 / 退出 都靠同一个快捷键**（默认 ⌥1）。无密码。
///   - 如果用户在菜单里把快捷键设成"关闭"，则没法解锁 —— 这是用户主动选择
final class FullscreenMaskController {
    static let shared = FullscreenMaskController()
    private init() {}

    private var windows: [MaskWindow] = []
    private var tickTimer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?            // ★ Space 切换 → 重铺
    private var appActivateObserver: NSObjectProtocol?      // ★ 别的 app 激活 → re-orderFront
    private var topUpTimer: Timer?                          // ★ 周期性 re-orderFront 兜底
    private var keyEventMonitor: Any?            // mask 显示期间拦截危险键
    private var lockViolationCount = 0           // 锁屏期间非法按键次数（≥3 触发 Look My 👀）

    // ★ 系统级 CGEventTap（active mode，需 Accessibility 权限）
    private var systemEventTap: CFMachPort?
    private var systemEventRunLoopSrc: CFRunLoopSource?

    var isShown: Bool { !windows.isEmpty }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func show() {
        guard !isShown else { return }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: MaskSettings.didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.applySettings()
            }

        // 屏幕拔插（连接外屏 / 断开 / 分辨率变化）→ 重铺全部遮罩，
        // 防止新接的屏幕暴露桌面
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.rebuildWindows()
            }

        // ★ Space 切换（三/四指滑切桌面）→ 强制 mask 在新 Space 上前置
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.bringMasksFrontOnNewSpace()
            }

        // ★ 任何 app 激活时 mask 也 re-orderFront —— 防止"其他 app 弹出的子窗口/sheet
        //   level 高过我们 + collectionBehavior 不带 .stationary"那种漏网情况
        appActivateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.bringMasksFrontOnNewSpace()
            }

        // 周期性兜底：每 1.5s 把所有 mask 窗口 re-orderFront 一次。
        // 用于覆盖那些"晚于 mask 出现的子窗口"——比如某些 Electron / 外部 app 弹出的
        // 浮层 / fork 子页面（它们 level 一般不会高过 CGShieldingWindowLevel，但创建顺序
        // 在我们之后，OS 默认把它们叠在我们上面）
        let topT = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            for w in self.windows { w.orderFrontRegardless() }
        }
        RunLoop.main.add(topT, forMode: .common)
        topUpTimer = topT

        rebuildWindows()
        installSystemEventTap()    // ★ 装系统级输入拦截（如有 Accessibility 权限）

        // 重置违规计数（每次进锁屏从 0 开始）
        lockViolationCount = 0

        // ★ 锁屏期间硬封锁：键盘 + 触摸板 + 滚轮 全部吞掉
        //   - 解锁快捷键由 Carbon RegisterEventHotKey 走系统级独立通道（GetEventDispatcherTarget）
        //     不会进 Cocoa 的 addLocalMonitorForEvents，所以放心吞所有 keyDown
        //   - 任何到达这里的 keyDown 都视为"非法尝试"，累计 ≥3 → 全屏闪 "Look My 👀"
        //   - 触摸板手势（.swipe / .magnify / .rotate / .scrollWheel ...）一律吞，
        //     防止有人用三指切 Space 把锁屏甩开
        let blockMask: NSEvent.EventTypeMask = [
            .keyDown, .keyUp,
            .scrollWheel,
            .gesture, .magnify, .swipe, .rotate,
            .beginGesture, .endGesture,
            .smartMagnify,
        ]
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: blockMask) { [weak self] ev in
            guard let self = self else { return ev }
            switch ev.type {
            case .keyDown:
                let chars = ev.charactersIgnoringModifiers ?? ""
                // ★ 兜底：万一 CGEventTap 没装（无辅助功能权限）+ Carbon 也没 fire，
                //   在这里匹配解锁键直接 toggle
                if self.unlockHotKeyMatchFromNSEvent(ev) {
                    AppLog.log("Mask: unlock key 匹配（NSEvent 本地兜底）→ toggle")
                    DispatchQueue.main.async { [weak self] in self?.toggle() }
                    return nil
                }
                AppLog.log("Mask 吞键 keyCode=\(ev.keyCode) chars=\"\(chars)\" mods=\(ev.modifierFlags.rawValue)")
                self.recordViolation()
                return nil
            case .keyUp:
                return nil   // 同步吞掉，避免一些 app 在 keyUp 上做事
            case .scrollWheel,
                 .gesture, .magnify, .swipe, .rotate,
                 .beginGesture, .endGesture, .smartMagnify:
                return nil   // 触摸板 / 滚轮 全部吞
            default:
                return ev
            }
        }

        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.windows.forEach { ($0.contentView as? MaskContentView)?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    /// 给当前所有屏幕铺一遍遮罩窗口（屏幕变更时也调）
    private func rebuildWindows() {
        // 先关掉旧的
        for w in windows { w.orderOut(nil) }
        windows.removeAll()

        let screens = NSScreen.screens
        let shieldLevel = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))

        AppLog.log("Mask.rebuild: \(screens.count) 个屏幕，shieldLevel=\(shieldLevel.rawValue)")
        for (idx, sc) in screens.enumerated() {
            AppLog.log("  屏幕[\(idx)] \(sc.localizedName) frame=\(sc.frame)")
        }

        for (screenIdx, screen) in screens.enumerated() {
            let frame = screen.frame   // 全局坐标 (x,y 可能为负或 >0)

            // ★ 用 .zero 起步 + 后续 setFrame，避免某些 macOS 版本 init 时把
            //   非零 origin 的 contentRect 误算到主屏
            let w = MaskWindow(
                contentRect: NSRect(origin: .zero, size: frame.size),
                styleMask: [.borderless],
                backing: .buffered, defer: false,
                screen: screen)
            _ = screenIdx   // 保留索引变量备用
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = shieldLevel
            w.ignoresMouseEvents = false
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            w.hasShadow = false
            w.animationBehavior = .none

            // 不再有"密码输入"概念：所有屏幕都只显示时钟 + 当前任务
            let v = MaskContentView(frame: NSRect(origin: .zero, size: frame.size))
            w.contentView = v

            // 强制贴到目标屏幕（双保险：contentRect 已设 + setFrame 再设一次）
            w.setFrame(frame, display: true, animate: false)
            w.orderFrontRegardless()
            w.displayIfNeeded()

            windows.append(w)
            (w.contentView as? MaskContentView)?.refresh()

            AppLog.log("  装窗 → target=\(frame) actual=\(w.frame) onScreen=\(w.screen?.localizedName ?? "nil")")
        }

        // ★ 第二轮：让 mask 抓住键盘焦点 + 强制各屏 frame 再贴一次（macOS 偶发竞争）
        //   不抓焦点的话别处 app 的 keyDown 不会进 local monitor，无法吞键
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            // 把 LazyCat 提到前台 —— 不然 LSUIElement 应用不接收键盘
            NSApp.activate(ignoringOtherApps: true)
            let curScreens = NSScreen.screens
            for (i, w) in self.windows.enumerated() {
                if i < curScreens.count {
                    w.setFrame(curScreens[i].frame, display: true, animate: false)
                }
                w.orderFrontRegardless()
                w.displayIfNeeded()
            }
            // 让主屏 mask 成为 key window，吞所有键
            if let primary = self.windows.first(where: { $0.screen == NSScreen.main })
                ?? self.windows.first {
                primary.makeKey()
            }
            AppLog.log("Mask.rebuild 第二轮 orderFront + makeKey 完成（共 \(self.windows.count) 屏）")
        }
    }

    // MARK: - 违规计数 + 全屏 "Look My 👀" 警告

    /// mask 期间每次"试图按非法键"调一次
    private func recordViolation() {
        lockViolationCount += 1
        AppLog.log("Mask 违规 \(lockViolationCount)/3")
        if lockViolationCount >= 3 {
            lockViolationCount = 0   // 触发后归零，再敲 3 次再弹
            DispatchQueue.main.async { [weak self] in
                self?.flashLookMyOnAllScreens()
            }
        }
    }

    private func flashLookMyOnAllScreens() {
        for w in windows {
            (w.contentView as? MaskContentView)?.flashLookMyWarning()
        }
    }

    func hide() {
        tickTimer?.invalidate(); tickTimer = nil
        if let o = settingsObserver {
            NotificationCenter.default.removeObserver(o); settingsObserver = nil
        }
        if let o = screenObserver {
            NotificationCenter.default.removeObserver(o); screenObserver = nil
        }
        if let o = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o); spaceObserver = nil
        }
        if let o = appActivateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o); appActivateObserver = nil
        }
        topUpTimer?.invalidate(); topUpTimer = nil
        if let m = keyEventMonitor {
            NSEvent.removeMonitor(m); keyEventMonitor = nil
        }
        uninstallSystemEventTap()
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        lockViolationCount = 0
    }

    // MARK: - Space 切换：强制 mask 在新 Space 前置

    private func bringMasksFrontOnNewSpace() {
        AppLog.log("Mask: activeSpaceDidChange → 完整重铺所有屏幕的 mask")
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.windows.isEmpty else { return }
            // ★ CGShieldingWindowLevel 下 .canJoinAllSpaces 对"用户三指滑切到新 Space"
            //   时常不跟过去；orderOut+orderFront 也不可靠。最稳的办法是直接 rebuild：
            //   销毁旧窗口（已经留在原 Space 了），在当前 Space 上重新创建一组。
            //   一组窗口很轻量（borderless + visualEffect），重建延迟 < 50ms 用户感知不到。
            self.rebuildWindows()
            // 让本 app 抢前台 + 主屏 mask 抓键盘焦点（吞键 + 让 unlock 路由生效）
            NSApp.activate(ignoringOtherApps: true)
            if let primary = self.windows.first(where: { $0.screen == NSScreen.main }) ?? self.windows.first {
                primary.makeKey()
            }
        }
    }

    // MARK: - 系统级 CGEventTap（active mode，吞所有键盘 / 触摸板输入）

    private func installSystemEventTap() {
        // ★ 静默查权限：prompt: false → 没权限就直接跳过，不再每次 mask 启动都弹"辅助功能"对话框。
        //   用户主动想开"硬封锁"模式 → 走菜单里的「申请辅助功能权限」一次。
        //   ad-hoc 签名重 build CDHash 会变 → TCC 失效 → 跳过逻辑会触发，但不会再骚扰。
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            AppLog.log("Mask: 无 Accessibility 权限 — 系统级 tap 跳过（用 NSEvent local monitor + Carbon hot key 兜底）")
            return
        }

        // 分步算 mask，避免 Swift 编译器卡死在长 expression
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .scrollWheel,
            .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        ]
        var mask: UInt64 = 0
        for t in types { mask |= (1 << UInt64(t.rawValue)) }
        let cgMask = CGEventMask(mask)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<FullscreenMaskController>.fromOpaque(refcon).takeUnretainedValue()
            return me.systemEventCallback(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,                // ★ active filter，可吞事件
            eventsOfInterest: cgMask,
            callback: callback,
            userInfo: userInfo)
        else {
            AppLog.log("Mask: CGEvent.tapCreate 失败")
            return
        }

        systemEventTap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        systemEventRunLoopSrc = src
        AppLog.log("Mask: ★ 系统级 CGEventTap 安装成功（吞全键盘/鼠标/触摸板）")
    }

    private func uninstallSystemEventTap() {
        if let tap = systemEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            systemEventTap = nil
        }
        if let src = systemEventRunLoopSrc {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            systemEventRunLoopSrc = nil
        }
    }

    /// NSEvent 版本的 unlock 匹配（NSEvent.modifierFlags 比 CGEventFlags 少几位，单独写）
    private func unlockHotKeyMatchFromNSEvent(_ ev: NSEvent) -> Bool {
        guard let preset = LockHotKeySettings.presets.first(where: { $0.id == LockHotKeySettings.shared.currentId }),
              preset.keyCode >= 0 else { return false }
        if Int(ev.keyCode) != preset.keyCode { return false }
        var expected: NSEvent.ModifierFlags = []
        let cm = preset.modifiers
        if cm & Int(cmdKey)     != 0 { expected.insert(.command) }
        if cm & Int(shiftKey)   != 0 { expected.insert(.shift) }
        if cm & Int(optionKey)  != 0 { expected.insert(.option) }
        if cm & Int(controlKey) != 0 { expected.insert(.control) }
        let actual = ev.modifierFlags.intersection([.command, .shift, .option, .control])
        return actual == expected
    }

    /// 解锁快捷键的 keyCode + Carbon mods → CGEventFlags
    private func unlockHotKeyMatch(_ keyCode: Int, _ flags: CGEventFlags) -> Bool {
        guard let preset = LockHotKeySettings.presets.first(where: { $0.id == LockHotKeySettings.shared.currentId }),
              preset.keyCode >= 0 else { return false }
        if Int(keyCode) != preset.keyCode { return false }
        // 把 Carbon mods 转 CGEvent flags 比较
        var expected: CGEventFlags = []
        let cm = preset.modifiers
        if cm & Int(cmdKey)     != 0 { expected.insert(.maskCommand) }
        if cm & Int(shiftKey)   != 0 { expected.insert(.maskShift) }
        if cm & Int(optionKey)  != 0 { expected.insert(.maskAlternate) }
        if cm & Int(controlKey) != 0 { expected.insert(.maskControl) }
        let actual = flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl])
        return actual == expected
    }

    /// CGEventTap 回调主体：解锁快捷键放行，其它一律吞
    private func systemEventCallback(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // ★ macOS 会在 callback 处理时间过长时自动禁用 tap，必须立刻 re-enable，
        //   否则 tap 之后再也不工作（解锁键也透传不了，但其它键也不会被吞）
        if type.rawValue == 0xFFFFFFFE /* kCGEventTapDisabledByTimeout */
            || type.rawValue == 0xFFFFFFFF /* kCGEventTapDisabledByUserInput */ {
            if let tap = systemEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                AppLog.log("Mask CGEventTap re-enabled (was auto-disabled type=\(type.rawValue))")
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown, .keyUp:
            let kc = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if unlockHotKeyMatch(kc, event.flags) {
                // ★ 直接在这里触发 toggle —— 不再依赖 Carbon hot key（它在 Sequoia
                //   下偶尔被 mask window 的 key 焦点"吃掉"）。事件本身仍然吞掉，
                //   防止 1/⌥1 进文本框
                if type == .keyDown {
                    DispatchQueue.main.async { [weak self] in self?.toggle() }
                }
                return nil
            }
            // 其它键全吞
            if type == .keyDown { recordViolation() }
            return nil
        case .flagsChanged:
            // 修饰键变化（按下 ⌥/⌘ 等）放行 —— 否则 Carbon 收不到完整组合
            return Unmanaged.passUnretained(event)
        case .scrollWheel,
             .mouseMoved,
             .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            return nil   // 鼠标 / 触摸板 全吞
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    fileprivate func applySettings() {
        for w in windows {
            (w.contentView as? MaskContentView)?.applyStyle()
        }
    }
}

// MARK: - 可成为 Key 的 borderless 窗口（让 SecureTextField 能拿到键盘）

final class MaskWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 遮罩内容视图

private final class MaskContentView: NSView {

    private let blur = NSVisualEffectView()
    private let dim = NSView()
    private let clockLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let taskLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    // ★ 全屏红色 "Look My 👀" 警告（违规 ≥3 次时弹）
    private let lookMyLabel = NSTextField(labelWithString: "Look My 👀")
    private var lookMyHideTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        // ★ 兜底层透明 —— 这样 0% 透明度时能真的看穿整个 mask（仅拦截鼠标 / 键盘，
        //   屏幕内容对外可见）。具体黑暗强度由 dim 单独控制，跟 alpha 走。
        layer?.backgroundColor = NSColor.clear.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        // 1. 底层毛玻璃
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)

        // 2. 黑色暗化
        dim.wantsLayer = true
        dim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dim)

        // 3. 前景：时钟 / 日期 / 任务 / 提示
        for lbl in [clockLabel, dateLabel, taskLabel, hintLabel] {
            lbl.isBezeled = false
            lbl.drawsBackground = false
            lbl.isEditable = false
            lbl.alignment = .center
            lbl.translatesAutoresizingMaskIntoConstraints = false
            addSubview(lbl)
        }
        // ★ Style B：右下角文字用暖奶油色，跟整 app 调一致
        clockLabel.textColor = LazyCatTheme.maskCream
        dateLabel.textColor  = LazyCatTheme.maskCream.withAlphaComponent(0.7)
        taskLabel.textColor  = LazyCatTheme.maskCream.withAlphaComponent(0.95)
        taskLabel.maximumNumberOfLines = 2
        taskLabel.lineBreakMode = .byTruncatingTail

        hintLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.stringValue = ""    // 由 refresh() 填快捷键提示

        // ── 约束 ──
        // ★ 时钟 / 日期 / 任务 全部移到 **右下角**，字号也改小
        clockLabel.alignment = .right
        dateLabel.alignment  = .right
        taskLabel.alignment  = .right

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),

            dim.leadingAnchor.constraint(equalTo: leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: trailingAnchor),
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor),

            // 任务 — 右下角最底部
            taskLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            taskLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),
            taskLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),

            // 日期 — 任务上方
            dateLabel.trailingAnchor.constraint(equalTo: taskLabel.trailingAnchor),
            dateLabel.bottomAnchor.constraint(equalTo: taskLabel.topAnchor, constant: -2),

            // 时钟 — 日期上方
            clockLabel.trailingAnchor.constraint(equalTo: dateLabel.trailingAnchor),
            clockLabel.bottomAnchor.constraint(equalTo: dateLabel.topAnchor, constant: 0),

            // 提示行（已不使用，留空挂在右下）
            hintLabel.trailingAnchor.constraint(equalTo: clockLabel.trailingAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: clockLabel.topAnchor),
        ])

        applyStyle()
        refresh()
    }

    /// 应用 MaskSettings（透明度 + 字号）
    /// alpha = 0 →【外人能看见屏幕但不能操作】：毛玻璃 + 暗化层全部隐藏，仅保留输入拦截
    /// alpha = 1 → 全暖棕磨砂彻底盖住
    /// ★ Style B：暗化层用暖深棕（#2c1810）而不是纯黑，跟 app 暖橙基调一致
    func applyStyle() {
        let s = MaskSettings.shared
        let a = s.alpha   // 0..1
        dim.layer?.backgroundColor = LazyCatTheme.maskDark.withAlphaComponent(a).cgColor
        // 毛玻璃强度跟 alpha 走 —— 0% 时整个 NSVisualEffectView 透明，桌面清晰可见
        blur.alphaValue = a
        let fs = s.fontSize
        clockLabel.font = .monospacedDigitSystemFont(ofSize: fs.clockSize, weight: .thin)
        dateLabel.font  = .systemFont(ofSize: fs.dateSize,  weight: .light)
        taskLabel.font  = .systemFont(ofSize: fs.taskSize,  weight: .regular)
        needsLayout = true
    }

    func refresh() {
        let now = Date()
        let tf = DateFormatter()
        tf.locale = Locale.current
        tf.dateFormat = "HH:mm"
        clockLabel.stringValue = tf.string(from: now)

        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        dateLabel.stringValue = df.string(from: now)

        let top = Store.shared.data.tasks
            .filter { !$0.completed }
            .sorted { a, b in
                if a.priority.rawValue != b.priority.rawValue {
                    return a.priority.rawValue > b.priority.rawValue
                }
                return a.createdAt < b.createdAt
            }
            .first

        if let t = top {
            let prefix: String
            switch t.priority {
            case .top: prefix = "🔴 T0 · "
            case .mid: prefix = "🟠 T1 · "
            case .low: prefix = "🟢 T2 · "
            case .none: prefix = "• "
            }
            let text = t.text.isEmpty ? "(仅图片)" : t.text
            taskLabel.stringValue = prefix + text
        } else {
            taskLabel.stringValue = "✨ 没有待办 — 尽情休息"
        }

        // ★ 不再显示任何快捷键提示
        //   用户初衷是"防偷"：让陌生人看到屏幕也无法知道怎么解锁
        hintLabel.stringValue = ""
    }

    // 鼠标 / 触摸板 交互全部吞掉（必须靠快捷键解锁）
    override func mouseDown(with event: NSEvent)        { /* 吞 */ }
    override func mouseUp(with event: NSEvent)          { /* 吞 */ }
    override func mouseDragged(with event: NSEvent)     { /* 吞 */ }
    override func rightMouseDown(with event: NSEvent)   { /* 吞 */ }
    override func rightMouseUp(with event: NSEvent)     { /* 吞 */ }
    override func otherMouseDown(with event: NSEvent)   { /* 吞 */ }
    override func scrollWheel(with event: NSEvent)      { /* 吞 */ }
    override func magnify(with event: NSEvent)          { /* 吞 */ }
    override func swipe(with event: NSEvent)            { /* 吞 */ }
    override func rotate(with event: NSEvent)           { /* 吞 */ }
    override func smartMagnify(with event: NSEvent)     { /* 吞 */ }
    override func beginGesture(with event: NSEvent)     { /* 吞 */ }
    override func endGesture(with event: NSEvent)       { /* 吞 */ }

    // MARK: - 全屏红色 "Look My 👀" 警告

    /// 违规 ≥3 次时调；在每个 mask 屏幕上中央闪一次 2 秒
    func flashLookMyWarning() {
        if lookMyLabel.superview == nil {
            lookMyLabel.isBezeled = false
            lookMyLabel.drawsBackground = false
            lookMyLabel.isEditable = false
            lookMyLabel.alignment = .center
            // 巨型字号 —— 屏幕宽 1920 ≈ 220pt 占半屏多
            lookMyLabel.font = .systemFont(ofSize: 220, weight: .black)
            lookMyLabel.textColor = NSColor.systemRed
            lookMyLabel.alphaValue = 0
            lookMyLabel.translatesAutoresizingMaskIntoConstraints = false
            // 黑色描边阴影 —— 即便 0% 遮罩、看见花花桌面也辨认得出来
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = 18
            lookMyLabel.shadow = shadow
            // 顶层（在所有时钟 / 任务 / blur / dim 之上）
            addSubview(lookMyLabel, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                lookMyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                lookMyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                lookMyLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.95),
            ])
        }

        // 每次触发都重置 hide timer（连击不会被前一次的渐隐打断）
        lookMyHideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.lookMyLabel.animator().alphaValue = 1.0
        }
        lookMyHideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.45
                self.lookMyLabel.animator().alphaValue = 0
            }
        }
    }
}
