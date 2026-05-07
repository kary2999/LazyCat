import AppKit

/// 点击任务行缩略图后弹出的图片查看窗口：滚轮缩放、拖动平移、方向键切换多图
final class ImageViewerController: NSWindowController {
    private static var shared: ImageViewerController?

    private let imageView = NSImageView()
    private let scrollView = NSScrollView()
    private let prevBtn = NSButton(title: "◀ 上一张", target: nil, action: nil)
    private let nextBtn = NSButton(title: "下一张 ▶", target: nil, action: nil)
    private let counter = NSTextField(labelWithString: "")

    private var imageNames: [String] = []
    private var index = 0

    static func present(imageNames: [String], startAt: Int = 0) {
        guard !imageNames.isEmpty else { return }
        let ctl = shared ?? ImageViewerController()
        shared = ctl
        ctl.imageNames = imageNames
        ctl.index = max(0, min(startAt, imageNames.count - 1))
        ctl.loadContentIfNeeded()
        ctl.showCurrent()
        ctl.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadContentIfNeeded() {
        if window != nil { return }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        w.title = "图片"
        w.isReleasedWhenClosed = false
        w.center()

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.documentView = imageView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.backgroundColor = .black
        scrollView.drawsBackground = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        prevBtn.bezelStyle = .rounded
        prevBtn.target = self
        prevBtn.action = #selector(showPrev)
        prevBtn.keyEquivalent = String(unichar(NSLeftArrowFunctionKey)).isEmpty ? "" : ""

        nextBtn.bezelStyle = .rounded
        nextBtn.target = self
        nextBtn.action = #selector(showNext)

        counter.font = .systemFont(ofSize: 12)
        counter.textColor = .secondaryLabelColor
        counter.alignment = .center

        let toolbar = NSStackView(views: [prevBtn, counter, nextBtn])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 10
        toolbar.distribution = .equalCentering
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(scrollView)
        root.addSubview(toolbar)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -8),

            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            toolbar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            toolbar.heightAnchor.constraint(equalToConstant: 28),
        ])
        w.contentView = root
        self.window = w
    }

    private func showCurrent() {
        guard imageNames.indices.contains(index) else { return }
        let name = imageNames[index]
        if let img = Store.shared.loadImage(named: name) {
            imageView.image = img
            // 让 imageView 自适应图片尺寸，然后 scrollView 可以滚动
            imageView.frame = NSRect(origin: .zero, size: img.size)
            scrollView.magnification = 1.0
            // 居中展示
            if let clip = scrollView.contentView as NSClipView? {
                let docRect = imageView.frame
                let visible = clip.bounds
                let x = max(0, (docRect.width - visible.width) / 2)
                let y = max(0, (docRect.height - visible.height) / 2)
                clip.scroll(to: NSPoint(x: x, y: y))
                scrollView.reflectScrolledClipView(clip)
            }
        }
        counter.stringValue = "\(index + 1) / \(imageNames.count)"
        prevBtn.isEnabled = index > 0
        nextBtn.isEnabled = index < imageNames.count - 1
    }

    @objc private func showPrev() {
        if index > 0 { index -= 1; showCurrent() }
    }
    @objc private func showNext() {
        if index < imageNames.count - 1 { index += 1; showCurrent() }
    }
}
