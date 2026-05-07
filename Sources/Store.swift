import AppKit

final class Store {
    static let shared = Store()

    private(set) var data: AppData
    private let fileURL: URL
    private let imageDir: URL

    static let didChangeNotification = Notification.Name("Store.didChange")

    init(testPath: URL? = nil) {
        let fm = FileManager.default

        let baseDir: URL
        if let tp = testPath {
            baseDir = tp.deletingLastPathComponent()
            self.fileURL = tp
        } else {
            let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true))
                ?? URL(fileURLWithPath: NSHomeDirectory())
            baseDir = support.appendingPathComponent("MyTodoApp", isDirectory: true)
            self.fileURL = baseDir.appendingPathComponent("data.json")
        }
        self.imageDir = baseDir.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: imageDir, withIntermediateDirectories: true)

        if let raw = try? Data(contentsOf: fileURL),
           let parsed = try? JSONDecoder().decode(AppData.self, from: raw) {
            self.data = parsed
        } else {
            self.data = AppData.defaultData()
            saveSilently()
        }
    }

    // MARK: - Persistence

    var dataFilePath: String { fileURL.path }
    var imageDirectory: URL { imageDir }

    private func saveSilently() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        if let bytes = try? enc.encode(data) {
            try? bytes.write(to: fileURL, options: .atomic)
        }
    }

    func save() {
        saveSilently()
        NotificationCenter.default.post(name: Store.didChangeNotification, object: nil)
    }

    // MARK: - Images

    /// 把剪贴板 / 拖入的 NSImage 保存到 images/，返回文件名
    @discardableResult
    func saveImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let name = "\(UUID().uuidString).png"
        let url = imageDir.appendingPathComponent(name)
        do {
            try png.write(to: url, options: .atomic)
            return name
        } catch {
            AppLog.log("saveImage fail: \(error)")
            return nil
        }
    }

    func imageURL(for fileName: String) -> URL {
        imageDir.appendingPathComponent(fileName)
    }

    func loadImage(named fileName: String) -> NSImage? {
        NSImage(contentsOf: imageURL(for: fileName))
    }

    private func deleteImageFiles(_ names: [String]) {
        let fm = FileManager.default
        for n in names {
            try? fm.removeItem(at: imageURL(for: n))
        }
    }

    // MARK: - Task CRUD

    @discardableResult
    func addTask(person: String, text: String, imageFiles: [String],
                 priority: Priority, remindAt: Date? = nil) -> TodoItem {
        var t = TodoItem(person: person, text: text,
                         imageFiles: imageFiles, priority: priority,
                         remindAt: remindAt)
        t.createdAt = Date()
        data.tasks.append(t)
        rememberPerson(person)
        save()
        return t
    }

    /// TG 转任务专用:整个 TodoItem 直接塞进去(已带 tgChatType / messages 等扩展字段)
    func addTaskRaw(_ t: TodoItem) {
        var t = t
        t.createdAt = Date()
        data.tasks.append(t)
        save()
    }

    /// 整体替换某条任务(用于 TG 追加场景)
    func updateTask(_ t: TodoItem) {
        guard let i = data.tasks.firstIndex(where: { $0.id == t.id }) else { return }
        data.tasks[i] = t
        save()
    }

    func setRemindAt(taskId: UUID, date: Date?) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        data.tasks[i].remindAt = date
        data.tasks[i].remindFired = false
        save()
    }

    func markRemindFired(_ taskId: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        data.tasks[i].remindFired = true
        saveSilently()
    }

    /// 修改指定任务的 @人名；空串会被忽略（保持必填语义）
    func setPerson(taskId: UUID, person: String) {
        let trimmed = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        data.tasks[i].person = trimmed
        rememberPerson(trimmed)
        save()
    }

    func setPriority(taskId: UUID, priority: Priority) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        data.tasks[i].priority = priority
        save()
    }

    func updateNote(taskId: UUID, note: String) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        data.tasks[i].note = String(note.prefix(50))
        save()
    }

    /// 详情页编辑正文，2000 字上限
    func updateText(taskId: UUID, text: String) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let trimmed = String(text.prefix(2000))
        if data.tasks[i].text == trimmed { return }   // 不变就不写盘
        data.tasks[i].text = trimmed
        save()
    }

    func toggleComplete(_ taskId: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        data.tasks[i].completed.toggle()
        data.tasks[i].completedAt = data.tasks[i].completed ? Date() : nil
        save()
    }

    func deleteTask(_ taskId: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == taskId }) else { return }
        let imgs = data.tasks[i].imageFiles
        data.tasks.remove(at: i)
        deleteImageFiles(imgs)
        save()
    }

    // MARK: - Person history (for 模糊提示)

    /// 把人名放到 history 最前面（去重）
    func rememberPerson(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.personHistory.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        data.personHistory.insert(trimmed, at: 0)
        if data.personHistory.count > 200 {
            data.personHistory = Array(data.personHistory.prefix(200))
        }
    }

    /// 模糊匹配：前缀 → 包含，最多 8 条
    func suggestPersons(for query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(data.personHistory.prefix(8)) }
        var prefix: [String] = []
        var contain: [String] = []
        for n in data.personHistory {
            let lc = n.lowercased()
            if lc.hasPrefix(q) { prefix.append(n) }
            else if lc.contains(q) { contain.append(n) }
        }
        return Array((prefix + contain).prefix(8))
    }

    // MARK: - Queries

    /// 按：未完成→优先级高→最新，完成放最下
    func sortedTasks() -> [TodoItem] {
        data.tasks.sorted { a, b in
            if a.completed != b.completed { return !a.completed && b.completed }
            if a.priority.rawValue != b.priority.rawValue {
                return a.priority.rawValue > b.priority.rawValue
            }
            return a.createdAt > b.createdAt
        }
    }
}
