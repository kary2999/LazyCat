# 版本迭代记录

所有值得记的改动都写在这里。日期用当地时区。

格式：`[版本] - YYYY-MM-DD` → `新增 / 变更 / 修复` 三类。

---

## [1.12.4] - 2026-05-22

### 新增
- **TG 面板可折叠**：点 TG 面板左上角 `‹` 按钮收起右栏；右边缘出现 `›` 按钮随时展开；折叠状态持久化（重启后保留）

### 修复
- **初始窗口过小**：autosave key 升为 V5，启动时若检测到已存窗口宽度 < 1200pt 或高度 < 720pt，自动修正为合理尺寸并居中，无需手动拖拽

---

## [1.6.0] - 2026-04-28

### 新增
- **全身招手企鹅**：`PenguinRenderer.swift` —— 24 帧程序化绘制
  - 黑顶 / 白肚 / 橙喙 / 橙脚（QQ 宠物风）
  - **右翅膀挥手**（周期摆动）
  - **眨眼**（每秒两次）
  - 呼吸 + 头微倾
- **悬浮形态简化为 2 种**（菜单栏 ▸ 悬浮形态）
  - 🐱 走动小猫（CatRenderer 24 帧）
  - 🐧 招手小企鹅（PenguinRenderer 24 帧）
- **「关于 LazyCat」面板**（主菜单 → 关于；菜单栏图标也有入口）
  - 显示版本 / 构建时间 / Git hash / Bundle 路径 / 进程 PID
  - 「复制信息」按钮一键复制诊断信息
  - 「在 Finder 中显示」按钮直接定位 .app
- **build.sh 注入 `LazyCatBuildDate` / `LazyCatGitHash`** 到 Info.plist，让用户可验证「这个 binary 是哪次构建」
- **`verify.sh`**：一键巡检（哪些 .app 装在哪、哪个在跑、CLT 是否健康）
- **build.sh 默认 `INSTALL_DIR=/Applications/自研项目/`**，匹配 dock 实际指向；可 `INSTALL_DIR=... bash build.sh --install` 覆盖

### 变更
- **删除悬浮猫的圆形 logo 底盘 + 阴影**（`catHolder` 的 cornerRadius/shadow）
  - 之前不论选什么形态都顶着一个圆白底盘 —— 嫌丑
  - 现在 vector 图层直接显在桌面，透明背景
- **删除所有 emoji 形态**（v1.4.0 加的 12 种 emoji 选择全部移除）
  - 旧 UserDefaults 里存的 1..13 一律 fallback 到默认猫
- **菜单文案**：「悬浮猫样式」→「悬浮形态」、「悬浮猫尺寸」→「悬浮尺寸」

### 修复
- v1.5.0 用户截图问题："企鹅了为啥还是猫头圆背景" → 圆背景已删

---

## [1.5.0] - 2026-04-27

### 新增
- **小企鹅悬浮形态**（菜单栏 ▸ 悬浮猫样式 → 小企鹅 / 极地企鹅）
- **悬浮动画透明度可调**（菜单栏 ▸ 悬浮透明度）30% – 100%
  - **小红点未完成数徽章不参与透明**：永远完全不透明，避免数字被淡掉
- **锁屏快捷键可配置**（菜单栏 ▸ 锁屏快捷键），9 个预设：
  `⌥⌘\``（默认） / `⌃⌥⌘L` / `⇧⌘L` / `⇧⌘D` / `⌃⌥⌘D` / `F13` / `F14` / `⌥⌘.` / `⌃⌥⌘\\` / 关闭
  - 切换后立即重新注册，不需重启
- **不可穿透**：mask 显示期间，⌘Q / ⌘W / ⌘H / ⌘M 全部被吃掉，防止用户绕开密码 quit/close 主窗
- **提醒触发动画升级**：悬浮猫/企鹅 **放大 20%** 持续 5 秒，期间持续上下浮动 + 红色发光环

### 变更
- **多屏锁定真正生效**：之前只盖主屏，现在每个连接的屏幕都铺一扇 mask 窗，且：
  - 用 `CGShieldingWindowLevel()`（系统锁屏 / 快速用户切换的最高 user-mode 级别）盖过其它 app 的全屏 / Dock / 菜单栏
  - 显式 `setFrame(screen.frame)` + `setFrameOrigin` 确保每扇真正贴到目标屏幕
  - 监听 `NSApplication.didChangeScreenParametersNotification`：拔插外屏 / 改分辨率会**实时重铺**，新接屏不暴露桌面
- **深色对比度大幅改善**：根/卡片/输入框改用显式 sRGB 调色板（窗口 #1C1C1E、卡片 #29292E、输入 #21212266、描边 30% 灰），不再依赖系统 dynamic color，避免主题切换时机差导致"浅底浅字"
- **默认强制深色**：`NSApp.appearance = .darkAqua`，**不跟随系统设置**

### 修复
- v1.4.0 截图反馈：背景色与文字颜色过于接近导致看不清
  - 根因：`inputCard` 的 `windowBackgroundColor` 在某些 SDK 上会被 root 透出而显示浅色
  - 修复：所有面板色全部硬编码 sRGB

### 新文件
- `Sources/LockHotKeySettings.swift` — 锁屏快捷键预设管理 + UserDefaults 持久化

---

## [1.4.0] - 2026-04-25

### 新增
- **悬浮猫样式可选**（菜单栏 ▸ 悬浮猫样式）共 12 种：
  - 🐈 走动小猫（默认，程序绘制 24 帧 walk-cycle）
  - 😺 微笑 / 😻 爱心 / 😸 开心 / 😽 亲亲 / 😴 睡眠
  - 🐱 卡哇伊 / 🐈 简笔猫 / 🐯 小老虎 / 🐻 小熊 / 🐰 兔兔 / 🐼 熊猫
- **悬浮猫尺寸三档**（菜单栏 ▸ 悬浮猫尺寸）：
  - 100%（默认 72pt）
  - 50%（36pt）
  - 30%（28pt 起，最小化但仍可点）
  - 红色未完成数徽章 / 字号 都按比例自适应
- 设置变更**实时生效**：调样式/尺寸时悬浮猫立刻在原位置缩放重建（不会跑到屏幕角落）

### 变更
- **主窗口彻底统一深色**：去掉「输入卡片」「文本框」与窗口背景的色差
  - `inputCard.backgroundColor` 改为 `windowBackgroundColor`（之前是 `textBackgroundColor`，比窗口浅一档）
  - `textScroll` 由 `lineBorder + textBackgroundColor` 改为 `noBorder + 透明背景`，仅保留 0.5pt 极淡描边
  - 所有"白色发亮"的卡片感全部消除

### 新文件
- `Sources/FloatingWidgetSettings.swift` — 悬浮猫样式 + 尺寸的 UserDefaults 持久化

---

## [1.3.1] - 2026-04-25

### 兼容性
- **架构**：从 arm64-only 升级为 **universal**（`arm64` + `x86_64`），同一份 .app 可同时跑：
  - Apple Silicon **M1 / M2 / M3 / M4**（原生 arm64）
  - Intel 全系（x86_64，Rosetta 不再需要）
- **最低系统**：从 macOS 12.0 下调至 **macOS 11.0 Big Sur**
  - 原计划下到 10.15 Catalina，但当前 Apple Command Line Tools 工具链与 SDK 版本不一致（compiler swiftlang 6.0.3.1.10 vs SDK swiftlang 6.0.3.1.5），10.15 deployment target 会强制加载 framework 的 textual swiftinterface 触发 mismatch 报错
  - 11.0+ 走预编译 binary swiftmodule 绕过此限制；`UNUserNotificationCenter` / `darkAqua` / `monospacedSystemFont` 等 API 都正常可用
  - 想再降可设环境变量：`MIN_MACOS=10.15 bash build.sh`（需自备完整 Xcode 工具链）
- 测试验证 SDK 中所有调用均可在 10.15 上解析；代码无 Swift Concurrency / 12+ API 依赖

### 工程
- `build.sh` 重写为发行级脚本：
  - 默认 universal 编译（`ARCHS="arm64 x86_64"` 可调）
  - `ad-hoc codesign`（`-`）让 Gatekeeper 至少能识别签名
  - **`bash build.sh --dist`** 一键产出三种发行包到 `dist/`：
    - `MyTodo-VERSION.zip`（`ditto -c -k --keepParent --sequesterRsrc`，保留 macOS 元数据）
    - `MyTodo-VERSION.tar.gz`（Unix 工具链友好）
    - `MyTodo-VERSION.dmg`（拖拽到 Applications 风格，含 `/Applications` 软链）
    - 同时生成 `MyTodo-VERSION.sha256.txt` 校验和
  - `bash build.sh --install` / `--dist` 可叠加

---

## [1.3.0] - 2026-04-20

### 新增
- **滞留天数徽章**（列表每行右上角大号彩色胶囊）
  - 未完成任务按从创建到今天的自然日计算：
    - 1–2 天：灰色  `⏳ N 天未完成`
    - 3–6 天：橙色
    - 7+ 天：红色
  - 已完成任务按 createdAt → completedAt 计算：
    - 当天完成：绿色  `✓ 当天完成`
    - 隔 N 天：绿色  `✓ N 天后完成`
  - 最小单位：**天**；当天建的未完成任务不显示胶囊
- **每小时汇总提醒**（默认）
  - 替代之前"每个任务到点弹 modal + Dock 弹跳"的逐条打扰方式
  - 只要存在未完成任务，每 1 小时投 1 条系统通知：「📋 你还有 N 个未完成任务」
  - 悬浮窗小猫会同步抖动一下
- **菜单栏 ▸ 未完成汇总提醒**：
  - 可选 30 分钟 / 1 小时（默认） / 2 小时 / 4 小时 / **关闭**
  - 子菜单里的「立刻汇总一次」可手动触发

### 变更
- `ReminderEngine` 完全重写：删除每任务 modal 弹窗 / Dock 弹跳 / 逐条通知；仅保留汇总通知
- `TaskRowView` 右上角原提醒时间位置改为滞留/完成胶囊，视觉更显眼

### 修复
- 点名：旧版"逐条提醒"用户容易忽略，现在改成更显眼的"列表内徽章 + 低频汇总"

---

## [1.2.0] - 2026-04-20

### 新增
- **强制深色外观**：`NSApp.appearance = .darkAqua`，解决浅色背景 + 浅色文字低对比度问题
- **遮罩毛玻璃背景**：用 `NSVisualEffectView (.hudWindow / .behindWindow)` 对下方桌面做系统级磨砂，相当于"马赛克打码"（不需要屏幕录制权限）
- **遮罩密码解锁**：必须输入密码 `123456` 才能退出专注模式
  - 主屏中央 520pt 大密码卡片：提示 + SecureTextField（28pt 大字） + 解锁按钮
  - 回车 / 点「解锁退出」提交
  - 错误时红色提示 + 抖动，3 秒自动清错
  - ESC / 鼠标点击不再生效，防止手滑跳出
- **`build.sh --install`**：构建完自动 kill 旧进程 → 覆盖 `/Applications/MyTodo.app` → 刷 LaunchServices → 重启，解决"改动没生效"都是因为在跑旧版的老问题

### 变更
- 遮罩在**所有连接的屏幕**各开一扇；只有**主屏**展示密码输入 UI，副屏只做遮挡 + 显示时钟/任务
- `MaskWindow` 子类化 `NSWindow` 并覆写 `canBecomeKey/Main`，让 SecureTextField 在 borderless 窗口里也能拿到键盘焦点

### 修复
- 主窗口在浅色系统外观下文字/输入框颜色几乎不可见（白字白底）

---

## [1.1.0] - 2026-04-18

### 新增
- **独立的全屏专注遮罩**（`FullscreenMaskController`）
  - 覆盖所有连接的屏幕，级别 `.screenSaver`，盖过 Dock / 菜单栏 / 其它 app
  - 居中显示大时钟 + 日期 + 当前最高优先级未完成任务
  - 没有待办时显示「✨ 没有待办 — 尽情休息」
- **遮罩透明度可调**（10% – 100%，共 10 档预设）
- **遮罩字号可调**（小 / 中 / 大 / 超大 4 档，影响时钟 / 日期 / 任务文字）
- **全局快捷键 ⌥⌘\`**：任何 app 前台都能呼出/关闭遮罩（Carbon `RegisterEventHotKey`，不需要辅助功能权限）
- **主菜单 ⇧⌘D**：app 前台时切换遮罩
- **猫头 app 图标**（Dock / Finder / 任务切换器）
  - `CatRenderer.makeAppIcon` 渲染猫头特写 + 粉色 squircle 底
  - `build.sh` 构建时自动产出 10 档 `.icns`
- **已有任务补填 / 修改 @人名**
  - 列表行里未指定人名显示为橘色「@未指定（点击补填）」
  - 优先级菜单新增「补填 @人名…」「修改 @xx…」项
  - 详情页 meta 区整段点击可改
  - 弹窗带历史模糊提示 ComboBox，空串会被拒（保持必填语义）

### 变更
- **优先级标签**：`无 / P1 / P2 / TOP` → `无 / T2 / T1 / T0`（rawValue 不变，T0 仍为最高）
- **运行时 Dock 图标**改用猫头特写版 `CatRenderer.makeAppIcon`
- `Info.plist` 新增 `CFBundleIconFile=AppIcon`，版本号 1.0 → 1.1.0

### 修复
- (无)

---

## [1.0.0] - 初始版本

- 最小可用的事件记录 app：输入框 + 进行中 / 已完成 Tab + 列表
- 可贴图 / 拖图到正文，图片文件名保存在 `images/`
- @人名历史模糊提示（NSComboBox）
- 4 档彩色优先级
- 定时提醒（ReminderEngine）+ 系统通知
- 桌面悬浮窗（猫咪徽标 + 展开列表）
- 顶部菜单栏常驻图标 + 背景透明度设置
- 任务详情面板（长文编辑 / 改优先级 / 改提醒 / 改备注）
- 本地 JSON 存储于 `~/Library/Application Support/MyTodoApp/`
