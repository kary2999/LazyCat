import AppKit

/// NSTextView 的克制版：
///  - 粘贴板里有图片，就不嵌到正文里，转给外部（缩略条）
///  - 纯文本一律按"当前主题"的 labelColor 插入，避免 Dark Mode 下黑字黑底看不见
final class PasteAwareTextView: NSTextView {
    var onPasteImages: (([NSImage]) -> Void)?

    // MARK: Paste

    override func paste(_ sender: Any?) {
        if extractAndForwardImages() { return }
        pasteAsPlainText(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        if extractAndForwardImages() { return }
        pasteAsPlainText(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if extractAndForwardImages() { return }
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string) else { return }
        insertPlainTextAtSelection(s)
    }

    // 注意：不要重写 insertText(_:replacementRange:) —— 苹果框架内部调用时
    // 可能传 {NSNotFound, 0}，重写后很容易把键盘输入"吞掉"。保持系统默认即可，
    // 深色模式下的文字颜色依靠 typingAttributes + textDidChange 保底。

    private func insertPlainTextAtSelection(_ raw: String) {
        let sel = selectedRange()
        guard shouldChangeText(in: sel, replacementString: raw) else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: self.font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        textStorage?.replaceCharacters(in: sel, with: NSAttributedString(string: raw, attributes: attrs))
        didChangeText()
    }

    private func extractAndForwardImages() -> Bool {
        let pb = NSPasteboard.general
        var images: [NSImage] = []
        if let objs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            images.append(contentsOf: objs)
        }
        if images.isEmpty,
           let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for u in urls {
                if let img = NSImage(contentsOf: u), img.isValid { images.append(img) }
            }
        }
        guard !images.isEmpty else { return false }
        onPasteImages?(images)
        return true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            var imgs: [NSImage] = []
            for u in urls {
                if let img = NSImage(contentsOf: u), img.isValid { imgs.append(img) }
            }
            if !imgs.isEmpty { onPasteImages?(imgs); return true }
        }
        if let objs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           !objs.isEmpty {
            onPasteImages?(objs); return true
        }
        return super.performDragOperation(sender)
    }

    // MARK: Appearance change → 重新着色已有内容

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColorsForCurrentAppearance()
    }

    func refreshColorsForCurrentAppearance() {
        textColor = .labelColor
        insertionPointColor = .labelColor
        backgroundColor = .textBackgroundColor
        typingAttributes = [
            .font: self.font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        guard let storage = textStorage, storage.length > 0 else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
    }
}
