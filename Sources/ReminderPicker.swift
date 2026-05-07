import AppKit

enum ReminderPreset: Int, CaseIterable {
    case in10min, in30min, in1h, in3h, tomorrow9, custom, none

    var label: String {
        switch self {
        case .in10min:   return "10 分钟后"
        case .in30min:   return "30 分钟后"
        case .in1h:      return "1 小时后"
        case .in3h:      return "3 小时后"
        case .tomorrow9: return "明早 9:00"
        case .custom:    return "自定义…"
        case .none:      return "不提醒"
        }
    }

    func resolve() -> Date? {
        let now = Date()
        switch self {
        case .in10min: return now.addingTimeInterval(10 * 60)
        case .in30min: return now.addingTimeInterval(30 * 60)
        case .in1h:    return now.addingTimeInterval(60 * 60)
        case .in3h:    return now.addingTimeInterval(3 * 60 * 60)
        case .tomorrow9:
            let cal = Calendar.current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
            var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
            comps.hour = 9; comps.minute = 0
            return cal.date(from: comps)
        default: return nil
        }
    }
}

enum ReminderPickerUI {
    /// 完整的提醒选择器：先弹预设菜单，选 "自定义" 才弹日期选择器
    static func present(current: Date?, anchor: NSView?, onPick: @escaping (Date?) -> Void) {
        let menu = NSMenu()
        for p in ReminderPreset.allCases {
            if p == .none && current == nil { continue }
            let item = NSMenuItem(title: p.label,
                                  action: #selector(ReminderMenuTarget.shared.tapped(_:)),
                                  keyEquivalent: "")
            item.target = ReminderMenuTarget.shared
            item.representedObject = PresetPick(preset: p, current: current, handler: onPick)
            menu.addItem(item)
        }
        if let a = anchor {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: a.bounds.maxY + 2), in: a)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    static func presentCustomPicker(current: Date?, onPick: @escaping (Date?) -> Void) {
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 280, height: 30))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.dateValue = current ?? Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        picker.minDate = Date()

        let alert = NSAlert()
        alert.messageText = "自定义提醒时间"
        alert.informativeText = "到点后发系统通知，悬浮小猫会抖动提醒"
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")
        if current != nil { alert.addButton(withTitle: "清除提醒") }
        alert.accessoryView = picker

        switch alert.runModal() {
        case .alertFirstButtonReturn: onPick(picker.dateValue)
        case .alertThirdButtonReturn: onPick(nil)
        default: break
        }
    }
}

struct PresetPick {
    let preset: ReminderPreset
    let current: Date?
    let handler: (Date?) -> Void
}

final class ReminderMenuTarget: NSObject {
    static let shared = ReminderMenuTarget()
    @objc func tapped(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? PresetPick else { return }
        switch info.preset {
        case .custom:
            ReminderPickerUI.presentCustomPicker(current: info.current, onPick: info.handler)
        case .none:
            info.handler(nil)
        default:
            if let d = info.preset.resolve() { info.handler(d) }
        }
    }
}
