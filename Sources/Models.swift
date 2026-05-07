import Foundation

/// 优先级 0-3，0 = 无，3 = TOP
enum Priority: Int, Codable, CaseIterable {
    case none = 0
    case low = 1
    case mid = 2
    case top = 3

    var label: String {
        switch self {
        case .none: return "无"
        case .low:  return "T2"
        case .mid:  return "T1"
        case .top:  return "T0"
        }
    }

    var colorHex: String {
        switch self {
        case .none: return "#C7C7CC"
        case .low:  return "#9BCF72"
        case .mid:  return "#F5A623"
        case .top:  return "#E8584C"
        }
    }
}

/// 单条任务（极简版）
/// TG 转任务时的"消息条"——同人私聊 24h 内追加,在详情面板分组列出
struct TaskMessage: Codable {
    var from: String = ""        // 发送人名
    var text: String = ""
    var date: Date = Date()
    var imageFile: String? = nil // 关联图片(已 import 进 images/)
}

struct TodoItem: Codable, Identifiable {
    var id: UUID = UUID()
    var person: String = ""            // 录入时的人名
    var text: String = ""              // 事件文本
    var imageFiles: [String] = []      // 图片文件名(相对于 images/)
    var priority: Priority = .none
    var note: String = ""              // 事后备注,最多 50 字
    var completed: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    var remindAt: Date? = nil          // 定时提醒时间(可空)
    var remindFired: Bool = false      // 是否已经通知过
    /// TG 来源标记 + 消息流(空数组表示非 TG 来源任务)
    var tgChatType: String = ""        // "private" / "group" / ""
    var tgSourceLabel: String = ""     // "私聊" 或 群名
    var messages: [TaskMessage] = []   // 同人私聊追加场景下的多条消息

    init(person: String = "", text: String = "", imageFiles: [String] = [],
         priority: Priority = .none, note: String = "", remindAt: Date? = nil) {
        self.person = person
        self.text = text
        self.imageFiles = imageFiles
        self.priority = priority
        self.note = note
        self.remindAt = remindAt
    }

    private struct AnyKey: CodingKey {
        var stringValue: String; var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
        init(_ s: String) { self.stringValue = s }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func str(_ k: String) -> String? { try? c.decode(String.self, forKey: AnyKey(k)) }
        self.id         = (try? c.decode(UUID.self, forKey: AnyKey("id"))) ?? UUID()
        self.person     = str("person") ?? ""
        // 旧数据 title → text
        self.text       = str("text") ?? str("title") ?? ""
        self.imageFiles = (try? c.decode([String].self, forKey: AnyKey("imageFiles"))) ?? []
        self.priority   = (try? c.decode(Priority.self, forKey: AnyKey("priority"))) ?? .none
        self.note       = str("note") ?? ""
        self.completed  = (try? c.decode(Bool.self, forKey: AnyKey("completed"))) ?? false
        self.completedAt = try? c.decode(Date.self, forKey: AnyKey("completedAt"))
        self.createdAt  = (try? c.decode(Date.self, forKey: AnyKey("createdAt"))) ?? Date()
        self.remindAt   = try? c.decode(Date.self, forKey: AnyKey("remindAt"))
        self.remindFired = (try? c.decode(Bool.self, forKey: AnyKey("remindFired"))) ?? false
        self.tgChatType    = str("tgChatType") ?? ""
        self.tgSourceLabel = str("tgSourceLabel") ?? ""
        self.messages      = (try? c.decode([TaskMessage].self, forKey: AnyKey("messages"))) ?? []
    }
}

struct AppData: Codable {
    var tasks: [TodoItem] = []
    /// 历史人名（按最近使用排序，用于录入时模糊提示）
    var personHistory: [String] = []

    static func defaultData() -> AppData { AppData() }

    init() {}

    enum CodingKeys: String, CodingKey { case tasks, personHistory }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.tasks = (try? c.decode([TodoItem].self, forKey: .tasks)) ?? []
        self.personHistory = (try? c.decode([String].self, forKey: .personHistory)) ?? []
    }
}
