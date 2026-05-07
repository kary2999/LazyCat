import AppKit
import Carbon.HIToolbox

/// 全局热键（不需要辅助功能权限）。注册后，无论 MyTodo 是否在前台都能响应。
/// 用 Carbon 的 RegisterEventHotKey —— 是 macOS 上最稳、权限最低的做法
final class GlobalHotKey {
    static let shared = GlobalHotKey()

    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x4D54444F), id: 1)  // 'MTDO'

    /// 注册一个全局热键。默认 ⌥⌘`。`keyCode` 用 `kVK_*` 常量，`carbonModifiers` 用 Carbon 位掩码（cmdKey/optionKey/shiftKey/controlKey）
    func register(keyCode: Int = kVK_ANSI_Grave,
                  carbonModifiers: Int = Int(optionKey | cmdKey),
                  action: @escaping () -> Void) {
        unregister()
        self.handler = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        // 装 event handler —— 用 GetEventDispatcherTarget 比 App target 更稳
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else { return noErr }
                var hkid = EventHotKeyID()
                GetEventParameter(eventRef,
                                  EventParamName(kEventParamDirectObject),
                                  EventParamType(typeEventHotKeyID),
                                  nil,
                                  MemoryLayout<EventHotKeyID>.size,
                                  nil,
                                  &hkid)
                let me = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                AppLog.log("GlobalHotKey.fired id=\(hkid.id)")
                if hkid.id == me.hotKeyID.id {
                    DispatchQueue.main.async { me.handler?() }
                }
                return noErr
            },
            1, &eventType, selfPtr, &handlerRef)
        AppLog.log("GlobalHotKey.InstallEventHandler status=\(installStatus)")

        var out: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode),
                                         UInt32(carbonModifiers),
                                         hotKeyID,
                                         GetEventDispatcherTarget(),
                                         0,
                                         &out)
        if status == noErr {
            self.ref = out
            AppLog.log("GlobalHotKey.register OK keyCode=\(keyCode) mods=\(carbonModifiers)")
        } else {
            AppLog.log("GlobalHotKey.register FAIL status=\(status) keyCode=\(keyCode) mods=\(carbonModifiers)")
        }
    }

    func unregister() {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
        handler = nil
    }
}
