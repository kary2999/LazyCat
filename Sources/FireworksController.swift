import AppKit
import QuartzCore

/// 全屏烟花庆祝层 —— 每打满 1000 字触发一次
///   · 主屏全屏 borderless 窗口
///   · ignoresMouseEvents = true → **完全穿透**，鼠标键盘照常工作
///   · alphaValue = 0.10 → 10% 透明度，**不影响后续操作的视觉**
///   · CAEmitterLayer 多点烟花，约 5 秒后自动关闭
final class FireworksController {
    static let shared = FireworksController()
    private init() {}

    private var window: NSWindow?
    private var dismissTimer: Timer?

    func celebrate(reason: String) {
        // 已经在放就不叠加
        if window != nil { return }
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame

        let win = NSPanel(contentRect: frame,
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false,
                          screen: screen)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.alphaValue = 0.10                // ★ 10% 透明
        win.level = .screenSaver
        win.ignoresMouseEvents = true        // ★ 鼠标穿透
        win.isFloatingPanel = true
        win.becomesKeyOnlyIfNeeded = true
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.hasShadow = false

        let view = FireworksView(frame: NSRect(origin: .zero, size: frame.size))
        view.startCelebrate(reason: reason)
        win.contentView = view

        win.orderFrontRegardless()
        window = win

        // 5 秒后自动收
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
        AppLog.log("Fireworks: celebrate(\(reason))")
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        window?.orderOut(nil)
        window = nil
    }
}

// MARK: - 烟花画布

private final class FireworksView: NSView {

    private let palette: [NSColor] = [
        .systemRed, .systemYellow, .systemPink,
        .systemGreen, .systemBlue, .systemOrange, .systemPurple,
    ]
    private var dotImage: CGImage?

    func startCelebrate(reason: String) {
        wantsLayer = true
        layer?.masksToBounds = false
        dotImage = makeDotImage()

        // 中央祝贺标语
        let label = NSTextField(labelWithString: "🎉 \(reason) 🎉")
        label.font = .systemFont(ofSize: 56, weight: .heavy)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // 标语先放大再淡出
        label.wantsLayer = true
        label.layer?.opacity = 0
        let pop = CABasicAnimation(keyPath: "opacity")
        pop.fromValue = 0.0; pop.toValue = 1.0
        pop.duration = 0.4
        pop.fillMode = .forwards
        pop.isRemovedOnCompletion = false
        label.layer?.add(pop, forKey: "fadeIn")
        label.layer?.opacity = 1

        // 多点烟花，错开 0.3 秒触发
        let positions: [CGPoint] = (0..<8).map { i in
            CGPoint(x: bounds.width * (0.15 + 0.10 * CGFloat(i)),
                    y: bounds.height * (0.55 + 0.10 * CGFloat((i % 3) - 1)))
        }
        for (i, p) in positions.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) { [weak self] in
                self?.spawnFirework(at: p)
            }
        }
    }

    /// 在 (x,y) 触发一团烟花
    private func spawnFirework(at point: CGPoint) {
        guard let host = self.layer else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.emitterMode = .outline
        emitter.emitterSize = CGSize(width: 1, height: 1)
        emitter.renderMode = .additive

        let cell = CAEmitterCell()
        cell.contents = dotImage
        cell.birthRate = 0
        cell.lifetime = 1.6
        cell.velocity = 240
        cell.velocityRange = 100
        cell.emissionRange = .pi * 2     // 全方向爆开
        cell.yAcceleration = -160        // 重力下落
        cell.scale = 0.18
        cell.scaleRange = 0.08
        cell.alphaSpeed = -0.6           // 渐隐
        cell.spin = 1.5; cell.spinRange = 2.0

        // 颜色随机
        let c = palette.randomElement()!.cgColor
        cell.color = c
        cell.redRange = 0.4
        cell.greenRange = 0.4
        cell.blueRange = 0.4

        emitter.emitterCells = [cell]
        host.addSublayer(emitter)

        // 50ms 内爆发 → 然后停止生成（已生成的粒子继续飞 + 衰减）
        DispatchQueue.main.async {
            cell.birthRate = 600
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                cell.birthRate = 0
            }
        }
        // 2 秒后清掉这层 emitter
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            emitter.removeFromSuperlayer()
        }
    }

    /// 一个发光圆点 PNG，作为烟花粒子的纹理
    private func makeDotImage() -> CGImage? {
        let size: CGFloat = 12
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        defer { img.unlockFocus() }
        let ctx = NSGraphicsContext.current?.cgContext
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        // 中心亮 → 边缘暗 的径向渐变
        let space = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 1, green: 1, blue: 1, alpha: 1.0),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray
        let grad = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        ctx?.drawRadialGradient(
            grad,
            startCenter: CGPoint(x: size/2, y: size/2), startRadius: 0,
            endCenter:   CGPoint(x: size/2, y: size/2), endRadius:   size/2,
            options: [])
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
