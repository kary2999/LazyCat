#!/bin/bash
# 编译 + 打包发行的一站式脚本
#   - 默认产出 universal (arm64 + x86_64) binary，覆盖 Intel + M1~M4
#   - 最低系统 macOS 10.15
#
# 用法：
#   bash build.sh                  # 仅编译，输出 build/MyTodo.app
#   bash build.sh --install        # 编译 + 覆盖 /Applications + 重启
#   bash build.sh --dist           # 编译 + 产出 dist/MyTodo-VERSION.{zip,dmg,tar.gz}
#   bash build.sh --dist --install # 全做
#
# 环境变量：
#   ARCHS="arm64 x86_64"           # 默认两个；只想 ARM 就 ARCHS=arm64
#   MIN_MACOS=10.15                # 最低系统
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="LazyCat"
LEGACY_APP_NAMES=("MyTodo")    # 旧名 .app 在 /Applications 里也清掉，避免出现两份
BUNDLE="build/${APP_NAME}.app"
MACOS_DIR="${BUNDLE}/Contents/MacOS"
RES_DIR="${BUNDLE}/Contents/Resources"
# ★ 安装目标目录 —— 默认装到 /Applications/自研项目/，匹配用户 Dock 实际指向
#   想换：INSTALL_DIR="/Applications" bash build.sh --install
INSTALL_DIR=${INSTALL_DIR:-"/Applications/自研项目"}
ARCHS=${ARCHS:-"arm64"}                    # 默认仅 arm64（M1–M4），编译只要 ~30s
                                            # 想出 universal：ARCHS="arm64 x86_64" bash build.sh
                                            # 走 Rosetta 2 时 Intel Mac 也能跑 arm64 版（首次启动会提示装）
# 注：受 CLT 工具链 vs SDK 版本同步性影响，10.15 下加载 textual swiftinterface 容易
# 报 SDK / 编译器 version mismatch。11.0 之后多数 framework 走预编译 binary swiftmodule，
# 稳定得多。用户机至少 M1（macOS 11 起）就够用。
MIN_MACOS=${MIN_MACOS:-"12.0"}
SWIFTC=${SWIFTC:-"swiftc"}

# 从 Info.plist 读版本，给打包文件命名
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
echo "==> ${APP_NAME} v${VERSION}  archs=[${ARCHS}]  min macOS=${MIN_MACOS}"

DO_INSTALL=0
DO_DIST=0
for arg in "$@"; do
    case "$arg" in
        --install) DO_INSTALL=1 ;;
        --dist)    DO_DIST=1 ;;
    esac
done

echo "==> 清理 build/（保留 dist/ 里历史版本不动）"
rm -rf build
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "==> 复制 Info.plist + 注入 build timestamp / git hash"
cp Info.plist "${BUNDLE}/Contents/Info.plist"

# 构建时戳 + git short hash —— 让用户从"关于"面板看到这次跑的是哪次构建
BUILD_TIME=$(date '+%Y-%m-%d %H:%M:%S %Z')
GIT_HASH=$(git -C "$(pwd)" rev-parse --short HEAD 2>/dev/null || echo "no-git")
GIT_DIRTY=$(git -C "$(pwd)" diff --quiet 2>/dev/null && echo "" || echo "+dirty")
/usr/libexec/PlistBuddy -c "Add :LazyCatBuildDate string ${BUILD_TIME}" "${BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LazyCatGitHash  string ${GIT_HASH}${GIT_DIRTY}" "${BUNDLE}/Contents/Info.plist"
echo "    BuildDate=${BUILD_TIME}  GitHash=${GIT_HASH}${GIT_DIRTY}"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
SWIFT_SOURCES=(Sources/*.swift)

# ── TDLib 库（开发机用 brew，分发时拷进 .app/Contents/Frameworks/）─────────
TDLIB_PREFIX="/opt/homebrew/opt/tdlib"
SSL_PREFIX="/opt/homebrew/opt/openssl@3"
if [ ! -f "${TDLIB_PREFIX}/lib/libtdjson.dylib" ]; then
    echo "!! 没找到 TDLib，请先：brew install tdlib"
    exit 1
fi

# 每个架构编译一次，最后 lipo 合体
THIN_BINS=()
for arch in $ARCHS; do
    echo "==> 编译 ${arch}（target ${arch}-apple-macos${MIN_MACOS}）"
    out="build/${APP_NAME}-${arch}"
    $SWIFTC \
        -wmo -Onone \
        -target "${arch}-apple-macos${MIN_MACOS}" \
        -sdk "$SDK" \
        -L "${TDLIB_PREFIX}/lib" \
        -ltdjson \
        "${SWIFT_SOURCES[@]}" \
        -o "$out"
    THIN_BINS+=("$out")
done

if [ "${#THIN_BINS[@]}" -gt 1 ]; then
    echo "==> lipo 合并 ${#THIN_BINS[@]} 个架构 → universal"
    lipo -create "${THIN_BINS[@]}" -output "${MACOS_DIR}/${APP_NAME}"
else
    cp "${THIN_BINS[0]}" "${MACOS_DIR}/${APP_NAME}"
fi
chmod +x "${MACOS_DIR}/${APP_NAME}"
echo "    架构信息: $(lipo -archs "${MACOS_DIR}/${APP_NAME}")"

echo "==> 复制 Assets/* 到 Bundle Resources"
if [ -d Assets ]; then
    # 把 Assets/*.png 等图直接放进 Resources，运行时通过 Bundle.main.url 找
    for f in Assets/*; do
        [ -e "$f" ] || continue
        cp "$f" "${RES_DIR}/"
        echo "    + $(basename "$f")"
    done
fi

echo "==> 生成 AppIcon.icns (猫头)"
ICONSET_DIR="build/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
"${MACOS_DIR}/${APP_NAME}" --gen-icon "$ICONSET_DIR" >/dev/null 2>&1 || true
if [ -f "$ICONSET_DIR/icon_512x512@2x.png" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "${RES_DIR}/AppIcon.icns"
    echo "    ok → ${RES_DIR}/AppIcon.icns"
else
    echo "    警告：--gen-icon 没生成 png，跳过 .icns"
fi

# ── 把 libtdjson + openssl 拷进 Frameworks/，改 install_name 让用户机不依赖 brew ──
echo "==> 打包 TDLib + OpenSSL 到 Frameworks/"
FW_DIR="${BUNDLE}/Contents/Frameworks"
mkdir -p "$FW_DIR"

# 自动发现 brew 装出来的 libtdjson 真实文件名（不同版本 1.8.0 / 1.8.63 / ... 不一样）
TDJSON_REAL=$(basename "$(readlink -f "${TDLIB_PREFIX}/lib/libtdjson.dylib")")
if [ -z "$TDJSON_REAL" ] || [ "$TDJSON_REAL" = "libtdjson.dylib" ]; then
    # 兜底：扫真实文件
    TDJSON_REAL=$(basename "$(ls "${TDLIB_PREFIX}/lib/"libtdjson.*.dylib 2>/dev/null | head -1)")
fi
if [ -z "$TDJSON_REAL" ]; then
    echo "✗ 找不到 libtdjson.X.Y.Z.dylib"
    exit 1
fi
echo "    检测到 TDLib 真实文件名: $TDJSON_REAL"

# 1. 拷主 dylib（用真实带版本号文件名；同时建 symlink libtdjson.dylib）
cp "${TDLIB_PREFIX}/lib/${TDJSON_REAL}" "$FW_DIR/"
( cd "$FW_DIR" && ln -sf "${TDJSON_REAL}" libtdjson.dylib )

# 2. 拷 openssl
cp "${SSL_PREFIX}/lib/libssl.3.dylib" "$FW_DIR/"
cp "${SSL_PREFIX}/lib/libcrypto.3.dylib" "$FW_DIR/"

# 3. 改各 dylib 的 LC_ID + 内部依赖路径
for lib in "${TDJSON_REAL}" libssl.3.dylib libcrypto.3.dylib; do
    install_name_tool -id "@executable_path/../Frameworks/$lib" "$FW_DIR/$lib"
done
# tdjson 的 ssl/crypto 依赖
install_name_tool \
    -change "${SSL_PREFIX}/lib/libssl.3.dylib" "@executable_path/../Frameworks/libssl.3.dylib" \
    -change "${SSL_PREFIX}/lib/libcrypto.3.dylib" "@executable_path/../Frameworks/libcrypto.3.dylib" \
    "$FW_DIR/${TDJSON_REAL}"
# libssl 依赖 libcrypto
install_name_tool \
    -change "${SSL_PREFIX}/lib/libcrypto.3.dylib" "@executable_path/../Frameworks/libcrypto.3.dylib" \
    "$FW_DIR/libssl.3.dylib"

# 4. 主二进制原本链 brew 路径，改成 @executable_path
install_name_tool \
    -change "${TDLIB_PREFIX}/lib/${TDJSON_REAL}" "@executable_path/../Frameworks/${TDJSON_REAL}" \
    "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true

echo "    Frameworks/ 内容："
ls -lh "$FW_DIR/" | tail -n +2 | awk '{print "    " $9 "  " $5}'

# 用 ad-hoc 签名让 Gatekeeper 至少能识别，避免每次 open 弹"无法验证开发者"
echo "==> ad-hoc 代签 (避免 Gatekeeper 拦截)"
# 注意：ad-hoc 每次重编 CDHash 都变，TCC（输入监控）会失效 → 用户必须每次重装后
#       手动去「系统设置 → 输入监控」删除旧 LazyCat 记录再重新允许。
#       菜单栏 →「权限失效？重置并重新申请…」会引导这套流程。
codesign --force --deep --sign - "${BUNDLE}" 2>&1 | tail -3 || true

# 触摸 bundle，让 Finder 重读图标
touch "${BUNDLE}"

echo ""
echo "==> 完成: ${BUNDLE}  v${VERSION}"

# ─────────────────────────────────────────
# 安装到 /Applications
# ─────────────────────────────────────────
if [ "$DO_INSTALL" = "1" ]; then
    # ★ 安全检查：必须真的编出可执行文件才动 INSTALL_DIR
    if [ ! -x "${MACOS_DIR}/${APP_NAME}" ]; then
        echo "!! 跳过 --install：build 没产出可执行文件 ${MACOS_DIR}/${APP_NAME}"
        echo "   （swiftc 编译失败 -> 详情 /tmp/mytodo-build.log）"
        echo "   ${INSTALL_DIR} 里旧版本保持不动"
        exit 1
    fi

    INSTALLED="${INSTALL_DIR}/${APP_NAME}.app"
    echo "==> --install: 覆盖到 ${INSTALLED}"

    mkdir -p "${INSTALL_DIR}"
    pkill -x "${APP_NAME}" 2>/dev/null || true
    # 清理一切可能的旧位置 —— 防止"装了新的但 Dock 还指向老的"
    for legacy in "${LEGACY_APP_NAMES[@]}"; do
        pkill -x "${legacy}" 2>/dev/null || true
        rm -rf "/Applications/${legacy}.app" 2>/dev/null || true
        rm -rf "/Applications/自研项目/${legacy}.app" 2>/dev/null || true
    done
    # 同名 LazyCat.app 出现在 /Applications 顶层也是误装位置 —— 也清理
    if [ "${INSTALLED}" != "/Applications/${APP_NAME}.app" ]; then
        rm -rf "/Applications/${APP_NAME}.app" 2>/dev/null || true
    fi
    sleep 0.3
    rm -rf "${INSTALLED}"
    cp -R "${BUNDLE}" "${INSTALLED}"
    touch "${INSTALLED}"
    /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "${INSTALLED}" >/dev/null 2>&1 || true
    rm -f /tmp/mytodo.log
    open "${INSTALLED}"
    echo "    已启动 ${INSTALLED}"
    # 自我打印一次"装了什么"，方便用户对照
    echo "    版本: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INSTALLED}/Contents/Info.plist")"
    echo "    构建: $(/usr/libexec/PlistBuddy -c 'Print :LazyCatBuildDate' "${INSTALLED}/Contents/Info.plist" 2>/dev/null || echo unknown)"
    echo "    git:  $(/usr/libexec/PlistBuddy -c 'Print :LazyCatGitHash' "${INSTALLED}/Contents/Info.plist" 2>/dev/null || echo unknown)"
fi

# ─────────────────────────────────────────
# 发布包 dist/
# ─────────────────────────────────────────
if [ "$DO_DIST" = "1" ]; then
    DIST_DIR="dist"
    mkdir -p "$DIST_DIR"
    BASE="${APP_NAME}-${VERSION}"

    echo ""
    echo "==> 打 ZIP（ditto，保留 macOS 属性）"
    ZIP_OUT="${DIST_DIR}/${BASE}.zip"
    /usr/bin/ditto -c -k --keepParent --sequesterRsrc "${BUNDLE}" "${ZIP_OUT}"
    echo "    → ${ZIP_OUT} ($(du -h "${ZIP_OUT}" | cut -f1))"

    echo "==> 打 tar.gz"
    TGZ_OUT="${DIST_DIR}/${BASE}.tar.gz"
    /usr/bin/tar -czf "${TGZ_OUT}" -C build "${APP_NAME}.app"
    echo "    → ${TGZ_OUT} ($(du -h "${TGZ_OUT}" | cut -f1))"

    echo "==> 打 DMG（拖拽到 Applications 风格）"
    DMG_OUT="${DIST_DIR}/${BASE}.dmg"
    DMG_STAGE="build/dmg-stage"
    rm -rf "$DMG_STAGE"
    mkdir -p "$DMG_STAGE"
    cp -R "${BUNDLE}" "${DMG_STAGE}/"
    # 在 dmg 里加一个指向 /Applications 的符号链接，方便用户拖拽
    ln -s /Applications "${DMG_STAGE}/Applications"
    rm -f "${DMG_OUT}"
    hdiutil create \
        -volname "${APP_NAME} ${VERSION}" \
        -srcfolder "${DMG_STAGE}" \
        -ov -format UDZO \
        "${DMG_OUT}" >/dev/null
    echo "    → ${DMG_OUT} ($(du -h "${DMG_OUT}" | cut -f1))"

    # 校验和
    echo ""
    echo "==> SHA-256"
    (cd "${DIST_DIR}" && shasum -a 256 "${BASE}.zip" "${BASE}.tar.gz" "${BASE}.dmg" | tee "${BASE}.sha256.txt")

    echo ""
    echo "==> 发布产物在 ./${DIST_DIR}/"
    ls -lah "${DIST_DIR}/"
fi

if [ "$DO_INSTALL" = "0" ] && [ "$DO_DIST" = "0" ]; then
    echo ""
    echo "双击打开："
    echo "  open \"$(pwd)/${BUNDLE}\""
    echo ""
    echo "一键安装并启动："
    echo "  bash build.sh --install"
    echo ""
    echo "打发布包（zip / tar.gz / dmg）："
    echo "  bash build.sh --dist"
fi
