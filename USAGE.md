# MyTodo 使用说明

一个极简的 macOS 本地事件记录 app。所有数据存在本地 JSON，不联网、不云同步。

- 存储位置：`~/Library/Application Support/MyTodoApp/data.json`
- 图片目录：`~/Library/Application Support/MyTodoApp/images/`
- 运行日志：`/tmp/mytodo.log`

---

## 1. 系统兼容性 (v1.3.1)

| 项 | 支持 |
|---|---|
| 芯片 | **Apple Silicon M1 / M2 / M3 / M4** + **Intel x86_64** （universal binary，单文件覆盖） |
| 最低 macOS | **11.0 Big Sur** 及以上 |
| 推荐 macOS | 12.0+（深色外观和通知更稳） |

## 2. 构建与启动

```bash
cd MyTodoApp

# 仅编译，输出 build/MyTodo.app
bash build.sh

# 编译 + 自动覆盖 /Applications/MyTodo.app + 重启
bash build.sh --install

# 编译 + 产出三种发行包到 dist/
bash build.sh --dist
#   → dist/MyTodo-VERSION.zip    （ditto 的 macOS 友好 zip）
#   → dist/MyTodo-VERSION.dmg    （拖到 /Applications 风格）
#   → dist/MyTodo-VERSION.tar.gz （Unix 工具链友好）
#   → dist/MyTodo-VERSION.sha256.txt

# 全做（编译 + 装 + 打发行包）
bash build.sh --dist --install
```

**仅编译 ARM**（如不需要 Intel 兼容、加快编译速度）：
```bash
ARCHS=arm64 bash build.sh
```

**调最低系统**（默认 11.0）：
```bash
MIN_MACOS=12.0 bash build.sh   # 调高
MIN_MACOS=10.15 bash build.sh  # 调低（需自备版本一致的 Xcode 工具链）
```

要求：Xcode Command Line Tools（提供 `swiftc` / `iconutil` / `lipo` / `hdiutil` / `ditto` / `codesign`）。

---

## 2. 界面速览

```
┌─────────────────────────────────────────┐
│ 🐱 滴答清单 Lite                       │
│ ┌─── 输入卡片 ─────────────────────────┐ │
│ │ [人名(必填) ▾] [无 T2 T1 T0] 🕒  添加 │ │
│ │ ┌ 正文 (最多 2000 字，支持贴图) ────┐ │
│ │ │                                    │ │
│ │ └────────────────────────────────────┘ │
│ │ [缩略图……]                           │ │
│ └────────────────────────────────────────┘ │
│ [进行中(3)] [已完成(12)]                 │
│ ● 事件标题                       🕒  📎  │
│   @张三 · 今天 14:30              T1 ×  │
│ ●  …                                      │
└─────────────────────────────────────────┘
```

---

## 3. 基础操作

### 3.1 录入事件
1. 在顶部**人名**下拉里输入 / 选择一个人（**必填**，历史会模糊匹配）
2. 选优先级：`无 / T2 / T1 / T0`（T0 最高）
3. 可选：点「🕒 定时」选一个未来时间，到点系统通知提醒
4. 正文框可**直接贴图 / 拖图**（图片会保存在 `images/`）
5. 回车 / 点「添加」提交

### 3.2 列表行
- **单击行** → 打开详情（可编辑长文 / 图 / 备注 / 优先级 / 提醒）
- **双击圆圈** → 标记完成 / 取消完成（单击会闪「双击完成」提示，防误触）
- **单击优先级胶囊** → 弹出菜单，可改优先级、**补填/修改 @人名**、改/删提醒
- **单击橘色 "@未指定（点击补填）"** → 直接弹窗补填人名（历史模糊提示）
- **单击图片缩略图** → 系统预览打开
- **单击 ×** → 删除（会再确认）

### 3.3 详情面板
- 正文自动保存（停止打字 0.6s 落盘 / 失焦 / 关窗 / 标记完成 / 删除都会提交）
- 点 meta 一行（`@xxx · 创建…`）可直接修改人名
- ESC 关闭

---

## 4. 悬浮窗（猫咪徽标）

启动时自动显示在桌面右上角。

- **点击小猫** → 展开成进行中列表（320×420）
- **拖拽小猫** → 移动位置（自动记住）
- **收到提醒** → 小猫会抖动 + 红色闪烁 3 秒，强制收起以免挡事
- 展开面板上的「–」→ 重新收回徽标
- 在**菜单栏 → 桌面悬浮窗** 或 **⇧⌘F** 整体开关

---

## 5. 全屏专注遮罩（v1.1 新增）⭐

盖住整个屏幕的半透明遮罩，居中显示时钟 + 当前最高优先级任务，逼自己只看一件事。

### 呼出方式
| 快捷键 | 场景 |
|---|---|
| `⇧⌘D` | MyTodo 在前台时切换 |
| `⌥⌘\`` | **全局热键**，任何 app 前台都能呼出/关闭 |
| 菜单栏 → 专注遮罩（全屏） | 鼠标操作 |

### 退出方式
- 按 **ESC**
- **点击**任意处
- 再按 `⌥⌘\`` / `⇧⌘D`

### 可调项（菜单栏图标展开）
- **遮罩透明度**：10% / 20% / 30% / 40% / 50% / 60% / 70% / 82%(默认) / 90% / 100%
  - 越低越能隐约看见桌面原貌（半专注）；越高越暗（深度专注）
- **遮罩字号**：小 / 中（默认） / 大 / 超大

设置会保存到 `UserDefaults`，下次启动保持。遮罩开着改设置也会**实时生效**。

---

## 6. 菜单栏图标菜单

点顶部菜单栏猫咪图标：
- 打开主窗口
- 新建事件（聚焦输入框）
- 桌面悬浮窗（开关）
- **专注遮罩（全屏） ⇧⌘D / ⌥⌘\`**（v1.1）
- **遮罩透明度 ▸**（v1.1）
- **遮罩字号 ▸**（v1.1）
- 背景透明度 ▸（主窗口）
- 在 Finder 中显示数据
- 退出

---

## 7. 键盘速查

| 快捷键 | 作用 |
|---|---|
| `⌘N` | 新建事件（聚焦人名框） |
| `⌘0` | 显示主窗口 |
| `⌘Q` | 退出 |
| `⇧⌘F` | 桌面悬浮窗开关 |
| `⇧⌘D` | 专注遮罩（app 前台） |
| `⌥⌘\`` | **全局**专注遮罩 |
| `⌘S` / 失焦 | 详情页保存正文（自动） |
| `ESC` | 详情页关闭 / 退出遮罩 |

---

## 8. 故障排查

| 问题 | 解决 |
|---|---|
| 按 `⌥⌘\`` 没反应 | 看 `/tmp/mytodo.log` 是否有 `GlobalHotKey.register OK`。若是 `FAIL status=-9878` 说明热键被其他 app 占了，需退出冲突方；若注册 OK 但按键无 `.fired` 日志，可能被 Karabiner/第三方输入法拦截 |
| Dock 图标还是老样 | macOS icon 缓存，跑 `killall Dock; killall Finder` |
| 看不到任何数据 | 菜单栏 → 在 Finder 中显示数据 检查 `data.json` 是否存在 |
| 遮罩遮不住全屏 app | 遮罩级别 `.screenSaver` 已经是系统最高，只有极少数真全屏视频 app 会盖过它 |
| 悬浮猫被拖丢了 | 关闭再开一次，会自动归位到主屏右上角 |

---

## 9. 测试

```bash
bash test.sh            # 跑 SelfTest.run() 里定义的冒烟用例
./build/MyTodo.app/Contents/MacOS/MyTodo --self-test
```

---

完整版本历史见 [`CHANGELOG.md`](./CHANGELOG.md)。

---

## 10. 发行包安装（给最终用户）

如果你拿到的是 dist/ 里的发行包，三种格式任选：

### ZIP / TAR.GZ
```bash
# zip
unzip MyTodo-1.3.1.zip
mv MyTodo.app /Applications/
xattr -dr com.apple.quarantine /Applications/MyTodo.app   # 第一次开会被 Gatekeeper 拦，去掉隔离属性
open /Applications/MyTodo.app

# tar.gz
tar -xzf MyTodo-1.3.1.tar.gz
mv MyTodo.app /Applications/
xattr -dr com.apple.quarantine /Applications/MyTodo.app
open /Applications/MyTodo.app
```

### DMG（推荐）
1. 双击 `MyTodo-1.3.1.dmg`
2. 把 `MyTodo.app` 拖到旁边的 `Applications` 文件夹
3. 第一次启动如果系统说"无法验证开发者"：
   - 右键 / Control 单击 `MyTodo.app` → 「打开」→ 再点「打开」
   - 或终端：`xattr -dr com.apple.quarantine /Applications/MyTodo.app`

### 校验完整性
```bash
shasum -a 256 -c MyTodo-1.3.1.sha256.txt
```
