import AppKit

/// QQ Q 版企鹅 —— 整体是个胖圆球：上 40% 黑色脸（眼睛+喙），下 60% 白肚子，
/// 黑白交界处一条红围巾。两侧翅膀向下伸，底部两个橙脚。
/// 动画：呼吸 / 右翅膀招手 / 周期眨眼 / 围巾尾巴飘。
enum PenguinRenderer {

    // ── 色板 ──
    private static let bodyBlack  = CGColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1)
    private static let bodyShade  = CGColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)
    private static let bellyWhite = CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
    private static let bellyShade = CGColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1)
    private static let outline    = CGColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1)

    private static let beak       = CGColor(red: 1.00, green: 0.65, blue: 0.16, alpha: 1)
    private static let beakDark   = CGColor(red: 0.85, green: 0.45, blue: 0.08, alpha: 1)

    private static let foot       = CGColor(red: 1.00, green: 0.62, blue: 0.16, alpha: 1)
    private static let footDark   = CGColor(red: 0.78, green: 0.42, blue: 0.08, alpha: 1)

    private static let scarfRed   = CGColor(red: 0.92, green: 0.18, blue: 0.20, alpha: 1)
    private static let scarfShade = CGColor(red: 0.72, green: 0.10, blue: 0.12, alpha: 1)

    private static let eyeWhite   = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let eyeBlack   = CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1)
    private static let cheekPink  = CGColor(red: 1.00, green: 0.62, blue: 0.66, alpha: 0.45)

    private static func sw(_ u: CGFloat) -> CGFloat { max(1.4, u * 0.020) }

    // ═══ 公共 API ═══

    static func makeFrames(size: NSSize) -> [NSImage] {
        (0..<24).map { drawFrame(size: size, p: Double($0) / 24.0, i: $0) }
    }

    static func makeStatic(size: NSSize) -> NSImage {
        drawFrame(size: size, p: 0, i: 0)
    }

    private static func drawFrame(size: NSSize, p: Double, i: Int) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }
        ctx.setShouldAntialias(true)
        render(ctx, size, p, i)
        img.unlockFocus()
        return img
    }

    // ═══ 核心渲染 ═══
    //
    // 坐标系：lockFocus 默认 y 向上递增。
    //   y = 0           最底部（脚底）
    //   y = size.height 最顶部（头顶）
    // ═══════════════════════════════════════

    private static func render(_ ctx: CGContext, _ s: NSSize, _ p: Double, _ i: Int) {
        let u = min(s.width, s.height)
        let cx = s.width / 2
        let strokeW = sw(u)

        // 动画
        let breathe   = CGFloat(sin(p * .pi * 2) * 0.018)
        let scarfFlow = CGFloat(sin(p * .pi * 4) * 0.30)
        let isBlink   = (i == 9 || i == 21)
        let waveAngle = CGFloat(sin(p * .pi * 4) * 0.55 + 0.55)   // 0..1.1 rad

        // ── 关键尺寸 ──
        // 圆球身体：尽量胖，留出底部脚的空间和顶部空气
        let bodyW    = u * 0.66
        let bodyH    = u * 0.74
        let bodyBot  = u * 0.13                     // 身体底部 y（让脚露出来）
        let bodyTop  = bodyBot + bodyH              // 身体顶部 y
        let bodyCx   = cx
        let bodyCy   = bodyBot + bodyH / 2

        // 头/脸 = 身体上 40%
        // 黑白交界线（围巾位置）= bodyCy 上方一点
        let scarfY   = bodyCy + bodyH * 0.10        // 黑白交界

        // ═══════ 1. 双脚（最底层）═══════
        drawFoot(ctx, cx: cx - u * 0.13, y: bodyBot - u * 0.04, u: u, sw: strokeW)
        drawFoot(ctx, cx: cx + u * 0.13, y: bodyBot - u * 0.04, u: u, sw: strokeW)

        // ═══════ 2. 黑色身体（整圆球）═══════
        ctx.saveGState()
        ctx.translateBy(x: bodyCx, y: bodyCy)
        ctx.scaleBy(x: 1.0 - breathe, y: 1.0 + breathe)
        let bodyRect = CGRect(x: -bodyW/2, y: -bodyH/2, width: bodyW, height: bodyH)
        ctx.setFillColor(bodyBlack); ctx.fillEllipse(in: bodyRect)

        // 头顶左侧深色（光影）
        ctx.saveGState()
        ctx.addEllipse(in: bodyRect); ctx.clip()
        ctx.setFillColor(bodyShade)
        ctx.fillEllipse(in: CGRect(x: -bodyW * 0.55, y: bodyH * 0.05,
                                    width: bodyW * 0.55, height: bodyH * 0.6))
        ctx.restoreGState()

        // 描边
        ctx.setStrokeColor(outline); ctx.setLineWidth(strokeW * 0.5); ctx.strokeEllipse(in: bodyRect)
        ctx.restoreGState()

        // ═══════ 3. 白肚子（身体内的椭圆，黑色底裁切外的部分被遮）═══════
        // 肚子位置：从 scarfY 往下延伸到接近底部
        let bellyW = bodyW * 0.78
        let bellyH = (scarfY - bodyBot) * 1.65   // 从围巾到底部的范围扩一点
        let bellyCy = (scarfY + bodyBot) / 2 - u * 0.02
        let bellyRect = CGRect(x: bodyCx - bellyW/2, y: bellyCy - bellyH/2,
                                width: bellyW, height: bellyH)
        ctx.setFillColor(bellyWhite); ctx.fillEllipse(in: bellyRect)
        // 肚子右下淡阴影
        ctx.saveGState()
        ctx.addEllipse(in: bellyRect); ctx.clip()
        ctx.setFillColor(bellyShade)
        ctx.fillEllipse(in: CGRect(x: bodyCx - bellyW * 0.45, y: bellyCy - bellyH * 0.55,
                                    width: bellyW * 0.95, height: bellyH * 0.85))
        ctx.restoreGState()

        // ═══════ 4. 左翅膀（贴身体外侧，下垂不动）═══════
        let leftWingX = bodyCx - bodyW * 0.45
        let leftWingY = bodyCy - bodyH * 0.05
        ctx.saveGState()
        ctx.translateBy(x: leftWingX, y: leftWingY)
        ctx.rotate(by: 0.20)        // 微张开
        drawWing(ctx, u: u, sw: strokeW, hangDown: true)
        ctx.restoreGState()

        // ═══════ 5. 右翅膀（招手 ★ 周期举起）═══════
        let rightShoulderX = bodyCx + bodyW * 0.42
        let rightShoulderY = bodyCy + bodyH * 0.05
        ctx.saveGState()
        ctx.translateBy(x: rightShoulderX, y: rightShoulderY)
        ctx.rotate(by: -waveAngle)  // 顺时针举起来挥
        drawWing(ctx, u: u, sw: strokeW, hangDown: false)
        ctx.restoreGState()

        // ═══════ 6. 红围巾（在黑白交界线 scarfY，绕颈一圈）═══════
        // 主巾：横向圆角条
        let scarfMainW = bodyW * 0.86
        let scarfMainH = u * 0.09
        let scarfMain = CGRect(x: bodyCx - scarfMainW/2, y: scarfY - scarfMainH/2,
                                width: scarfMainW, height: scarfMainH)
        let scarfPath = CGPath(roundedRect: scarfMain,
                                cornerWidth: scarfMainH/2, cornerHeight: scarfMainH/2,
                                transform: nil)
        ctx.addPath(scarfPath); ctx.setFillColor(scarfRed); ctx.fillPath()
        // 围巾下沿阴影线
        ctx.setStrokeColor(scarfShade); ctx.setLineWidth(strokeW * 0.5)
        ctx.addPath(scarfPath); ctx.strokePath()
        // 围巾尾巴（左前方斜向下）
        ctx.saveGState()
        ctx.translateBy(x: bodyCx - scarfMainW * 0.20, y: scarfY - scarfMainH * 0.5)
        ctx.rotate(by: -0.45 + scarfFlow * 0.18)
        let tailW: CGFloat = u * 0.09
        let tailH: CGFloat = u * 0.20
        let tailRect = CGRect(x: -tailW/2, y: -tailH, width: tailW, height: tailH)
        let tailPath = CGPath(roundedRect: tailRect, cornerWidth: tailW/3, cornerHeight: tailW/3, transform: nil)
        ctx.addPath(tailPath); ctx.setFillColor(scarfRed); ctx.fillPath()
        ctx.addPath(tailPath); ctx.setStrokeColor(scarfShade); ctx.setLineWidth(strokeW * 0.5); ctx.strokePath()
        // 流苏
        ctx.setStrokeColor(scarfShade); ctx.setLineWidth(strokeW * 0.55)
        for dx: CGFloat in [-tailW * 0.30, 0, tailW * 0.30] {
            let p2 = CGMutablePath()
            p2.move(to: CGPoint(x: dx, y: -tailH))
            p2.addLine(to: CGPoint(x: dx, y: -tailH - u * 0.03))
            ctx.addPath(p2); ctx.strokePath()
        }
        ctx.restoreGState()

        // ═══════ 7. 脸部细节（在身体上方 黑色脸区里）═══════
        // 脸中心 y 在 围巾以上
        let faceY = bodyCy + bodyH * 0.30          // 黑色区中心

        // 双眼：椭圆 + 黑瞳偏内
        let eyeR: CGFloat   = u * 0.07
        let eyeDX: CGFloat  = u * 0.07
        if isBlink {
            for sign: CGFloat in [-1, 1] {
                drawBlinkEye(ctx, CGPoint(x: bodyCx + sign * eyeDX, y: faceY),
                             w: eyeR, sw: strokeW)
            }
        } else {
            for sign: CGFloat in [-1, 1] {
                drawEye(ctx, CGPoint(x: bodyCx + sign * eyeDX, y: faceY),
                        rx: eyeR * 0.85, ry: eyeR * 1.10, sw: strokeW,
                        pupilOffset: CGPoint(x: sign * eyeR * 0.10, y: -eyeR * 0.05))
            }
        }

        // 喙：在两眼下方中间
        drawBeak(ctx, c: CGPoint(x: bodyCx, y: faceY - u * 0.10),
                 w: u * 0.12, h: u * 0.07, sw: strokeW)

        // 腮红：在喙两侧
        ctx.setFillColor(cheekPink)
        ctx.fillEllipse(in: CGRect(x: bodyCx - u * 0.22, y: faceY - u * 0.12,
                                    width: u * 0.10, height: u * 0.06))
        ctx.fillEllipse(in: CGRect(x: bodyCx + u * 0.12, y: faceY - u * 0.12,
                                    width: u * 0.10, height: u * 0.06))
    }

    // ═══ 元素 ═══

    /// 翅膀
    /// `hangDown=true` 表示自然下垂（中心在腰部）
    /// `hangDown=false` 用于挥起来的右翼，原点在肩部
    private static func drawWing(_ ctx: CGContext, u: CGFloat, sw: CGFloat, hangDown: Bool) {
        let w = u * 0.13
        let h = u * 0.34
        let yOffset: CGFloat = hangDown ? -h/2 : -h    // 下垂时中心位置；举起时挂在原点上方
        let rect = CGRect(x: -w/2, y: yOffset, width: w, height: h)
        ctx.setFillColor(bodyBlack); ctx.fillEllipse(in: rect)
        // 翅膀外侧高光
        ctx.saveGState()
        ctx.addEllipse(in: rect); ctx.clip()
        ctx.setFillColor(bodyShade)
        ctx.fillEllipse(in: CGRect(x: -w * 0.45, y: yOffset, width: w * 0.65, height: h))
        ctx.restoreGState()
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.55); ctx.strokeEllipse(in: rect)
    }

    /// 橙色橡皮鸭脚
    private static func drawFoot(_ ctx: CGContext, cx: CGFloat, y: CGFloat,
                                  u: CGFloat, sw: CGFloat) {
        let footW: CGFloat = u * 0.18
        let footH: CGFloat = u * 0.07
        let rect = CGRect(x: cx - footW/2, y: y, width: footW, height: footH)
        let path = CGPath(roundedRect: rect, cornerWidth: footH/2, cornerHeight: footH/2, transform: nil)
        ctx.addPath(path); ctx.setFillColor(foot); ctx.fillPath()
        // 脚底深色
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.setFillColor(footDark)
        ctx.fill(CGRect(x: cx - footW/2, y: y, width: footW, height: footH * 0.30))
        ctx.restoreGState()
        ctx.addPath(path); ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.55); ctx.strokePath()
        // 三趾
        ctx.setStrokeColor(outline.copy(alpha: 0.4)!); ctx.setLineWidth(sw * 0.4)
        for dx: CGFloat in [-footW * 0.22, 0, footW * 0.22] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: cx + dx, y: y + footH * 0.55))
            p.addLine(to: CGPoint(x: cx + dx, y: y + footH * 0.95))
            ctx.addPath(p); ctx.strokePath()
        }
    }

    /// 喙：橙色钻石（上下瓣）
    private static func drawBeak(_ ctx: CGContext, c: CGPoint, w: CGFloat, h: CGFloat, sw: CGFloat) {
        // 上瓣（亮）
        let top = CGMutablePath()
        top.move(to: CGPoint(x: c.x - w/2, y: c.y))
        top.addQuadCurve(to: CGPoint(x: c.x + w/2, y: c.y),
                          control: CGPoint(x: c.x, y: c.y + h * 0.85))
        top.closeSubpath()
        ctx.setFillColor(beak); ctx.addPath(top); ctx.fillPath()
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.55); ctx.addPath(top); ctx.strokePath()
        // 下瓣（暗）
        let bot = CGMutablePath()
        bot.move(to: CGPoint(x: c.x - w * 0.42, y: c.y - 0.5))
        bot.addQuadCurve(to: CGPoint(x: c.x + w * 0.42, y: c.y - 0.5),
                          control: CGPoint(x: c.x, y: c.y - h * 0.55))
        bot.closeSubpath()
        ctx.setFillColor(beakDark); ctx.addPath(bot); ctx.fillPath()
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.55); ctx.addPath(bot); ctx.strokePath()
    }

    /// Q 版大眼：椭圆 + 黑瞳 + 高光
    private static func drawEye(_ ctx: CGContext, _ c: CGPoint,
                                 rx: CGFloat, ry: CGFloat, sw: CGFloat,
                                 pupilOffset: CGPoint) {
        let outRect = CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)
        ctx.setFillColor(eyeWhite); ctx.fillEllipse(in: outRect)
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 0.7); ctx.strokeEllipse(in: outRect)
        let pr = rx * 0.62
        ctx.setFillColor(eyeBlack)
        ctx.fillEllipse(in: CGRect(x: c.x + pupilOffset.x - pr,
                                    y: c.y + pupilOffset.y - pr,
                                    width: pr * 2, height: pr * 2))
        ctx.setFillColor(eyeWhite)
        ctx.fillEllipse(in: CGRect(x: c.x + pupilOffset.x - pr * 0.4,
                                    y: c.y + pupilOffset.y + pr * 0.15,
                                    width: pr * 0.65, height: pr * 0.55))
    }

    private static func drawBlinkEye(_ ctx: CGContext, _ c: CGPoint, w: CGFloat, sw: CGFloat) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x - w, y: c.y))
        p.addQuadCurve(to: CGPoint(x: c.x + w, y: c.y),
                       control: CGPoint(x: c.x, y: c.y - w * 0.55))
        ctx.setStrokeColor(outline); ctx.setLineWidth(sw * 1.4); ctx.setLineCap(.round)
        ctx.addPath(p); ctx.strokePath()
    }
}
