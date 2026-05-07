import AppKit
import CoreText

/// HTML → A4 多页 PDF（CoreText 分页绘制）
/// 用法：swift html2pdf.swift <input.html> <output.pdf>
let args = CommandLine.arguments
guard args.count >= 3 else {
    print("用法: swift html2pdf.swift <input.html> <output.pdf>")
    exit(1)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])

// 1. 加载 HTML 成 NSAttributedString
guard let htmlData = try? Data(contentsOf: inputURL) else {
    print("✗ 读 HTML 失败"); exit(1)
}
let attr: NSAttributedString
do {
    attr = try NSAttributedString(data: htmlData, options: [
        .documentType: NSAttributedString.DocumentType.html,
        .characterEncoding: String.Encoding.utf8.rawValue
    ], documentAttributes: nil)
} catch {
    print("✗ HTML 解析失败: \(error)"); exit(1)
}

// 2. 设置页面 + 边距
let pageW: CGFloat = 595, pageH: CGFloat = 842   // A4
let margin: CGFloat = 50
var mediaBox = CGRect(x: 0, y: 0, width: pageW, height: pageH)
let textRect = CGRect(x: margin, y: margin,
                       width: pageW - margin * 2,
                       height: pageH - margin * 2)

// 3. 创建 PDF context
guard let consumer = CGDataConsumer(url: outputURL as CFURL),
      let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
    print("✗ PDF context 创建失败"); exit(1)
}

let setter = CTFramesetterCreateWithAttributedString(attr)
let totalLen = attr.length
var startIdx = CFIndex(0)
var pageNo = 0

while startIdx < totalLen {
    pageNo += 1
    ctx.beginPage(mediaBox: &mediaBox)
    let path = CGMutablePath()
    path.addRect(textRect)
    let frame = CTFramesetterCreateFrame(
        setter, CFRangeMake(startIdx, 0), path, nil)
    CTFrameDraw(frame, ctx)
    let visible = CTFrameGetVisibleStringRange(frame)
    ctx.endPage()
    startIdx += visible.length
    if visible.length == 0 { break }   // 防死循环
}
ctx.closePDF()

print("✓ 写入 \(pageNo) 页 → \(outputURL.path)")
exit(0)
