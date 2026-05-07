import AppKit

/// QQ 宠物风小猫 —— **坐姿** + **举右手挥动** + 4 条腿全可见
/// 粗黑描边 · 大头 · 大眼 · 肉垫 · 摇尾巴 · 眨眼
enum CatRenderer {

    // ── 色板 ──
    private static let white     = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let outline   = CGColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 1)
    private static let bodyFill  = CGColor(red: 0.98, green: 0.96, blue: 0.94, alpha: 1)
    private static let bellyFill = CGColor(red: 0.96, green: 0.93, blue: 0.89, alpha: 1)
    private static let pinkEar   = CGColor(red: 1.00, green: 0.62, blue: 0.70, alpha: 1)
    private static let pinkNose  = CGColor(red: 0.95, green: 0.48, blue: 0.55, alpha: 1)
    private static let pinkCheek = CGColor(red: 1.00, green: 0.60, blue: 0.66, alpha: 0.45)
    private static let pinkPad   = CGColor(red: 1.00, green: 0.70, blue: 0.76, alpha: 1)
    private static let eyeBlack  = CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
    private static let eyeShine  = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let tailGrey  = CGColor(red: 0.82, green: 0.80, blue: 0.76, alpha: 1)

    private static func sw(_ u: CGFloat) -> CGFloat { max(1.6, u * 0.03) }

    // ═══ 公共 API ═══

    static func makeFrames(size: NSSize) -> [NSImage] {
        (0..<24).map { drawFrame(size: size, p: Double($0) / 24.0, i: $0) }
    }

    static func makeStatic(size: NSSize) -> NSImage {
        drawFrame(size: size, p: 0, i: 0)
    }

    /// Dock / Finder icon 专用：只画猫头（顶天立地 + 圆角底色 + 柔和阴影）
    /// 图标在缩小到 32/16pt 时仍可辨识
    static func makeAppIcon(size: NSSize) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        defer { img.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return img }
        ctx.setShouldAntialias(true)

        let u = min(size.width, size.height)
        // 粉蓝色圆角底（苹果风 squircle）
        let pad = u * 0.06
        let rect = CGRect(x: pad, y: pad, width: size.width - pad * 2, height: size.height - pad * 2)
        let radius = u * 0.22
        let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [CGColor(red: 1.00, green: 0.94, blue: 0.92, alpha: 1),
                                       CGColor(red: 1.00, green: 0.82, blue: 0.86, alpha: 1)] as CFArray,
                              locations: [0, 1])!
        ctx.saveGState()
        ctx.addPath(bgPath); ctx.clip()
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: size.height),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
        ctx.restoreGState()

        // 头部占画面中心偏上，大头大眼
        let cx = size.width / 2
        let cy = size.height * 0.48
        let hr = u * 0.34
        let sw = max(1.6, u * 0.03)

        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)

        // 耳朵
        drawEar(ctx, side: -1, hr: hr, sw: sw, flick: 0)
        drawEar(ctx, side:  1, hr: hr, sw: sw, flick: 0)

        // 脸
        fillStrokeE(ctx, CGRect(x: -hr, y: -hr * 0.92, width: hr * 2, height: hr * 1.84),
                    bodyFill, outline, sw)

        // 腮红
        ctx.setFillColor(pinkCheek)
        ctx.fillEllipse(in: CGRect(x: -hr * 0.78, y: -hr * 0.50, width: hr * 0.36, height: hr * 0.20))
        ctx.fillEllipse(in: CGRect(x:  hr * 0.42, y: -hr * 0.50, width: hr * 0.36, height: hr * 0.20))

        // 眼睛（静态，不眨）
        let eyeDX = hr * 0.36, eyeY = hr * 0.05
        drawEye(ctx, CGPoint(x: -eyeDX, y: eyeY), hr * 0.18, sw)
        drawEye(ctx, CGPoint(x:  eyeDX, y: eyeY), hr * 0.18, sw)

        // 鼻
        drawNose(ctx, CGPoint(x: 0, y: -hr * 0.18), hr * 0.11, sw)
        // 嘴
        drawMouth(ctx, CGPoint(x: 0, y: -hr * 0.32), hr * 0.22, sw)
        // 胡须
        drawWhiskers(ctx, hr, sw)

        ctx.restoreGState()
        return img
    }

    /// 为 .icns 生成 10 种尺寸的 PNG，写到 outDir，返回成功数
    @discardableResult
    static func writeIconSet(to outDir: URL) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)
        // iconutil 要求的命名
        let entries: [(name: String, px: Int)] = [
            ("icon_16x16.png",      16),
            ("icon_16x16@2x.png",   32),
            ("icon_32x32.png",      32),
            ("icon_32x32@2x.png",   64),
            ("icon_128x128.png",   128),
            ("icon_128x128@2x.png",256),
            ("icon_256x256.png",   256),
            ("icon_256x256@2x.png",512),
            ("icon_512x512.png",   512),
            ("icon_512x512@2x.png",1024),
        ]
        var ok = 0
        for e in entries {
            let img = makeAppIcon(size: NSSize(width: e.px, height: e.px))
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = outDir.appendingPathComponent(e.name)
            if (try? png.write(to: url)) != nil { ok += 1 }
        }
        return ok
    }

    // ═══ 核心渲染 ═══

    private static func drawFrame(size: NSSize, p: Double, i: Int) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
        ctx.setShouldAntialias(true)
        render(ctx, size, p, i)
        img.unlockFocus()
        return img
    }

    private static func render(_ ctx: CGContext, _ s: NSSize, _ p: Double, _ i: Int) {
        let u = min(s.width, s.height)
        let cx = s.width / 2
        let sw = sw(u)

        // ── 动画 ──
        let breathe   = cg(sin(p * .pi * 2) * 0.025)           // 轻微呼吸
        let headTilt  = cg(sin(p * .pi * 2) * 0.05)            // 头微倾
        let tailWag   = cg(sin(p * .pi * 3 + 0.3) * 0.55)     // 摇尾巴
        let earFlick  = cg(sin(p * .pi * 5) * 0.08)            // 耳朵抖
        let isBlink   = (i % 10 == 9)                           // 眨眼

        // 右手挥动角度：-20° ~ +40°（正弦波）
        let waveAngle = cg(sin(p * .pi * 4) * 0.55 + 0.35)    // 0..-0.2 ~ +0.9 rad

        // 坐姿：屁股贴底部，前爪在肚前
        let groundY = u * 0.06
        let bodyY   = groundY + u * 0.22                        // 身体中心

        // ═══════ 尾巴（最底层）═══════
        ctx.saveGState()
        ctx.translateBy(x: cx - u * 0.18, y: bodyY - u * 0.02)
        ctx.rotate(by: tailWag - 0.3)
        drawTail(ctx, u, sw)
        ctx.restoreGState()

        // ═══════ 后腿（向两侧摊开，坐姿）═══════
        // 左后腿
        drawSittingHindLeg(ctx, cx: cx, bodyY: bodyY, side: -1, u: u, sw: sw)
        // 右后腿
        drawSittingHindLeg(ctx, cx: cx, bodyY: bodyY, side: 1, u: u, sw: sw)

        // ═══════ 身体（圆胖，稍扁 = 坐着被压）═══════
        ctx.saveGState()
        ctx.translateBy(x: cx, y: bodyY)
        ctx.scaleBy(x: cg(1.0 - breathe), y: cg(1.0 + breathe))
        let bw = u * 0.34, bh = u * 0.28
        fillStrokeE(ctx, CGRect(x: -bw/2, y: -bh/2, width: bw, height: bh), bodyFill, outline, sw)
        // 肚皮
        let blyW = bw * 0.55, blyH = bh * 0.50
        ctx.setFillColor(bellyFill)
        ctx.fillEllipse(in: CGRect(x: -blyW/2, y: -blyH/2 - bh * 0.05, width: blyW, height: blyH))
        ctx.restoreGState()

        // ═══════ 左前腿（放在肚前，静止）═══════
        drawFrontLeg(ctx, cx: cx, bodyY: bodyY, side: -1, angle: -0.15, u: u, sw: sw)

        // ═══════ 右前腿（举起来挥手！）═══════
        drawWavingArm(ctx, cx: cx, bodyY: bodyY, angle: waveAngle, u: u, sw: sw)

        // ═══════ 头（大！）═══════
        let headY = bodyY + u * 0.28
        ctx.saveGState()
        ctx.translateBy(x: cx, y: headY)
        ctx.rotate(by: headTilt)

        let hr = u * 0.24

        // 耳朵
        drawEar(ctx, side: -1, hr: hr, sw: sw, flick: earFlick)
        drawEar(ctx, side:  1, hr: hr, sw: sw, flick: -earFlick * 0.7)

        // 脸
        fillStrokeE(ctx, CGRect(x: -hr, y: -hr * 0.92, width: hr * 2, height: hr * 1.84),
                    bodyFill, outline, sw)

        // 腮红
        ctx.setFillColor(pinkCheek)
        ctx.fillEllipse(in: CGRect(x: -hr * 0.78, y: -hr * 0.50, width: hr * 0.36, height: hr * 0.20))
        ctx.fillEllipse(in: CGRect(x:  hr * 0.42, y: -hr * 0.50, width: hr * 0.36, height: hr * 0.20))

        // 眼睛
        let eyeDX = hr * 0.36, eyeY = hr * 0.05
        if isBlink {
            drawBlinkEye(ctx, CGPoint(x: -eyeDX, y: eyeY), hr * 0.20, sw)
            drawBlinkEye(ctx, CGPoint(x:  eyeDX, y: eyeY), hr * 0.20, sw)
        } else {
            drawEye(ctx, CGPoint(x: -eyeDX, y: eyeY), hr * 0.15, sw)
            drawEye(ctx, CGPoint(x:  eyeDX, y: eyeY), hr * 0.15, sw)
        }

        // 鼻
        drawNose(ctx, CGPoint(x: 0, y: -hr * 0.16), hr * 0.09, sw)

        // 嘴
        drawMouth(ctx, CGPoint(x: 0, y: -hr * 0.28), hr * 0.20, sw)

        // 胡须
        drawWhiskers(ctx, hr, sw)

        ctx.restoreGState()
    }

    // ═══════════════════════════════════════
    // MARK: - 四肢
    // ═══════════════════════════════════════

    /// 坐姿后腿 —— 水平向外伸，脚丫可见
    private static func drawSittingHindLeg(_ ctx: CGContext, cx: CGFloat, bodyY: CGFloat,
                                            side: CGFloat, u: CGFloat, sw: CGFloat) {
        let legW = u * 0.08
        let legH = u * 0.065
        // 大腿（水平椭圆，从身体向外伸）
        let thighX = cx + side * u * 0.16
        let thighY = bodyY - u * 0.10
        let thighRect = CGRect(x: thighX - legW/2, y: thighY - legH/2, width: legW, height: legH)
        fillStrokeE(ctx, thighRect, bodyFill, outline, sw * 0.9)

        // 脚丫（圆，在大腿外端稍下）
        let pawX = cx + side * u * 0.22
        let pawY = bodyY - u * 0.16
        let pawR = u * 0.038
        let pawRect = CGRect(x: pawX - pawR, y: pawY - pawR * 0.6, width: pawR * 2, height: pawR * 1.5)
        fillStrokeE(ctx, pawRect, bodyFill, outline, sw * 0.8)
        // 肉垫
        let pr = pawR * 0.30
        ctx.setFillColor(pinkPad)
        ctx.fillEllipse(in: CGRect(x: pawX - pr, y: pawY - pr * 0.3, width: pr * 2, height: pr * 1.2))
    }

    /// 前腿（放在身前，微微弯曲）
    private static func drawFrontLeg(_ ctx: CGContext, cx: CGFloat, bodyY: CGFloat,
                                      side: CGFloat, angle: CGFloat, u: CGFloat, sw: CGFloat) {
        let shoulderX = cx + side * u * 0.13
        let shoulderY = bodyY + u * 0.06

        ctx.saveGState()
        ctx.translateBy(x: shoulderX, y: shoulderY)
        ctx.rotate(by: angle * side)

        let armLen = u * 0.14
        let armW = u * 0.06

        // 胳膊
        let armRect = CGRect(x: -armW/2, y: -armLen, width: armW, height: armLen)
        ctx.setFillColor(bodyFill)
        ctx.fill(armRect)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(sw * 0.9)
        ctx.stroke(armRect)

        // 爪子
        let pawR = u * 0.04
        let pawRect = CGRect(x: -pawR, y: -armLen - pawR * 0.7, width: pawR * 2, height: pawR * 1.5)
        fillStrokeE(ctx, pawRect, bodyFill, outline, sw * 0.8)
        let pr = pawR * 0.30
        ctx.setFillColor(pinkPad)
        ctx.fillEllipse(in: CGRect(x: -pr, y: -armLen - pr * 0.2, width: pr * 2, height: pr * 1.2))

        ctx.restoreGState()
    }

    /// 右手挥动！张开的小爪子
    private static func drawWavingArm(_ ctx: CGContext, cx: CGFloat, bodyY: CGFloat,
                                       angle: CGFloat, u: CGFloat, sw: CGFloat) {
        let shoulderX = cx + u * 0.14
        let shoulderY = bodyY + u * 0.08

        ctx.saveGState()
        ctx.translateBy(x: shoulderX, y: shoulderY)
        ctx.rotate(by: angle)

        let armLen = u * 0.16
        let armW = u * 0.06

        // 上臂
        let armRect = CGRect(x: -armW/2, y: 0, width: armW, height: armLen)
        ctx.setFillColor(bodyFill)
        ctx.fill(armRect)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(sw * 0.9)
        ctx.stroke(armRect)

        // 张开的爪子（五个小圆 = 掌 + 4 指）—— QQ 宠物标志性大手
        let palmR = u * 0.045
        let palmY = armLen + palmR * 0.3
        // 掌心
        fillStrokeE(ctx, CGRect(x: -palmR, y: palmY - palmR, width: palmR * 2, height: palmR * 2),
                    bodyFill, outline, sw * 0.7)
        ctx.setFillColor(pinkPad)
        ctx.fillEllipse(in: CGRect(x: -palmR * 0.5, y: palmY - palmR * 0.5,
                                    width: palmR, height: palmR))
        // 4 根手指
        let fingerR = palmR * 0.35
        let angles: [CGFloat] = [-0.5, -0.15, 0.15, 0.5]
        for a in angles {
            let fx = palmR * 0.85 * sin(a) * 1.6
            let fy = palmY + palmR * 0.85 * cos(a)
            fillStrokeE(ctx, CGRect(x: fx - fingerR, y: fy - fingerR,
                                     width: fingerR * 2, height: fingerR * 2),
                        bodyFill, outline, sw * 0.5)
            // 指尖粉
            let tr = fingerR * 0.55
            ctx.setFillColor(pinkPad)
            ctx.fillEllipse(in: CGRect(x: fx - tr, y: fy - tr, width: tr * 2, height: tr * 2))
        }

        ctx.restoreGState()
    }

    // ═══════════════════════════════════════
    // MARK: - 头部元素
    // ═══════════════════════════════════════

    private static func drawEar(_ ctx: CGContext, side: CGFloat, hr: CGFloat, sw: CGFloat, flick: CGFloat) {
        let tipX = side * hr * 0.60
        let tipY = hr * 1.10 + abs(flick) * hr * 0.15
        let b1 = CGPoint(x: side * hr * 0.12, y: hr * 0.58)
        let b2 = CGPoint(x: side * hr * 0.84, y: hr * 0.48)
        let tip = CGPoint(x: tipX, y: tipY)

        let path = CGMutablePath()
        path.move(to: b1)
        path.addQuadCurve(to: tip, control: CGPoint(x: (b1.x + tip.x)/2 - side * 1.5, y: tip.y + 2))
        path.addQuadCurve(to: b2, control: CGPoint(x: (tip.x + b2.x)/2 + side * 1.5, y: tip.y + 2))
        path.closeSubpath()

        ctx.setFillColor(bodyFill); ctx.addPath(path); ctx.fillPath()
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw); ctx.addPath(path); ctx.strokePath()

        // 内耳粉
        let cxE = (b1.x + b2.x + tip.x) / 3, cyE = (b1.y + b2.y + tip.y) / 3
        let f: CGFloat = 0.48
        let inner = CGMutablePath()
        inner.move(to: lp(b1, cxE, cyE, f))
        inner.addQuadCurve(to: lp(tip, cxE, cyE, f),
                           control: CGPoint(x: (lp(b1, cxE, cyE, f).x + lp(tip, cxE, cyE, f).x)/2,
                                            y: lp(tip, cxE, cyE, f).y + 1))
        inner.addQuadCurve(to: lp(b2, cxE, cyE, f),
                           control: CGPoint(x: (lp(tip, cxE, cyE, f).x + lp(b2, cxE, cyE, f).x)/2,
                                            y: lp(tip, cxE, cyE, f).y + 1))
        inner.closeSubpath()
        ctx.setFillColor(pinkEar); ctx.addPath(inner); ctx.fillPath()
    }

    private static func drawEye(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat, _ sw: CGFloat) {
        let rect = CGRect(x: c.x - r, y: c.y - r * 1.15, width: r * 2, height: r * 2.3)
        ctx.setFillColor(white); ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.9); ctx.strokeEllipse(in: rect)
        // 瞳
        let pr = r * 0.70
        ctx.setFillColor(eyeBlack)
        ctx.fillEllipse(in: CGRect(x: c.x - pr, y: c.y - pr, width: pr * 2, height: pr * 2))
        // 大高光
        ctx.setFillColor(eyeShine)
        ctx.fillEllipse(in: CGRect(x: c.x + r * 0.05, y: c.y + r * 0.20,
                                    width: r * 0.58, height: r * 0.48))
        // 小高光
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.48, y: c.y - r * 0.40,
                                    width: r * 0.26, height: r * 0.22))
    }

    private static func drawBlinkEye(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ sw: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x - w, y: c.y))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y),
                       control: CGPoint(x: c.x, y: c.y - w * 0.55))
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 1.2); ctx.setLineCap(.round)
        ctx.addPath(p); ctx.strokePath()
    }

    private static func drawNose(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ sw: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x - w, y: c.y + w * 0.3))
        p.addLine(to: CGPoint(x: c.x + w, y: c.y + w * 0.3))
        p.addQuadCurve(to: CGPoint(x: c.x - w, y: c.y + w * 0.3),
                       control: CGPoint(x: c.x, y: c.y - w * 1.3))
        p.closeSubpath()
        ctx.setFillColor(pinkNose); ctx.addPath(p); ctx.fillPath()
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.6); ctx.addPath(p); ctx.strokePath()
    }

    private static func drawMouth(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ sw: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x - w, y: c.y))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + w * 0.10),
                       control: CGPoint(x: c.x - w * 0.5, y: c.y - w * 0.25))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y),
                       control: CGPoint(x: c.x + w * 0.5, y: c.y - w * 0.25))
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.8)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(p); ctx.strokePath()
    }

    private static func drawWhiskers(_ ctx: CGContext, _ hr: CGFloat, _ sw: CGFloat) {
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.55); ctx.setLineCap(.round)
        for side: CGFloat in [-1, 1] {
            for (dy, curve): (CGFloat, CGFloat) in [(-0.04, 0.06), (-0.15, 0), (-0.26, -0.05)] {
                let o = CGPoint(x: side * hr * 0.48, y: hr * dy)
                let e = CGPoint(x: side * hr * 1.12, y: hr * dy + curve * hr)
                let c = CGPoint(x: (o.x + e.x) / 2, y: o.y + hr * 0.03 * side)
                let p = CGMutablePath()
                p.move(to: o); p.addQuadCurve(to: e, control: c)
                ctx.addPath(p); ctx.strokePath()
            }
        }
    }

    // ═══ 尾巴 ═══

    private static func drawTail(_ ctx: CGContext, _ u: CGFloat, _ sw: CGFloat) {
        let len = u * 0.28
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addCurve(to: CGPoint(x: -len * 0.6, y: len * 0.8),
                      control1: CGPoint(x: -len * 0.5, y: -len * 0.15),
                      control2: CGPoint(x:  len * 0.1, y: len * 0.65))
        // 粗白底
        ctx.setStrokeColor(bodyFill); ctx.setLineWidth(u * 0.06); ctx.setLineCap(.round)
        ctx.addPath(path); ctx.strokePath()
        // 尾尖灰
        let tip = CGMutablePath()
        tip.move(to: CGPoint(x: -len * 0.25, y: len * 0.50))
        tip.addCurve(to: CGPoint(x: -len * 0.6, y: len * 0.8),
                     control1: CGPoint(x: -len * 0.05, y: len * 0.55),
                     control2: CGPoint(x: -len * 0.35, y: len * 0.82))
        ctx.setStrokeColor(tailGrey); ctx.setLineWidth(u * 0.05)
        ctx.addPath(tip); ctx.strokePath()
        // 描边
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw)
        ctx.addPath(path); ctx.strokePath()
    }

    // ═══ 工具 ═══

    private static func fillStrokeE(_ ctx: CGContext, _ r: CGRect,
                                     _ fill: CGColor, _ stroke: CGColor, _ sw: CGFloat) {
        ctx.setFillColor(fill); ctx.fillEllipse(in: r)
        ctx.setStrokeColor(stroke); ctx.setLineWidth(sw); ctx.strokeEllipse(in: r)
    }

    private static func cg(_ v: Double) -> CGFloat { CGFloat(v) }
    private static func lp(_ pt: CGPoint, _ cx: CGFloat, _ cy: CGFloat, _ f: CGFloat) -> CGPoint {
        CGPoint(x: cx + (pt.x - cx) * f, y: cy + (pt.y - cy) * f)
    }
}
