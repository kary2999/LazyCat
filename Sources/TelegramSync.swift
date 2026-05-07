import Foundation
import AppKit

/// Telegram Bot API 集成
///
/// 用法：
/// 1. 用户在 @BotFather 创建 bot，拿到 token
/// 2. 在「设置 → Telegram」里填入 token
/// 3. 启动后每 30 秒拉一次 getUpdates；遇到符合规则的消息 → 自动建任务
///
/// 触发规则：
/// - 私聊（chat.type == private）：所有消息都触发
/// - 群组 / 超级群：只有 @ 提到本 bot 的消息触发
final class TelegramSync {
    static let shared = TelegramSync()

    static let didChangeStatusNotification = Notification.Name("TelegramSync.statusChanged")

    // MARK: - Settings

    private let tokenKey = "MyTodo.telegram.botToken"
    private let lastUpdateKey = "MyTodo.telegram.lastUpdateId"
    private let enabledKey = "MyTodo.telegram.enabled"

    var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
            // token 变更 → 重置 update id
            UserDefaults.standard.set(0, forKey: lastUpdateKey)
            cachedBotUsername = nil
        }
    }

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private var lastUpdateId: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: lastUpdateKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: lastUpdateKey) }
    }

    private var cachedBotUsername: String?

    // 状态
    private(set) var status: String = "未配置"
    private(set) var lastError: String?
    private(set) var lastSyncAt: Date?

    private var pollTimer: Timer?

    // MARK: - 启动

    func startIfEnabled() {
        guard enabled, let _ = token else {
            status = "未启用"
            return
        }
        // 先拿 bot 用户名（用于 @ 检测）
        fetchMe { [weak self] in
            self?.poll()   // 立即拉一次
        }
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        status = "已停止"
        notifyStatus()
    }

    // MARK: - API call

    /// 测试连接：调 getMe，成功返回用户名
    func testConnection(completion: @escaping (Result<String, Error>) -> Void) {
        guard let tk = token, !tk.isEmpty else {
            completion(.failure(SyncError.noToken)); return
        }
        let url = URL(string: "https://api.telegram.org/bot\(tk)/getMe")!
        URLSession.shared.dataTask(with: url) { data, _, err in
            if let err = err {
                DispatchQueue.main.async { completion(.failure(err)) }; return
            }
            guard let data = data else {
                DispatchQueue.main.async { completion(.failure(SyncError.empty)) }; return
            }
            do {
                let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let ok = parsed?["ok"] as? Bool, ok,
                      let result = parsed?["result"] as? [String: Any] else {
                    let desc = (parsed?["description"] as? String) ?? "未知错误"
                    DispatchQueue.main.async {
                        completion(.failure(SyncError.api(desc)))
                    }
                    return
                }
                let username = result["username"] as? String ?? "?"
                DispatchQueue.main.async {
                    self.cachedBotUsername = username
                    completion(.success(username))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
    }

    private func fetchMe(completion: @escaping () -> Void) {
        testConnection { _ in completion() }
    }

    private func poll() {
        guard enabled, let tk = token else { return }
        var comp = URLComponents(string: "https://api.telegram.org/bot\(tk)/getUpdates")!
        comp.queryItems = [
            URLQueryItem(name: "offset", value: "\(lastUpdateId + 1)"),
            URLQueryItem(name: "timeout", value: "0"),
            URLQueryItem(name: "allowed_updates", value: "[\"message\"]"),
        ]
        guard let url = comp.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, err in
            guard let self = self else { return }
            if let err = err {
                self.lastError = err.localizedDescription
                self.status = "拉取失败"
                self.notifyStatus()
                return
            }
            guard let data = data,
                  let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let ok = parsed["ok"] as? Bool, ok,
                  let updates = parsed["result"] as? [[String: Any]] else {
                self.lastError = "解析失败"
                self.status = "解析失败"
                self.notifyStatus()
                return
            }
            self.lastError = nil
            self.lastSyncAt = Date()
            self.status = "已同步 · \(updates.count) 条新消息"

            for upd in updates {
                self.handleUpdate(upd)
                if let id = upd["update_id"] as? Int64 {
                    self.lastUpdateId = max(self.lastUpdateId, id)
                } else if let id = upd["update_id"] as? Int {
                    self.lastUpdateId = max(self.lastUpdateId, Int64(id))
                }
            }
            self.notifyStatus()
        }.resume()
    }

    private func handleUpdate(_ upd: [String: Any]) {
        guard let msg = upd["message"] as? [String: Any] else { return }
        guard let chat = msg["chat"] as? [String: Any] else { return }
        let chatType = (chat["type"] as? String) ?? "private"
        let text = (msg["text"] as? String) ?? (msg["caption"] as? String) ?? ""

        // 决定是否触发：私聊 always；群聊 仅当 @bot
        var shouldAdd = false
        if chatType == "private" {
            shouldAdd = true
        } else if let botName = cachedBotUsername, !botName.isEmpty {
            let mention = "@" + botName
            if text.localizedCaseInsensitiveContains(mention) {
                shouldAdd = true
            }
        }
        guard shouldAdd, !text.isEmpty else { return }

        // 提取 sender 名
        let from = msg["from"] as? [String: Any]
        let firstName = from?["first_name"] as? String ?? ""
        let lastName  = from?["last_name"] as? String ?? ""
        let username  = from?["username"] as? String ?? ""
        let person: String = {
            let full = (firstName + " " + lastName).trimmingCharacters(in: .whitespaces)
            if !full.isEmpty { return full }
            if !username.isEmpty { return username }
            return "Telegram"
        }()

        // 文本：去掉 @bot 部分
        var taskText = text
        if let botName = cachedBotUsername {
            taskText = taskText.replacingOccurrences(of: "@" + botName,
                                                     with: "",
                                                     options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
        }
        if taskText.isEmpty { taskText = text }
        // 加来源前缀
        let chatTitle = (chat["title"] as? String) ?? "私聊"
        let prefix = chatType == "private" ? "📨 私聊" : "📨 \(chatTitle) · @\(cachedBotUsername ?? "bot")"
        let final = "\(prefix)\n\n\(taskText)"

        DispatchQueue.main.async {
            _ = Store.shared.addTask(person: person, text: final,
                                     imageFiles: [],
                                     priority: .none,
                                     remindAt: nil)
            Store.shared.rememberPerson(person)
            AppLog.log("Telegram 自动建任务: \(person) \(taskText.prefix(30))…")
        }
    }

    private func notifyStatus() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeStatusNotification, object: nil)
        }
    }

    enum SyncError: LocalizedError {
        case noToken
        case empty
        case api(String)
        var errorDescription: String? {
            switch self {
            case .noToken: return "未填 token"
            case .empty:   return "返回空"
            case .api(let s): return s
            }
        }
    }

    var displayBotUsername: String { cachedBotUsername ?? "未连接" }
}
