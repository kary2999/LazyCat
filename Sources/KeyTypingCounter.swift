import AppKit
import IOKit.hid

extension Notification.Name {
    /// 每次全局 keyDown 时投递；observer 自己读 KeyTypingCounter.shared 取数
    static let typingKeyDown = Notification.Name("KeyTypingCounter.keyDown")
    /// 跨 0 点重置时投递
    static let typingDayChanged = Notification.Name("KeyTypingCounter.dayChanged")
}

/// 全局键盘按键计数器
///   · 监听 NSEvent global keyDown（需要"输入监控"权限）
///   · 每天用一个独立的 UserDefaults key 累加，**0 点自动切换 key 实现重置**
///     （旧的日期 key 留作历史；不会被覆盖）
///   · 维护"最近 3 秒"按键时间戳，用于判断 isTyping 状态
final class KeyTypingCounter {
    static let shared = KeyTypingCounter()
    private init() {}

    // MARK: - Public

    /// 今日累计按键数
    var todayCount: Int {
        UserDefaults.standard.integer(forKey: keyForToday())
    }

    /// 最近 3 秒按键数
    var recentCount: Int {
        prune()
        return recentTimestamps.count
    }

    /// 是否在"快速打字"状态（最近 3 秒 ≥ 2 次）
    var isTyping: Bool {
        recentCount >= 2
    }

    func start() {
        // ★ 启动即请求"输入监控"权限：
        //   - 首次：IOHIDRequestAccess 触发系统授权对话框
        //   - 之前已拒绝：弹一个 NSAlert 引导去系统设置（每日最多 1 次）
        ensurePermission()

        installMonitor()
        // 0 点检测线：每 30 秒看一眼日期变了没有；同时跨日时再申请一次权限
        let t = Timer(timeInterval: 30, target: self,
                      selector: #selector(checkDayChange),
                      userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        dayChangeTimer = t
        lastDayKey = keyForToday()
        // 启动时清一次超过保留期的旧数据
        purgeOldData()
        AppLog.log("KeyTypingCounter started, today=\(lastDayKey) count=\(todayCount)")
    }

    // MARK: - 权限

    private let lastPromptKey = "MyTodo.typingCounter.lastPermissionPromptISO"

    /// 当前权限状态（IOHIDCheckAccess 包装）
    var accessState: IOHIDAccessType {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    }

    /// 确保权限：
    ///   - granted ⇒ 啥也不做
    ///   - unknown ⇒ 主动调 IOHIDRequestAccess 触发系统对话框
    ///   - denied  ⇒ 弹 NSAlert 引导去系统设置；24h 内不再打扰（force=true 时无视 cooldown）
    /// 终极方案：tccutil 把 macOS 数据库里 LazyCat 的输入监控记录抹掉，
    /// 让系统重新把 LazyCat 视为"全新 app"再弹官方授权对话框。
    /// 解决 ad-hoc 签名重编后 binary hash 变了 → TCC 认不出 → 永远 Denied 的死结。
    func resetTCCAndRequest() {
        AppLog.log("KeyTypingCounter resetTCCAndRequest: tccutil reset ListenEvent com.local.mytodo")
        let task = Process()
        task.launchPath = "/usr/bin/tccutil"
        task.arguments = ["reset", "ListenEvent", "com.local.mytodo"]
        do {
            try task.run()
            task.waitUntilExit()
            AppLog.log("tccutil exit=\(task.terminationStatus)")
        } catch {
            AppLog.log("tccutil failed: \(error)")
        }
        // TCC 数据库刷一会儿
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            // 重新申请；现在系统会把它当成新 app，弹官方对话框
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            self?.ensurePermission(force: true)
        }
    }

    func ensurePermission(force: Bool = false) {
        let state = accessState
        AppLog.log("KeyTypingCounter accessState=\(state.rawValue) force=\(force)")

        switch state {
        case kIOHIDAccessTypeGranted:
            if force {
                // 用户手动点了"申请权限"但已经 granted —— 给个反馈
                let alert = NSAlert()
                alert.messageText = "已授权"
                alert.informativeText = "LazyCat 已经拥有「输入监控」权限。\n如果发现「今日打字」还显示 0，可以重启 LazyCat 让监听器重新注册。"
                alert.runModal()
            }
            return
        case kIOHIDAccessTypeUnknown:
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            AppLog.log("KeyTypingCounter requested access, immediate grant=\(granted)")
        case kIOHIDAccessTypeDenied:
            promptOpenSystemSettingsIfNotRecent(force: force)
        default:
            promptOpenSystemSettingsIfNotRecent(force: force)
        }
    }

    private func promptOpenSystemSettingsIfNotRecent(force: Bool = false) {
        // 每日最多 1 次（不到 23 小时不再弹），force=true 无视
        if !force {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
            let now = Date()
            if let lastStr = UserDefaults.standard.string(forKey: lastPromptKey),
               let last = df.date(from: lastStr),
               now.timeIntervalSince(last) < 23 * 3600 {
                AppLog.log("KeyTypingCounter prompt skipped (last=\(lastStr))")
                return
            }
            UserDefaults.standard.set(df.string(from: now), forKey: lastPromptKey)
        }
        DispatchQueue.main.async { Self.showPermissionAlert() }
    }

    private static func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要授权「输入监控」"
        alert.informativeText = """
        LazyCat 只统计每天按了多少次键，不记录具体内容。

        ━━━ 第一次设置 ━━━
        1. 点下方「打开输入监控面板」
        2. 在列表中勾选 LazyCat
        3. 退出 LazyCat 再重启（菜单栏猫 → 退出）

        ━━━ 已经勾选过但还是不生效（重装后最常见）━━━
        每次重编 LazyCat 的 binary 哈希都会变，macOS 旧授权失效但状态卡 Denied。

        正确修法：
        1. 「打开输入监控面板」
        2. 找到 LazyCat 那一条 → 点旁边的【—】把整条删掉
        3. 退出 LazyCat 再重启 → 系统会弹官方对话框 → 点「允许」
        4. 监听立即生效

        （每天最多提醒一次。一切信息可以从菜单栏猫图标 → 关于 LazyCat 看到）
        """
        alert.addButton(withTitle: "打开输入监控面板")
        alert.addButton(withTitle: "已知道")
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath:
                    "/System/Library/PreferencePanes/Security.prefPane"))
            }
        }
    }

    /// 打印一份完整诊断到 /tmp/mytodo.log，并返回多行字符串供 UI 展示
    static func diagnosticReport() -> String {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let stateName: String
        switch access {
        case kIOHIDAccessTypeGranted: stateName = "Granted (✓)"
        case kIOHIDAccessTypeDenied:  stateName = "Denied (✗) — 旧授权失效或被拒"
        case kIOHIDAccessTypeUnknown: stateName = "Unknown — 没记录，下次申请会弹对话框"
        default:                      stateName = "?(\(access.rawValue))"
        }

        // codesign 信息（前几行就够）
        let csTask = Process()
        csTask.launchPath = "/usr/bin/codesign"
        csTask.arguments = ["-dvvv", Bundle.main.bundlePath]
        let csPipe = Pipe()
        csTask.standardError = csPipe
        csTask.standardOutput = csPipe
        var csInfo = ""
        do {
            try csTask.run()
            csTask.waitUntilExit()
            let data = csPipe.fileHandleForReading.readDataToEndOfFile()
            if let s = String(data: data, encoding: .utf8) {
                csInfo = s.split(separator: "\n").prefix(8).joined(separator: "\n")
            }
        } catch {
            csInfo = "codesign error: \(error)"
        }

        let nsMon  = (KeyTypingCounter.shared.monitor != nil) ? "✓" : "✗"
        let cgTap  = (KeyTypingCounter.shared.eventTap != nil) ? "✓" : "✗"
        let today  = KeyTypingCounter.shared.todayCount
        let recent = KeyTypingCounter.shared.recentCount

        let report = """
        === LazyCat 输入监控诊断 ===
        TCC accessState   : \(access.rawValue) — \(stateName)
        NSEvent monitor   : \(nsMon)
        CGEventTap        : \(cgTap)
        今日按键          : \(today)（最近 3 秒：\(recent)）

        Bundle ID         : \(Bundle.main.bundleIdentifier ?? "?")
        Bundle 路径       : \(Bundle.main.bundlePath)
        可执行            : \(Bundle.main.executablePath ?? "?")

        --- codesign 标识 ---
        \(csInfo)
        """
        AppLog.log(report.replacingOccurrences(of: "\n", with: " | "))
        return report
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m); monitor = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        dayChangeTimer?.invalidate()
        dayChangeTimer = nil
    }

    // MARK: - Internals

    private var monitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dayChangeTimer: Timer?
    private var lastDayKey: String = ""
    private var recentTimestamps: [Date] = []
    private let recentWindow: TimeInterval = 3.0
    private let storageKeyPrefix = "MyTodo.typingCount."
    private let perKeyPrefix     = "MyTodo.typingByKey."   // [Int: Int] keyCode → count
    private let retentionDays    = 30                      // 最多保留 30 天数据

    /// 双重监听 —— 哪个能拿到事件就走哪个：
    ///   1. CGEventTap (.listenOnly)：底层 Quartz，需要 Input Monitoring 权限
    ///   2. NSEvent global monitor：高层 AppKit，同样需要 Input Monitoring 权限
    /// 用 dedupe 防止两个都成功时重复计数
    private func installMonitor() {
        installCGEventTap()
        installNSEventMonitor()
    }

    private func installNSEventMonitor() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            self?.handleKey(source: "NSEvent", keyCode: Int(ev.keyCode))
        }
        AppLog.log("KeyTypingCounter NSEvent monitor: \(monitor != nil)")
    }

    private func installCGEventTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon, type == .keyDown else {
                return Unmanaged.passUnretained(event)
            }
            let me = Unmanaged<KeyTypingCounter>.fromOpaque(refcon).takeUnretainedValue()
            let kc = Int(event.getIntegerValueField(.keyboardEventKeycode))
            me.handleKey(source: "CGEventTap", keyCode: kc)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo)
        else {
            AppLog.log("KeyTypingCounter CGEventTap: 创建失败（最常见原因：输入监控权限未给）")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        runLoopSource = source
        AppLog.log("KeyTypingCounter CGEventTap installed ✓")
    }

    /// 去重 —— CGEventTap 和 NSEvent 都触发时，只计一次（5ms 内的视为同一次）
    private var lastHandledAt: Date?
    private let dedupeWindow: TimeInterval = 0.005

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func dayString(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func keyForToday() -> String {
        storageKeyPrefix + dayString(Date())
    }

    private func perKeyKeyForToday() -> String {
        perKeyPrefix + dayString(Date())
    }

    /// 双 monitor 去重 + 计数 + 通知
    private func handleKey(source: String = "?", keyCode: Int = -1) {
        let now = Date()
        if let last = lastHandledAt, now.timeIntervalSince(last) < dedupeWindow {
            return   // 同一事件被两个 monitor 收到 → 跳过
        }
        lastHandledAt = now

        let key = keyForToday()
        let cur = UserDefaults.standard.integer(forKey: key)
        let newCount = cur + 1
        UserDefaults.standard.set(newCount, forKey: key)

        // 每键累加（仅在拿到合法 keyCode 时）
        if keyCode >= 0 {
            let pkKey = perKeyKeyForToday()
            var dict: [String: Int] = (UserDefaults.standard.dictionary(forKey: pkKey) as? [String: Int]) ?? [:]
            let kStr = String(keyCode)
            dict[kStr, default: 0] += 1
            UserDefaults.standard.set(dict, forKey: pkKey)
        }

        recentTimestamps.append(now)
        prune()

        NotificationCenter.default.post(name: .typingKeyDown, object: nil)

        // ★ 每打满 1000 字（1000、2000、3000…）→ 触发全屏烟花
        if newCount % 1000 == 0 {
            DispatchQueue.main.async {
                FireworksController.shared.celebrate(reason: "今日已敲 \(newCount) 键，干得漂亮！")
            }
        }
    }

    // MARK: - 历史数据查询 / 维护

    /// 返回最近 N 天的总数序列：从 N-1 天前 → 今天，长度 = days
    /// e.g. dailyCounts(days: 7) = [周一前, ..., 昨天, 今天]
    func dailyCounts(days: Int) -> [(date: Date, day: String, count: Int)] {
        var out: [(Date, String, Int)] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in (0..<days).reversed() {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayStr = dayString(d)
            let n = UserDefaults.standard.integer(forKey: storageKeyPrefix + dayStr)
            out.append((d, dayStr, n))
        }
        return out
    }

    /// 最近 days 天里，按键累计 Top N（合并多日）
    func topKeys(days: Int, limit: Int) -> [(keyCode: Int, count: Int)] {
        var merged: [Int: Int] = [:]
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for i in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let pkKey = perKeyPrefix + dayString(d)
            let dict = (UserDefaults.standard.dictionary(forKey: pkKey) as? [String: Int]) ?? [:]
            for (k, v) in dict {
                if let kc = Int(k) { merged[kc, default: 0] += v }
            }
        }
        return merged.sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (keyCode: $0.key, count: $0.value) }
    }

    /// 删除超过 retentionDays 的数据（每日 0 点后调）
    func purgeOldData() {
        let ud = UserDefaults.standard
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: -retentionDays, to: today) else { return }

        var removed = 0
        for (k, _) in ud.dictionaryRepresentation() {
            // 处理 totals 和 per-key dicts 两种 key
            let dayStrOpt: String?
            if k.hasPrefix(storageKeyPrefix) {
                dayStrOpt = String(k.dropFirst(storageKeyPrefix.count))
            } else if k.hasPrefix(perKeyPrefix) {
                dayStrOpt = String(k.dropFirst(perKeyPrefix.count))
            } else {
                dayStrOpt = nil
            }
            guard let dayStr = dayStrOpt,
                  let d = Self.dayFormatter.date(from: dayStr),
                  d < cutoff else { continue }
            ud.removeObject(forKey: k)
            removed += 1
        }
        if removed > 0 {
            AppLog.log("KeyTypingCounter purgeOldData: 删除了 \(removed) 个超过 \(retentionDays) 天的记录")
        }
    }

    @objc private func checkDayChange() {
        let now = keyForToday()
        if now != lastDayKey {
            AppLog.log("KeyTypingCounter dayChange: \(lastDayKey) → \(now)")
            lastDayKey = now
            recentTimestamps.removeAll()
            NotificationCenter.default.post(name: .typingDayChanged, object: nil)
            // 跨过 0 点：再确认一次权限（仍然没给的话会再提醒一次，每日最多 1 次）
            ensurePermission()
            // 顺手清理超过 retentionDays 的旧数据
            purgeOldData()
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-recentWindow)
        recentTimestamps.removeAll { $0 < cutoff }
    }

    // MARK: - keyCode → 可读名（macOS 虚拟键码，参考 Carbon Events.h）

    /// 将 macOS 虚拟键码转成可阅读的标签（"A"、"空格"、"⏎" 等）。
    /// 没匹配上时返回 "Key(\(kc))"
    static func label(for keyCode: Int) -> String {
        switch keyCode {
        // 字母（按 Carbon 虚拟键码）
        case 0:  return "A"
        case 11: return "B"
        case 8:  return "C"
        case 2:  return "D"
        case 14: return "E"
        case 3:  return "F"
        case 5:  return "G"
        case 4:  return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1:  return "S"
        case 17: return "T"
        case 32: return "U"
        case 9:  return "V"
        case 13: return "W"
        case 7:  return "X"
        case 16: return "Y"
        case 6:  return "Z"
        // 数字（主键盘）
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        // 符号
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 42: return "\\"
        case 50: return "`"
        // 控制键
        case 49: return "空格"
        case 36: return "⏎ Return"
        case 51: return "⌫ Delete"
        case 117:return "⌦ FwdDel"
        case 53: return "⎋ Esc"
        case 48: return "⇥ Tab"
        case 56,60: return "⇧ Shift"
        case 59,62: return "⌃ Control"
        case 58,61: return "⌥ Option"
        case 55,54: return "⌘ Command"
        case 57: return "⇪ Caps"
        case 63: return "fn"
        case 123:return "←"
        case 124:return "→"
        case 125:return "↓"
        case 126:return "↑"
        case 116:return "PageUp"
        case 121:return "PageDown"
        case 115:return "Home"
        case 119:return "End"
        // 功能键
        case 122:return "F1"
        case 120:return "F2"
        case 99: return "F3"
        case 118:return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100:return "F8"
        case 101:return "F9"
        case 109:return "F10"
        case 103:return "F11"
        case 111:return "F12"
        // 小键盘
        case 65: return "Num ."
        case 67: return "Num *"
        case 69: return "Num +"
        case 71: return "Num Clear"
        case 75: return "Num /"
        case 76: return "Num ⏎"
        case 78: return "Num -"
        case 81: return "Num ="
        case 82: return "Num 0"
        case 83: return "Num 1"
        case 84: return "Num 2"
        case 85: return "Num 3"
        case 86: return "Num 4"
        case 87: return "Num 5"
        case 88: return "Num 6"
        case 89: return "Num 7"
        case 91: return "Num 8"
        case 92: return "Num 9"
        default: return "Key(\(keyCode))"
        }
    }
}
