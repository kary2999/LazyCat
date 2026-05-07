import AppKit
import Carbon.HIToolbox

/// 锁屏（专注遮罩）全局快捷键的可配置预设。
/// 几个常用组合给用户挑，避开 macOS 系统占用的（⌘空格、⌃↑、⌘Tab、⌘`、⌘Q 等）。
final class LockHotKeySettings {
    static let shared = LockHotKeySettings()

    static let didChangeNotification = Notification.Name("LockHotKey.didChange")

    struct Preset {
        let id: Int            // UserDefaults 持久化 + 菜单 tag
        let title: String      // 菜单显示
        let keyCode: Int       // kVK_*
        let modifiers: Int     // Carbon (cmdKey | optionKey | …)
    }

    /// 预设列表 —— 给用户多种组合自由选
    /// 全局热键 = Carbon RegisterEventHotKey（不需要辅助功能权限）
    /// 默认 ⌥1 在英文输入法下稳定生效；中文输入法下若被吃掉，可换成 ⌃⌥⌘1 这类带多修饰符的更稳
    static let presets: [Preset] = [
        Preset(id: 0,  title: "⌥ 1（默认）",         keyCode: kVK_ANSI_1,         modifiers: Int(optionKey)),
        Preset(id: 1,  title: "⌥ 2",                keyCode: kVK_ANSI_2,         modifiers: Int(optionKey)),
        Preset(id: 2,  title: "⌥ 3",                keyCode: kVK_ANSI_3,         modifiers: Int(optionKey)),
        Preset(id: 3,  title: "⌥ ⌘ 1",              keyCode: kVK_ANSI_1,         modifiers: Int(optionKey | cmdKey)),
        Preset(id: 4,  title: "⌃ ⌥ ⌘ 1",            keyCode: kVK_ANSI_1,         modifiers: Int(controlKey | optionKey | cmdKey)),
        Preset(id: 5,  title: "⌥ ⌘ `",              keyCode: kVK_ANSI_Grave,     modifiers: Int(optionKey | cmdKey)),
        Preset(id: 6,  title: "⌃ ⌥ ⌘ L",            keyCode: kVK_ANSI_L,         modifiers: Int(controlKey | optionKey | cmdKey)),
        Preset(id: 7,  title: "⇧ ⌘ L",              keyCode: kVK_ANSI_L,         modifiers: Int(shiftKey | cmdKey)),
        Preset(id: 8,  title: "⇧ ⌘ D",              keyCode: kVK_ANSI_D,         modifiers: Int(shiftKey | cmdKey)),
        Preset(id: 9,  title: "⌃ ⌥ ⌘ D",            keyCode: kVK_ANSI_D,         modifiers: Int(controlKey | optionKey | cmdKey)),
        Preset(id: 10, title: "⌥ ⌘ .",              keyCode: kVK_ANSI_Period,    modifiers: Int(optionKey | cmdKey)),
        Preset(id: 11, title: "⌃ ⌥ ⌘ \\",           keyCode: kVK_ANSI_Backslash, modifiers: Int(controlKey | optionKey | cmdKey)),
        Preset(id: 12, title: "F13",                keyCode: kVK_F13,            modifiers: 0),
        Preset(id: 13, title: "F14",                keyCode: kVK_F14,            modifiers: 0),
        Preset(id: 14, title: "F15",                keyCode: kVK_F15,            modifiers: 0),
        Preset(id: 99, title: "关闭（不绑定）",      keyCode: -1,                 modifiers: 0),
    ]

    private let key = "MyTodo.lockHotKeyPresetId"

    var currentId: Int {
        let v = UserDefaults.standard.object(forKey: key) as? Int ?? 0
        return v
    }

    var current: Preset {
        Self.presets.first { $0.id == currentId } ?? Self.presets[0]
    }

    func setCurrent(id: Int) {
        UserDefaults.standard.set(id, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
