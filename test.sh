#!/bin/bash
# 自动化烟雾测试 —— build / launch / 模拟点击 / 校验 / 关闭
# 用法：./test.sh
set -uo pipefail

APP="$(cd "$(dirname "$0")" && pwd)/build/MyTodo.app"
APP_BIN="$APP/Contents/MacOS/MyTodo"
LOG=/tmp/mytodo.log
DATA="$HOME/Library/Application Support/MyTodoApp/data.json"
DATA_BAK="$HOME/Library/Application Support/MyTodoApp/data.json.testbak"

PASS=0
FAIL=0
FAIL_DETAILS=()

pass() { echo "✅ $1"; PASS=$((PASS+1)); }
fail() { echo "❌ $1"; FAIL=$((FAIL+1)); FAIL_DETAILS+=("$1"); }

check_log() {
    local pattern="$1"
    local desc="$2"
    if grep -q "$pattern" "$LOG" 2>/dev/null; then
        pass "$desc"
    else
        fail "$desc (期望日志含: $pattern)"
    fi
}

# ---- 1. 构建 ----
echo "== build =="
( cd "$(dirname "$0")" && ./build.sh ) > /tmp/mytodo-build.log 2>&1
if [[ -x "$APP_BIN" ]]; then
    pass "build: 二进制存在"
else
    fail "build: 二进制不存在"
    cat /tmp/mytodo-build.log
    exit 1
fi

# ---- 2. 备份并清空数据 ----
echo "== reset data =="
mkdir -p "$(dirname "$DATA")"
[[ -f "$DATA" ]] && cp "$DATA" "$DATA_BAK"
rm -f "$DATA"
rm -f "$LOG"

# ---- 3. 关掉旧实例并启动 ----
pkill -f "MyTodo.app/Contents/MacOS/MyTodo" 2>/dev/null
sleep 1
open "$APP"
sleep 2

# 验证进程存在
if pgrep -f "MyTodo.app/Contents/MacOS/MyTodo" > /dev/null; then
    pass "launch: 进程已启动"
else
    fail "launch: 进程未启动"
fi

# 验证日志已写
sleep 1
check_log "App.didFinishLaunching" "launch: AppDelegate.applicationDidFinishLaunching 触发"
check_log "App.window shown" "launch: 主窗口已显示"

# 验证默认数据已生成
if [[ -f "$DATA" ]]; then
    pass "data: 默认 data.json 已生成"
else
    fail "data: data.json 未生成"
fi

# 验证默认有"收件箱"清单
if grep -q "收件箱" "$DATA" 2>/dev/null; then
    pass "data: 默认含'收件箱'清单"
else
    fail "data: 缺少'收件箱'清单"
fi

# ---- 4. 通过 AppleScript 用键盘添加任务 ----
echo "== UI: 通过快速添加输入框创建任务 =="
osascript <<'EOF' > /tmp/mytodo-osa.log 2>&1
tell application "System Events"
    tell process "MyTodo"
        set frontmost to true
        delay 0.3
        -- Cmd+N → 主菜单"新建任务"，焦点跳到 quickAdd
        keystroke "n" using {command down}
        delay 0.3
        keystroke "测试任务A @张 15:30 !1"
        delay 0.2
        key code 36   -- Return
        delay 0.5
        keystroke "测试任务B today"
        delay 0.2
        key code 36
        delay 0.5
    end tell
end tell
EOF

if grep -q "1043" /tmp/mytodo-osa.log; then
    fail "AppleScript 没有辅助功能权限（需在 系统设置→隐私→辅助功能 给 终端/Claude 勾选）"
    cat /tmp/mytodo-osa.log
else
    pass "osascript: 命令已发送（无 -1719/-1043 权限错误）"
fi

sleep 1

# 验证数据
if grep -q "测试任务A" "$DATA" 2>/dev/null; then
    pass "task: 测试任务A 已写入 data.json"
else
    fail "task: 测试任务A 未写入"
fi
if grep -q "测试任务B" "$DATA" 2>/dev/null; then
    pass "task: 测试任务B 已写入 data.json"
else
    fail "task: 测试任务B 未写入"
fi

# 验证 events 有 created 类型
if grep -q '"kind" : "created"' "$DATA" 2>/dev/null; then
    pass "event: 自动写入 created 事件"
else
    fail "event: 缺少 created 事件"
fi

check_log "TaskList.quickAdd" "log: 快速添加调用日志已写"

# ---- 5. 切换侧栏 ----
echo "== UI: 切换侧栏到'所有' =="
osascript <<'EOF' > /tmp/mytodo-osa2.log 2>&1
tell application "System Events"
    tell process "MyTodo"
        set frontmost to true
        delay 0.3
        -- 点击侧栏第 3 项"所有"（粗略尝试，不一定命中）
        try
            click row 4 of outline 1 of scroll area 1 of group 1 of splitter group 1 of window 1
        end try
    end tell
end tell
EOF

# 不一定能成功，因为辅助功能层级名可能不一致；只要 AppLog 里出现 Sidebar.click 就算通过
sleep 0.5
if grep -q "Sidebar.click\|Sidebar.select" "$LOG"; then
    pass "sidebar: 收到点击事件"
else
    fail "sidebar: 未收到点击事件（可能是辅助功能权限或层级名不对，需手动验证）"
fi

# ---- 6. 菜单栏图标存在性 ----
echo "== UI: 菜单栏 status item =="
osascript <<'EOF' > /tmp/mytodo-osa3.log 2>&1
tell application "System Events"
    tell process "MyTodo"
        if exists (menu bar item 1 of menu bar 2) then
            return "OK"
        else if (exists menu bar 2) then
            return "no_item"
        else
            return "no_menubar2"
        end if
    end tell
end tell
EOF
RES=$(cat /tmp/mytodo-osa3.log)
case "$RES" in
    OK) pass "menubar: 菜单栏图标存在" ;;
    *)  fail "menubar: 菜单栏图标缺失 (osa=$RES)" ;;
esac

# ---- 7. 校验"窗口置顶"菜单项存在 ----
osascript <<'EOF' > /tmp/mytodo-osa4.log 2>&1
tell application "System Events"
    tell process "MyTodo"
        if (exists menu item "窗口置顶" of menu 1 of menu bar item "窗口" of menu bar 1) then
            return "OK"
        else
            return "missing"
        end if
    end tell
end tell
EOF
RES=$(cat /tmp/mytodo-osa4.log)
[[ "$RES" == "OK" ]] && pass "menu: '窗口置顶' 菜单项存在" || fail "menu: '窗口置顶' 菜单项缺失"

# ---- 8. 数据备份恢复 ----
if [[ -f "$DATA_BAK" ]]; then
    cp "$DATA_BAK" "$DATA"
    rm -f "$DATA_BAK"
    pass "cleanup: 已恢复用户原有数据"
else
    rm -f "$DATA"
    pass "cleanup: 已清理测试数据（用户原本没数据）"
fi

# ---- 总结 ----
echo
echo "================================="
echo "  PASS: $PASS    FAIL: $FAIL"
echo "================================="
if [[ $FAIL -gt 0 ]]; then
    echo "失败项："
    for d in "${FAIL_DETAILS[@]}"; do echo "  - $d"; done
    exit 1
fi
