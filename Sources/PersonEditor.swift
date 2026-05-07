import AppKit

/// 弹窗编辑"人名"——带历史模糊提示，空串会被拒绝（保持必填语义）
enum PersonEditor {

    /// 弹出一个带 NSComboBox 的 modal alert；确认后把新人名回调出去
    /// - Parameter current: 当前人名，为 "" 或 nil 时视作未填
    static func present(anchorWindow: NSWindow? = nil,
                        current: String,
                        onCommit: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = current.isEmpty ? "补填 @人名" : "修改 @人名"
        alert.informativeText = "人名是必填项，可从历史中选一个。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        combo.placeholderString = "人名（必填）"
        combo.usesDataSource = true
        let ds = HistoryDS()
        combo.dataSource = ds
        combo.completes = true
        combo.numberOfVisibleItems = 8
        combo.stringValue = current
        // keep dataSource alive during modal
        objc_setAssociatedObject(combo, &Self.dsKey, ds, .OBJC_ASSOCIATION_RETAIN)

        alert.accessoryView = combo
        alert.window.initialFirstResponder = combo

        let resp: NSApplication.ModalResponse
        if let anchor = anchorWindow {
            resp = alert.runModal()
            _ = anchor  // 目前不走 sheet；保持简单
        } else {
            resp = alert.runModal()
        }
        if resp == .alertFirstButtonReturn {
            let v = combo.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { onCommit(v) }
            else { NSSound.beep() }
        }
    }

    private static var dsKey: UInt8 = 0

    /// ComboBox 数据源：取 Store 历史，随输入模糊匹配
    private final class HistoryDS: NSObject, NSComboBoxDataSource, NSComboBoxDelegate {
        func numberOfItems(in comboBox: NSComboBox) -> Int {
            Store.shared.suggestPersons(for: comboBox.stringValue).count
        }
        func comboBox(_ comboBox: NSComboBox, objectValueForItemAt index: Int) -> Any? {
            let list = Store.shared.suggestPersons(for: comboBox.stringValue)
            return list.indices.contains(index) ? list[index] : nil
        }
    }
}
