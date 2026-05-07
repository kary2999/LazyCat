import AppKit

/// 模型层自检：在临时目录建独立 Store，把公共 API 跑一遍并断言结果。
enum SelfTest {
    static func run() -> Int32 {
        var pass = 0, fail = 0, fails: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if ok { print("✅ \(name)"); pass += 1 }
            else { print("❌ \(name) \(detail)"); fails.append(name); fail += 1 }
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MyTodoSelfTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let dataURL = tmp.appendingPathComponent("data.json")
        let store = Store(testPath: dataURL)

        check("初始 tasks 为空", store.data.tasks.isEmpty)
        check("初始 personHistory 为空", store.data.personHistory.isEmpty)

        // 录入
        let t1 = store.addTask(person: "张三", text: "需求讨论",
                               imageFiles: [], priority: .top)
        check("addTask 写入 task", store.data.tasks.count == 1)
        check("addTask 写 personHistory", store.data.personHistory.first == "张三")
        check("addTask 保留 person", t1.person == "张三")
        check("addTask priority=TOP", t1.priority == .top)

        _ = store.addTask(person: "李四", text: "审核合同",
                          imageFiles: [], priority: .mid)
        _ = store.addTask(person: "张三", text: "再讨论",
                          imageFiles: [], priority: .low)

        // 历史排序：最近使用在前
        check("personHistory 最近使用在前 (张三)",
              store.data.personHistory.first == "张三")
        check("personHistory 去重", store.data.personHistory.count == 2)

        // 模糊提示
        let sug1 = store.suggestPersons(for: "张")
        check("suggestPersons 前缀命中 '张'", sug1.contains("张三"))
        let sug2 = store.suggestPersons(for: "四")
        check("suggestPersons 包含命中 '四'", sug2.contains("李四"))
        let sug3 = store.suggestPersons(for: "")
        check("suggestPersons 空查询返回全部", sug3.count == 2)

        // 排序：未完成 + 高优先级在前
        let sorted = store.sortedTasks()
        check("sortedTasks: TOP 在最前", sorted.first?.priority == .top)

        // 备注（50 字截断）
        let longNote = String(repeating: "字", count: 80)
        store.updateNote(taskId: t1.id, note: longNote)
        let noteSaved = store.data.tasks.first(where: { $0.id == t1.id })?.note ?? ""
        check("updateNote 截断到 50 字", noteSaved.count == 50)

        // 完成 / 取消
        store.toggleComplete(t1.id)
        check("toggleComplete → completed=true",
              store.data.tasks.first(where: { $0.id == t1.id })?.completed == true)
        check("toggleComplete 写 completedAt",
              store.data.tasks.first(where: { $0.id == t1.id })?.completedAt != nil)
        store.toggleComplete(t1.id)
        check("toggleComplete 再次 → completed=false",
              store.data.tasks.first(where: { $0.id == t1.id })?.completed == false)

        // 图片保存
        let img = makeTestImage()
        let name = store.saveImage(img)
        check("saveImage 返回文件名", name != nil)
        if let n = name {
            let url = store.imageURL(for: n)
            check("saveImage 落盘", FileManager.default.fileExists(atPath: url.path))
            check("loadImage 可读回", store.loadImage(named: n) != nil)
        }

        // 带图的 task
        let t4 = store.addTask(person: "王五", text: "设计稿",
                               imageFiles: [name ?? ""], priority: .none)
        check("addTask 带 imageFiles", t4.imageFiles.count == 1)

        // 持久化
        store.save()
        let raw = try? Data(contentsOf: dataURL)
        check("data.json 已写", raw != nil)
        if let raw = raw,
           let re = try? JSONDecoder().decode(AppData.self, from: raw) {
            check("反序列化任务数一致", re.tasks.count == store.data.tasks.count)
            check("反序列化 personHistory 一致",
                  re.personHistory == store.data.personHistory)
        } else {
            check("反序列化", false)
        }

        // 删除 task 同时删除图片
        let imgFile = t4.imageFiles.first!
        store.deleteTask(t4.id)
        check("deleteTask 从 tasks 移除",
              !store.data.tasks.contains(where: { $0.id == t4.id }))
        check("deleteTask 同步删除图片文件",
              !FileManager.default.fileExists(atPath: store.imageURL(for: imgFile).path))

        // 老 JSON 兼容：title → text
        let legacy = """
        {"tasks":[{"id":"\(UUID().uuidString)","title":"老任务标题","priority":2}],"personHistory":["历史人"]}
        """.data(using: .utf8)!
        let legacyParsed = try? JSONDecoder().decode(AppData.self, from: legacy)
        check("兼容旧 JSON: 解码成功", legacyParsed != nil)
        check("兼容旧 JSON: title → text",
              legacyParsed?.tasks.first?.text == "老任务标题")
        check("兼容旧 JSON: personHistory 读回",
              legacyParsed?.personHistory == ["历史人"])

        // 更旧 JSON（完全缺 personHistory）
        let veryOld = """
        {"tasks":[]}
        """.data(using: .utf8)!
        let veryOldParsed = try? JSONDecoder().decode(AppData.self, from: veryOld)
        check("兼容更旧 JSON: 缺字段用默认值",
              veryOldParsed?.personHistory.isEmpty == true)

        print("\n=================================")
        print("  PASS: \(pass)    FAIL: \(fail)")
        print("=================================")
        if fail > 0 {
            print("失败项：")
            for f in fails { print("  - \(f)") }
            return 1
        }
        return 0
    }

    private static func makeTestImage() -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        return img
    }
}
