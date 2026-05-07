#!/bin/bash
# 一键核对：dock / Finder 实际打开的是哪份 LazyCat、是哪次构建、跑没跑起来
set -e
APP_NAME="LazyCat"

echo '================================================================'
echo "  LazyCat 实地巡检  $(date '+%H:%M:%S')"
echo '================================================================'

echo
echo '【1】系统里所有 LazyCat.app（按修改时间倒序）'
find /Applications -maxdepth 4 -type d -name "${APP_NAME}.app" 2>/dev/null \
  | xargs -I{} stat -f '%Sm  %N' {} \
  | sort -r

echo
echo '【2】LaunchServices 注册的 LazyCat 候选（dock 双击会从这里取）'
mdfind 'kMDItemContentType == "com.apple.application-bundle" && kMDItemFSName == "LazyCat.app"' 2>/dev/null

echo
echo '【3】当前正在跑的 LazyCat 进程的真实路径 + PID'
running=$(ps aux | grep -i "LazyCat\.app/Contents/MacOS" | grep -v grep | head -1)
if [ -z "$running" ]; then
    echo "  (没在跑)"
else
    echo "  $running" | awk '{printf "  PID %s  %s\n", $2, $11}'
fi

echo
echo '【4】每个 .app 的版本元数据'
for app in $(find /Applications -maxdepth 4 -type d -name "${APP_NAME}.app" 2>/dev/null) ; do
    echo
    echo "  ─── $app ───"
    pl="$app/Contents/Info.plist"
    printf "    Version          : %s (build %s)\n" \
        "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$pl" 2>/dev/null || echo '?')" \
        "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$pl" 2>/dev/null || echo '?')"
    printf "    Display Name     : %s\n" \
        "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$pl" 2>/dev/null || echo '?')"
    printf "    Build Date       : %s\n" \
        "$(/usr/libexec/PlistBuddy -c 'Print :LazyCatBuildDate' "$pl" 2>/dev/null || echo '(旧 build.sh 没注入此字段)')"
    printf "    Git              : %s\n" \
        "$(/usr/libexec/PlistBuddy -c 'Print :LazyCatGitHash' "$pl" 2>/dev/null || echo '(同上)')"
    printf "    Binary mtime     : %s\n" \
        "$(stat -f '%Sm' "$app/Contents/MacOS/${APP_NAME}" 2>/dev/null || echo '?')"
    printf "    Bundle ID        : %s\n" \
        "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$pl" 2>/dev/null || echo '?')"
done

echo
echo '【5】per-app 暗色 override 状态'
echo "    AppleInterfaceStyle = $(defaults read com.local.mytodo AppleInterfaceStyle 2>/dev/null || echo '(未设置)')"

echo
echo '【6】编译器健康状况'
if echo 'import AppKit' | swiftc - -o /tmp/_lc_probe 2>/dev/null && [ -x /tmp/_lc_probe ] ; then
    rm -f /tmp/_lc_probe
    echo '    ✓ swiftc 工作正常，可以重编 LazyCat'
else
    echo '    ✗ swiftc 还坏着 —— 跑这条修复:'
    echo '      sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap'
fi

echo
echo '================================================================'
