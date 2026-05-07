import Foundation

/// 简易文件日志，写到 /tmp/mytodo.log 方便外部 cat / tail 检查
enum AppLog {
    private static let queue = DispatchQueue(label: "mytodo.log")
    private static let path = "/tmp/mytodo.log"
    private static var didInit = false

    static func log(_ message: String) {
        NSLog("[MyTodo] %@", message)
        queue.async {
            if !didInit {
                try? "".write(toFile: path, atomically: true, encoding: .utf8)
                didInit = true
            }
            let line = "[\(timestamp())] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
