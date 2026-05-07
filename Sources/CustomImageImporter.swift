import AppKit

/// 自定义形象图片导入器：
///   - 弹 NSOpenPanel 让用户选一张本地图（jpg/png/heic 等）
///   - 重绘到 RGBA bitmap，**flood-fill 抠"和图边连通的近白色"**，等价于 Python PIL 那一招
///     → 不会误抠图内部的白色（猫白肚子、企鹅白脸都保留）
///   - 写入 ~/Library/Application Support/MyTodoApp/custom.png
///   - 自动切换悬浮形态到 .custom
enum CustomImageImporter {

    /// 弹 OpenPanel；用户挑完后做转换 + 落盘 + 切形态
    static func pickAndInstall() {
        let panel = NSOpenPanel()
        panel.title = "选择自定义形象图片"
        panel.message = "选一张图（建议 PNG，背景透明最好；不透明的图会自动抠白底）"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image, .heic]

        guard panel.runModal() == .OK, let srcURL = panel.url else { return }

        // 落盘位置
        let base = Store.shared.dataFilePath
            .replacingOccurrences(of: "/data.json", with: "")
        let dstURL = URL(fileURLWithPath: base).appendingPathComponent("custom.png")

        // 加载源图
        guard let src = NSImage(contentsOf: srcURL) else {
            showError("无法读取所选图片")
            return
        }

        // 转 RGBA bitmap + flood-fill 抠外部白底
        guard let processed = processImage(src) else {
            showError("处理图片失败")
            return
        }

        // 写出 PNG
        guard let pngData = processed.representation(using: .png, properties: [:]) else {
            showError("PNG 编码失败")
            return
        }
        do {
            try pngData.write(to: dstURL, options: .atomic)
            AppLog.log("CustomImage installed → \(dstURL.path)")
        } catch {
            showError("写入失败：\(error.localizedDescription)")
            return
        }

        // 切到 .custom 形态（悬浮窗会触发 reloadStyleAndSize 自动重读 custom.png）
        FloatingWidgetSettings.shared.setStyle(.custom)
    }

    // MARK: - 图像处理

    /// 把任意 NSImage 转成 RGBA bitmap，并 flood-fill 外部近白 → alpha 0
    private static func processImage(_ src: NSImage) -> NSBitmapImageRep? {
        // 用源图原始像素尺寸（不放大不缩小，悬浮窗渲染时会再 aspect-fit 缩）
        let pxW = max(1, Int(src.size.width))
        let pxH = max(1, Int(src.size.height))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: pxW * 4, bitsPerPixel: 32) else { return nil }

        // 把 NSImage 画到这张 RGBA bitmap 上
        NSGraphicsContext.saveGraphicsState()
        guard let gctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }
        NSGraphicsContext.current = gctx
        src.draw(in: NSRect(x: 0, y: 0, width: pxW, height: pxH),
                 from: .zero, operation: .copy, fraction: 1.0)
        gctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.bitmapData else { return bitmap }
        let bpr = bitmap.bytesPerRow

        // flood-fill：把"近白 / 浅灰棋盘格 / 源就是透明"都算外部背景
        // ★ 关键：源 PNG 透明区在 .copy 后会变成 (0,0,0,0)，必须把 alpha=0 当成背景识别，
        //    否则后面统一刷 alpha=255 会把它压成实色黑
        @inline(__always) func at(_ x: Int, _ y: Int) -> Int { y * bpr + x * 4 }
        @inline(__always) func isBg(_ x: Int, _ y: Int) -> Bool {
            let p = at(x, y)
            let r = data[p]; let g = data[p+1]; let b = data[p+2]; let a = data[p+3]
            // 源已透明 / 半透明（< 0.1）→ 直接当背景
            if a < 25 { return true }
            // 近白
            if r > 235 && g > 235 && b > 235 { return true }
            // 透明背景的棋盘格灰（很常见）
            if abs(Int(r) - Int(g)) < 12, abs(Int(g) - Int(b)) < 12,
               r >= 175, r <= 230 { return true }
            return false
        }

        // 用一份 mark 数组追踪"已确认为外部"
        var marked = [Bool](repeating: false, count: pxW * pxH)
        var queue: [Int] = []
        queue.reserveCapacity(pxW * pxH / 4)

        // 入队所有边缘像素（如果它本身就 isBg）
        for x in 0..<pxW {
            for y in [0, pxH - 1] {
                if isBg(x, y) {
                    let i = y * pxW + x
                    if !marked[i] { marked[i] = true; queue.append(i) }
                }
            }
        }
        for y in 0..<pxH {
            for x in [0, pxW - 1] {
                if isBg(x, y) {
                    let i = y * pxW + x
                    if !marked[i] { marked[i] = true; queue.append(i) }
                }
            }
        }

        // BFS
        var head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            let cy = cur / pxW
            let cx = cur - cy * pxW
            let neighbors: [(Int, Int)] = [(cx+1, cy), (cx-1, cy), (cx, cy+1), (cx, cy-1)]
            for (nx, ny) in neighbors {
                if nx < 0 || nx >= pxW || ny < 0 || ny >= pxH { continue }
                let ni = ny * pxW + nx
                if marked[ni] { continue }
                if isBg(nx, ny) {
                    marked[ni] = true
                    queue.append(ni)
                }
            }
        }

        // 应用：marked → alpha 0（外部背景）；
        // 非 marked → 保留源 alpha（半透明描边、抗锯齿羽化都得留住，否则边缘会出锯齿黑环）
        for y in 0..<pxH {
            for x in 0..<pxW {
                let i = y * pxW + x
                let p = at(x, y)
                if marked[i] { data[p + 3] = 0 }
                // else: 不动 alpha，保持源像素（透明的就是透明的，不透明的就是不透明的）
            }
        }

        AppLog.log("CustomImage: \(pxW)×\(pxH), 抠外部 \(queue.count) 像素")
        return bitmap
    }

    private static func showError(_ msg: String) {
        let alert = NSAlert()
        alert.messageText = "导入图片失败"
        alert.informativeText = msg
        alert.alertStyle = .warning
        alert.runModal()
    }
}
