import Foundation
import AppKit

/// TDLib 高阶 wrapper
///
/// 用法：
///   let tg = TelegramTDLib.shared
///   tg.start()                      // 后台线程跑接收循环
///   tg.delegate = ...               // 接收认证状态 / 消息事件
///   tg.setApiCredentials(id:..., hash:...)
///   tg.setPhoneNumber("+86...")
///   tg.checkCode("12345")
///
/// 收到的「应该建任务」消息走 onShouldCreateTask 回调
final class TelegramTDLib {
    static let shared = TelegramTDLib()

    // MARK: - 持久化 keys

    private let apiIdKey   = "MyTodo.tg.apiId"
    private let apiHashKey = "MyTodo.tg.apiHash"
    private let myIdKey    = "MyTodo.tg.myId"

    // MARK: - 状态

    enum AuthState: String {
        case unknown
        case waitingTdParams       // 等设置 TDLib 参数
        case waitingEncryptionKey  // ★ 旧 schema 1.8.0 才有：参数发完后等 db 加密密钥
        case waitingPhoneNumber    // 等手机号
        case waitingCode           // 等 SMS / app 验证码
        case waitingPassword       // 等 2FA 密码
        case ready                 // 已登录
        case loggingOut
        case closed
    }

    private(set) var authState: AuthState = .unknown {
        didSet {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.authStateDidChange, object: nil)
            }
        }
    }
    static let authStateDidChange = Notification.Name("TelegramTDLib.authStateDidChange")
    static let inboxDidChange     = Notification.Name("TelegramTDLib.inboxDidChange")
    /// userInfo["message"] = String, userInfo["code"] = Int
    static let didReceiveError    = Notification.Name("TelegramTDLib.didReceiveError")

    /// 最近一次 TDLib 报的错（用来在 UI 上显示「上次失败原因」）
    private(set) var lastErrorMessage: String?

    /// 收到一条新消息（私聊 / 群里 @ 我），推到 inbox
    var onInboxMessage: ((InboxMessage) -> Void)?

    /// 用户配置的 api_id / api_hash
    var apiId: Int32? {
        get {
            let n = UserDefaults.standard.integer(forKey: apiIdKey)
            return n > 0 ? Int32(n) : nil
        }
        set { UserDefaults.standard.set(Int(newValue ?? 0), forKey: apiIdKey) }
    }
    var apiHash: String? {
        get { UserDefaults.standard.string(forKey: apiHashKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiHashKey) }
    }

    /// 我自己的 user id（登录后填入；用来判断"被 @ 的"）
    private(set) var myUserId: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: myIdKey)) }
        set { UserDefaults.standard.set(Int(newValue), forKey: myIdKey) }
    }

    /// 我自己的 username，用于 @ 检测
    private var myUsername: String?

    /// 内存中的 inbox（按时间倒序，最新在 0）
    private(set) var inbox: [InboxMessage] = []

    // MARK: - private

    private var clientId: Int32 = -1
    private var receiveThread: Thread?
    private let queue = DispatchQueue(label: "tdlib.receive")
    private var stopRequested = false

    // 简单去重：上次见过的 (chat_id, message_id) 对
    private var seenMessages: Set<String> = []

    // chat_id → chat 元数据（type / title / username）
    private var chatCache: [Int64: ChatInfo] = [:]
    // user_id → user 元数据
    private var userCache: [Int64: UserInfo] = [:]

    // MARK: - 启动 / 停止

    /// 应用启动调一次。如果已配置 api_id/hash 就开 TDLib，否则只设置参数等用户配置
    func start() {
        guard clientId == -1 else { return }
        clientId = td_create_client_id()
        // 启动后台接收循环
        receiveThread = Thread { [weak self] in
            self?.receiveLoop()
        }
        receiveThread?.name = "tdlib.receive"
        receiveThread?.start()
        AppLog.log("TDLib client_id=\(clientId) 已创建")
        // 立刻 ping 一下让 TDLib 开始返回 authorizationState
        send(["@type": "getAuthorizationState"])
    }

    func stop() {
        stopRequested = true
        if clientId != -1 {
            send(["@type": "close"])
        }
    }

    /// 退出 app 前同步关停：发 close、等 receive 线程退出最多 timeout 秒。
    /// 避免主线程 exit() 进 C++ 静态析构时，receive 线程还在 td_receive 摸已经被析构的对象 → SIGSEGV。
    func shutdownBeforeTerminate(timeout: TimeInterval = 1.5) {
        AppLog.log("TDLib shutdownBeforeTerminate begin (state=\(authState.rawValue))")
        if clientId != -1 {
            send(["@type": "close"])
        }
        stopRequested = true
        // 自旋等 receive 线程跑完最后一轮（最多 timeout 秒）
        let deadline = Date().addingTimeInterval(timeout)
        while let t = receiveThread, !t.isFinished, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        AppLog.log("TDLib shutdownBeforeTerminate done (thread.isFinished=\(receiveThread?.isFinished ?? true))")
    }

    // MARK: - 用户操作

    func setApiCredentials(id: Int32, hash: String) {
        self.apiId = id
        self.apiHash = hash
        // ★ 关键：如果 TDLib 已经在等参数（waitingTdParams），立刻补发，否则它会一直卡死
        // 不在 wait 状态下也无害——TDLib 不会接受第二次 setTdlibParameters，但顶多忽略
        if authState == .waitingTdParams || authState == .unknown {
            sendTdlibParameters()
        } else {
            // 兜底：让 TDLib 重新汇报当前 authState（首次启动时它有时不会主动推）
            send(["@type": "getAuthorizationState"])
        }
    }

    /// 防抖：1.5s 内发过同样的 setAuthenticationPhoneNumber 就吞掉，
    /// 避免 UI 抖两下触发 TDLib 400 "Another authorization query has started"
    private var lastPhoneSendAt: Date?
    private var lastPhoneSent: String?
    func setPhoneNumber(_ phone: String) {
        if let last = lastPhoneSendAt, lastPhoneSent == phone,
           Date().timeIntervalSince(last) < 1.5 {
            AppLog.log("setPhoneNumber: 1.5s 内重复请求，吞掉")
            return
        }
        lastPhoneSendAt = Date()
        lastPhoneSent = phone
        send([
            "@type": "setAuthenticationPhoneNumber",
            "phone_number": phone,
        ])
    }

    func checkCode(_ code: String) {
        send([
            "@type": "checkAuthenticationCode",
            "code": code,
        ])
    }

    func checkPassword(_ password: String) {
        send([
            "@type": "checkAuthenticationPassword",
            "password": password,
        ])
    }

    func logOut() {
        send(["@type": "logOut"])
    }

    // MARK: - 收发

    private func send(_ obj: [String: Any]) {
        guard clientId != -1 else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return }
        s.withCString { td_send(clientId, $0) }
    }

    private func receiveLoop() {
        var lastHeartbeat = Date()
        AppLog.log("TDLib receiveLoop started")
        while !stopRequested {
            if let cstr = td_receive(1.0) {
                let str = String(cString: cstr)
                handle(jsonString: str)
            }
            // 每 5 秒打一行心跳，证明线程还活着，方便排查"卡死"
            if Date().timeIntervalSince(lastHeartbeat) > 5 {
                AppLog.log("TDLib receiveLoop alive (state=\(authState.rawValue))")
                lastHeartbeat = Date()
            }
        }
        AppLog.log("TDLib receiveLoop exited")
    }

    private func handle(jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["@type"] as? String else { return }

        switch type {
        case "updateAuthorizationState":
            if let state = obj["authorization_state"] as? [String: Any],
               let stType = state["@type"] as? String {
                handleAuthState(stType, state: state)
            }

        case "updateNewMessage":
            if let msg = obj["message"] as? [String: Any] {
                handleNewMessage(msg)
            }

        case "updateNewChat":
            if let chat = obj["chat"] as? [String: Any] {
                cacheChat(chat)
            }

        case "updateFile":
            // 文件下载状态推送：图片消息的 photo 文件下载完成时把路径回填到 inbox
            if let f = obj["file"] as? [String: Any],
               let fid = f["id"] as? Int,
               let local = f["local"] as? [String: Any],
               let done = local["is_downloading_completed"] as? Bool, done,
               let p = local["path"] as? String, !p.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    var changed = false
                    for i in 0..<self.inbox.count
                        where self.inbox[i].imageFileId == fid && self.inbox[i].imageLocalPath == nil {
                        self.inbox[i].imageLocalPath = p
                        changed = true
                    }
                    if changed {
                        NotificationCenter.default.post(name: Self.inboxDidChange, object: nil)
                    }
                }
            }

        case "updateUser":
            if let user = obj["user"] as? [String: Any] {
                cacheUser(user)
            }

        case "user":
            // getMe 返回
            cacheUser(obj)
            if let id = (obj["id"] as? Int64) ?? (obj["id"] as? Int).map(Int64.init) {
                myUserId = id
                myUsername = obj["username"] as? String
            }

        case "error":
            let msg = obj["message"] as? String ?? "?"
            let code = (obj["code"] as? Int) ?? 0
            AppLog.log("TDLib error: code=\(code) msg=\(msg)")
            lastErrorMessage = msg
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.didReceiveError, object: nil,
                    userInfo: ["message": msg, "code": code])
            }

        default:
            break  // 忽略其他类型
        }
    }

    private func handleAuthState(_ stType: String, state: [String: Any]) {
        AppLog.log("TDLib authState: \(stType)")
        switch stType {
        case "authorizationStateWaitTdlibParameters":
            authState = .waitingTdParams
            sendTdlibParameters()
        case "authorizationStateWaitEncryptionKey":
            // 1.8.6+ 已不再走这个状态；保留兼容老版本：传空 key 让它通过
            authState = .waitingEncryptionKey
            send([
                "@type": "checkDatabaseEncryptionKey",
                "encryption_key": "",
            ])
        case "authorizationStateWaitPhoneNumber":
            authState = .waitingPhoneNumber
        case "authorizationStateWaitCode":
            authState = .waitingCode
        case "authorizationStateWaitPassword":
            authState = .waitingPassword
        case "authorizationStateReady":
            authState = .ready
            // 拉取 me 信息
            send(["@type": "getMe"])
            // 加载已有 chat 列表（这样后续 chat_id 能查到信息）
            send([
                "@type": "loadChats",
                "chat_list": ["@type": "chatListMain"],
                "limit": 200,
            ])
        case "authorizationStateLoggingOut":
            authState = .loggingOut
        case "authorizationStateClosed":
            authState = .closed
        default:
            break
        }
    }

    private func sendTdlibParameters() {
        guard let id = apiId, let hash = apiHash else {
            AppLog.log("TDLib: 没有 api_id/api_hash，等待用户配置")
            return
        }
        let supportDir = (Store.shared.dataFilePath as NSString).deletingLastPathComponent
        let tdDir = supportDir + "/tdlib"
        try? FileManager.default.createDirectory(atPath: tdDir, withIntermediateDirectories: true)

        // ★ TDLib 1.8.6+ 用 flat schema：所有字段直接平铺；同时 authorizationStateWaitEncryptionKey
        //   状态被移除，加密密钥（如果用）合并进 setTdlibParameters 的 database_encryption_key 字段。
        //   不加密 → 传空 bytes（base64 空串）。
        let payload: [String: Any] = [
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": tdDir,
            "files_directory": tdDir + "/files",
            "database_encryption_key": "",
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            "use_secret_chats": false,
            "api_id": Int(id),               // 必须 Int，避免 JSONSerialization 把 Int32 变 NSNumber
            "api_hash": hash,
            "system_language_code": "en",
            "device_model": "Mac",
            "system_version": "macOS",
            "application_version": "LazyCat",
        ]
        AppLog.log("TDLib → setTdlibParameters (flat form, 1.8.6+): api_id=\(id) hash.len=\(hash.count) dir=\(tdDir)")
        send(payload)
    }

    /// "解卡"操作：不重建 client（重建会和 receiveLoop 抢 td_receive，TDLib 内部 abort 崩溃）
    /// 只做两件无副作用的事：
    ///   1) 当前 state 仍卡在 waitingTdParams → 再发一次 setTdlibParameters（TDLib 会接收并尝试初始化）
    ///   2) ping getAuthorizationState 让 TDLib 把当前真实状态再吼一次
    /// 如果 TDLib 不爱听（比如已经初始化过了），它会回 error，我们的 didReceiveError 通知会弹 alert。
    func restart() {
        AppLog.log("TDLib restart requested (current state=\(authState.rawValue))")
        // 必须保证 client 已创建；如果没（首次进来），先 start 出来一条 receive 线程
        if clientId == -1 {
            start()
            return
        }
        // 只重发 setTdlibParameters；不要再 ping getAuthorizationState ——
        // 在 waitTdParams 状态下额外发 getAuthorizationState 会触发 TDLib 回 400
        // "Parameters aren't specified"，反而把用户引到错误归因
        if authState == .waitingTdParams || authState == .unknown {
            sendTdlibParameters()
        }
    }

    // MARK: - 消息 → inbox

    private func handleNewMessage(_ msg: [String: Any]) {
        let chatId = parseInt64(msg["chat_id"]) ?? 0
        let messageId = parseInt64(msg["id"]) ?? 0
        let dedupeKey = "\(chatId):\(messageId)"
        guard !seenMessages.contains(dedupeKey) else { return }
        seenMessages.insert(dedupeKey)
        // 限制 dedupe set 大小
        if seenMessages.count > 5000 {
            seenMessages = Set(seenMessages.suffix(2000))
        }

        // 自己发的消息忽略
        let senderId = parseSenderId(msg["sender_id"])
        if senderId == myUserId { return }

        // 提取文字
        let content = msg["content"] as? [String: Any]
        let text: String = {
            if let c = content,
               let inner = c["text"] as? [String: Any],
               let t = inner["text"] as? String {
                return t
            }
            // 图片/视频等可能有 caption
            if let c = content, let caption = c["caption"] as? [String: Any],
               let t = caption["text"] as? String {
                return t
            }
            // content type 名字（音频/贴纸等）
            if let c = content, let ct = c["@type"] as? String {
                return "[\(ct.replacingOccurrences(of: "message", with: ""))]"
            }
            return ""
        }()

        // 图片消息：messagePhoto.photo.sizes 是按宽高排序的多档；取最大那张的 file_id
        var imgFileId: Int? = nil
        var imgLocalPath: String? = nil
        if let c = content, (c["@type"] as? String) == "messagePhoto",
           let photo = c["photo"] as? [String: Any],
           let sizes = photo["sizes"] as? [[String: Any]],
           let biggest = sizes.last,
           let f = biggest["photo"] as? [String: Any],
           let fid = f["id"] as? Int {
            imgFileId = fid
            // local.path 在已经下载到本地时非空；is_downloading_completed=true 才用
            if let local = f["local"] as? [String: Any],
               let done = local["is_downloading_completed"] as? Bool, done,
               let p = local["path"] as? String, !p.isEmpty {
                imgLocalPath = p
            } else {
                // 未下载完成 → 主动触发下载（priority=1 高、synchronous=false 异步）
                send([
                    "@type": "downloadFile",
                    "file_id": fid,
                    "priority": 1,
                    "synchronous": false,
                ])
            }
        }

        let chat = chatCache[chatId]
        let chatType = chat?.type ?? "private"
        let chatTitle = chat?.title ?? "未知聊天"

        // 决定要不要进 inbox
        var shouldShow = false
        var sourceLabel = ""
        if chatType == "private" {
            // 私聊一律进
            shouldShow = true
            sourceLabel = "私聊"
        } else {
            // 群组：只有 @ 我或 reply 我才进
            if isMentioned(text: text, msg: msg) {
                shouldShow = true
                sourceLabel = chatTitle
            }
        }
        guard shouldShow else { return }

        let senderName = nameForSender(senderId)
        let date = Date(timeIntervalSince1970: Double((msg["date"] as? Int) ?? Int(Date().timeIntervalSince1970)))

        var item = InboxMessage(
            id: dedupeKey,
            chatId: chatId,
            messageId: messageId,
            senderId: senderId,
            senderName: senderName,
            chatType: chatType,
            chatTitle: chatTitle,
            sourceLabel: sourceLabel,
            text: text.isEmpty && imgFileId != nil ? "[图片]" : text,
            date: date,
            read: false,
            imageLocalPath: imgLocalPath,
            imageFileId: imgFileId
        )
        item.isMention = chatType != "private" && isMentioned(text: text, msg: msg)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.inbox.insert(item, at: 0)
            // 上限 200 条
            if self.inbox.count > 200 { self.inbox = Array(self.inbox.prefix(200)) }
            NotificationCenter.default.post(name: Self.inboxDidChange, object: nil)
            self.onInboxMessage?(item)
            AppLog.log("TG inbox: [\(sourceLabel)] \(senderName): \(text.prefix(40))…")
        }
    }

    private func isMentioned(text: String, msg: [String: Any]) -> Bool {
        // 简单做法：text 里出现 @username 就算
        if let u = myUsername, !u.isEmpty, text.localizedCaseInsensitiveContains("@" + u) {
            return true
        }
        // 或 message 里 contains_unread_mention = true
        if let flag = msg["contains_unread_mention"] as? Bool, flag { return true }
        return false
    }

    // MARK: - 缓存

    private func cacheChat(_ obj: [String: Any]) {
        guard let id = parseInt64(obj["id"]) else { return }
        let title = (obj["title"] as? String) ?? ""
        let type: String = {
            if let t = obj["type"] as? [String: Any], let typ = t["@type"] as? String {
                switch typ {
                case "chatTypePrivate": return "private"
                case "chatTypeBasicGroup": return "group"
                case "chatTypeSupergroup": return "supergroup"
                case "chatTypeSecret": return "secret"
                default: return "private"
                }
            }
            return "private"
        }()
        chatCache[id] = ChatInfo(id: id, title: title, type: type)
    }

    private func cacheUser(_ obj: [String: Any]) {
        guard let id = parseInt64(obj["id"]) else { return }
        let firstName = obj["first_name"] as? String ?? ""
        let lastName  = obj["last_name"] as? String ?? ""
        let username  = obj["username"] as? String ?? ""
        userCache[id] = UserInfo(id: id, firstName: firstName, lastName: lastName, username: username)
    }

    private func parseSenderId(_ raw: Any?) -> Int64 {
        guard let dict = raw as? [String: Any] else { return 0 }
        if let uid = parseInt64(dict["user_id"]) { return uid }
        if let cid = parseInt64(dict["chat_id"]) { return cid }
        return 0
    }

    private func parseInt64(_ raw: Any?) -> Int64? {
        if let v = raw as? Int64 { return v }
        if let v = raw as? Int { return Int64(v) }
        if let s = raw as? String, let v = Int64(s) { return v }
        return nil
    }

    private func nameForSender(_ id: Int64) -> String {
        if let u = userCache[id] {
            let full = (u.firstName + " " + u.lastName).trimmingCharacters(in: .whitespaces)
            if !full.isEmpty { return full }
            if !u.username.isEmpty { return "@" + u.username }
        }
        if let c = chatCache[id] { return c.title }
        return "用户 \(id)"
    }

    // MARK: - 操作 inbox

    func dismiss(_ id: String) {
        DispatchQueue.main.async {
            self.inbox.removeAll { $0.id == id }
            NotificationCenter.default.post(name: Self.inboxDidChange, object: nil)
        }
    }

    func markAllRead() {
        DispatchQueue.main.async {
            for i in 0..<self.inbox.count { self.inbox[i].read = true }
            NotificationCenter.default.post(name: Self.inboxDidChange, object: nil)
        }
    }

    /// 批量标记指定 id 为已读，一次通知
    func markRead(ids: Set<String>) {
        DispatchQueue.main.async {
            for i in 0..<self.inbox.count where ids.contains(self.inbox[i].id) {
                self.inbox[i].read = true
            }
            NotificationCenter.default.post(name: Self.inboxDidChange, object: nil)
        }
    }

    /// 批量删除，一次通知（避免逐条 dismiss 触发 N 次 refresh）
    func dismissBatch(ids: Set<String>) {
        DispatchQueue.main.async {
            self.inbox.removeAll { ids.contains($0.id) }
            NotificationCenter.default.post(name: Self.inboxDidChange, object: nil)
        }
    }

    func clearAll() {
        DispatchQueue.main.async {
            self.inbox.removeAll()
            NotificationCenter.default.post(name: Self.inboxDidChange, object: nil)
        }
    }
}

// MARK: - 数据模型

struct InboxMessage: Equatable {
    let id: String
    let chatId: Int64
    let messageId: Int64
    let senderId: Int64
    let senderName: String
    let chatType: String     // private / group / supergroup
    let chatTitle: String
    let sourceLabel: String  // 「私聊」 或 群名
    let text: String
    let date: Date
    var read: Bool
    /// 该消息附带的图片本地路径（已下载完成才有值；TDLib 异步推送）
    var imageLocalPath: String? = nil
    /// TDLib 中此图片对应的 file_id；用于异步下载完成后回填 imageLocalPath
    var imageFileId: Int? = nil

    var isPrivate: Bool { chatType == "private" }
    /// 群消息中包含对我的 @ 或 reply
    var isMention: Bool = false
}

struct ChatInfo {
    let id: Int64
    let title: String
    let type: String
}

struct UserInfo {
    let id: Int64
    let firstName: String
    let lastName: String
    let username: String
}
