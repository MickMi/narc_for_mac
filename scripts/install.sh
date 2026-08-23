#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_CONFIG="${NARC_BUILD_CONFIG:-release}"
INSTALL_ROOT="${NARC_INSTALL_DIR:-${HOME}/Applications}"
TARGET_APP="${INSTALL_ROOT}/NARC.app"
BUILT_APP="${PROJECT_DIR}/build/NARC.app"
SKIP_LAUNCH="${NARC_SKIP_LAUNCH:-0}"

fail() {
    printf '\n❌ %s\n' "$1" >&2
    exit "${2:-1}"
}

if [ "$(uname -s)" != "Darwin" ]; then
    fail "NARC 只支持 macOS 14 或更高版本。" 2
fi

MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if ! [[ "$MACOS_MAJOR" =~ ^[0-9]+$ ]] || [ "$MACOS_MAJOR" -lt 14 ]; then
    fail "当前 macOS 版本过低；请升级到 macOS 14 或更高版本。" 2
fi

if ! command -v swift >/dev/null 2>&1; then
    fail "缺少 Xcode Command Line Tools。请先运行：xcode-select --install" 2
fi

case "$BUILD_CONFIG" in
    debug|release) ;;
    *) fail "NARC_BUILD_CONFIG 只能是 debug 或 release。" 2 ;;
esac

case "$SKIP_LAUNCH" in
    0|1) ;;
    *) fail "NARC_SKIP_LAUNCH 只能是 0 或 1。" 2 ;;
esac

case "$INSTALL_ROOT" in
    ""|"/") fail "安装目录不安全；请设置一个具体的 NARC_INSTALL_DIR。" 2 ;;
esac

if [ "$SKIP_LAUNCH" != "1" ] && pgrep -x NARC >/dev/null 2>&1; then
    fail "NARC 正在运行。请先在 NARC 菜单选择 Quit NARC，然后重新运行：bash scripts/install.sh" 3
fi

printf '🔨 正在构建 NARC（%s）…\n' "$BUILD_CONFIG"
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/narc-build.XXXXXX.log")"
if ! bash "${SCRIPT_DIR}/build-app.sh" "$BUILD_CONFIG" >"$BUILD_LOG" 2>&1; then
    printf '\n构建日志：\n' >&2
    cat "$BUILD_LOG" >&2
    rm -f "$BUILD_LOG"
    fail "构建失败；请保留上方日志并在 GitHub 提交 Issue。" 4
fi
rm -f "$BUILD_LOG"

if [ ! -d "$BUILT_APP" ]; then
    fail "构建未产生 build/NARC.app；请保留上方错误并在 GitHub 提交 Issue。" 4
fi

mkdir -p "$INSTALL_ROOT"

STAGING_APP="${INSTALL_ROOT}/.NARC.app.installing.$$"
BACKUP_APP="${INSTALL_ROOT}/.NARC.app.backup.$$"

cleanup() {
    if [ -e "$STAGING_APP" ]; then
        rm -rf "$STAGING_APP"
    fi
    if [ -e "$BACKUP_APP" ] && [ ! -e "$TARGET_APP" ]; then
        mv "$BACKUP_APP" "$TARGET_APP"
    fi
}
trap cleanup EXIT

/usr/bin/ditto "$BUILT_APP" "$STAGING_APP"
codesign --verify --deep --strict "$STAGING_APP"

if [ -e "$TARGET_APP" ]; then
    mv "$TARGET_APP" "$BACKUP_APP"
fi

mv "$STAGING_APP" "$TARGET_APP"

if [ -e "$BACKUP_APP" ]; then
    rm -rf "$BACKUP_APP"
fi
trap - EXIT

if [ "$SKIP_LAUNCH" = "1" ]; then
    printf '\n✅ NARC 已安装到：%s\n' "$TARGET_APP"
    printf '   启动：open "%s"\n' "$TARGET_APP"
else
    open "$TARGET_APP"
    printf '\n✅ NARC 已安装并启动。\n'
fi

printf '\n只需记住：\n'
printf '  1. 点击桌面悬浮 N：查看消息和窗口\n'
printf '  2. 按 ⌃⌥Q：快速记录 Todo 或 Note\n'
printf '  3. 首次使用窗口快捷键时，按引导开启辅助功能权限\n'
