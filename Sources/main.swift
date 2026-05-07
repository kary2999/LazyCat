import AppKit

if CommandLine.arguments.contains("--self-test") {
    exit(SelfTest.run())
}

// 构建脚本用：生成 .iconset 到指定目录，再交给 iconutil 打 .icns
if let i = CommandLine.arguments.firstIndex(of: "--gen-icon"),
   i + 1 < CommandLine.arguments.count {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    let n = CatRenderer.writeIconSet(to: dir)
    FileHandle.standardOutput.write(Data("wrote \(n) icon pngs to \(dir.path)\n".utf8))
    exit(n == 10 ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
