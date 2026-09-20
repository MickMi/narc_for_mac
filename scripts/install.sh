#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_CONFIG="${NARC_BUILD_CONFIG:-release}"
INSTALL_ROOT="${NARC_INSTALL_DIR:-${HOME}/Applications}"
TARGET_APP="${INSTALL_ROOT}/NARC.app"
BUILT_APP="${PROJECT_DIR}/build/NARC.app"
SKIP_LAUNCH="${NARC_SKIP_LAUNCH:-0}"
INSTALL_MODE="normal"
MARKER_DIR="${HOME}/Library/Application Support/NARC"
MARKER_PATH="${MARKER_DIR}/signing-identity.sha1"
CURRENT_SIGN_IDENTITY=""
TRANSACTION_COMMITTED=0
APP_SWITCHED=0
LOCKF_BIN="/usr/bin/lockf"
INSTALL_LOCK_PATH="${MARKER_DIR}/install.lock"
INSTALL_LOCK_HELD=0
STAGING_APP=""
BACKUP_APP=""
FAILED_APP=""
MARKER_STAGING=""
MARKER_BACKUP=""

# shellcheck source=lib/install-transaction.sh
source "${SCRIPT_DIR}/lib/install-transaction.sh"

fail() {
    printf '\n❌ %s\n' "$1" >&2
    exit "${2:-1}"
}

acquire_install_lock() {
    [ -x "$LOCKF_BIN" ] || fail "缺少 macOS 安装互斥工具：$LOCKF_BIN" 2
    [ ! -L "$MARKER_DIR" ] \
        || fail "NARC 应用数据目录不能是符号链接：$MARKER_DIR" 4
    mkdir -p "$MARKER_DIR" || fail "无法创建 NARC 应用数据目录。" 4
    [ -d "$MARKER_DIR" ] || fail "NARC 应用数据路径不是目录。" 4
    [ "$(stat -f '%u' "$MARKER_DIR")" = "$(id -u)" ] \
        || fail "NARC 应用数据目录不属于当前用户；拒绝创建安装锁。" 4
    chmod 700 "$MARKER_DIR" || fail "无法保护 NARC 应用数据目录。" 4
    [ ! -L "$INSTALL_LOCK_PATH" ] \
        || fail "安装锁不能是符号链接：$INSTALL_LOCK_PATH" 4
    if [ -e "$INSTALL_LOCK_PATH" ] && [ ! -f "$INSTALL_LOCK_PATH" ]; then
        fail "安装锁路径存在但不是普通文件：$INSTALL_LOCK_PATH" 4
    fi

    # lockf operates on an inherited descriptor. The file is intentionally
    # retained: kernel lock ownership, not file existence or a reusable PID,
    # is the source of truth, so crashed installers leave no stale lock state.
    exec 9>>"$INSTALL_LOCK_PATH" \
        || fail "无法打开当前用户的 NARC 安装锁。" 5
    chmod 600 "$INSTALL_LOCK_PATH" \
        || { exec 9>&-; fail "无法保护当前用户的 NARC 安装锁。" 5; }
    if ! "$LOCKF_BIN" -s -t 0 9; then
        exec 9>&-
        fail "另一个 NARC 安装正在进行；本次未构建或替换任何文件。" 5
    fi

    INSTALL_LOCK_HELD=1
    trap narc_install_early_cleanup EXIT
    narc_install_arm_signal_handlers
}

case "$#" in
    0) ;;
    1)
        [ "$1" = "--restore-legacy-signer" ] \
            || fail "未知参数：$1" 2
        INSTALL_MODE="restore-legacy"
        ;;
    *) fail "用法：bash scripts/install.sh [--restore-legacy-signer]" 2 ;;
esac

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

if [ -L "$TARGET_APP" ]; then
    fail "安装目标不能是符号链接：$TARGET_APP" 3
fi
if [ -e "$TARGET_APP" ] && [ ! -d "$TARGET_APP" ]; then
    fail "安装目标已存在但不是 NARC.app 目录：$TARGET_APP" 3
fi

case "${NARC_INTERNAL_INSTALL_LOCK_TEST:-0}" in
    0) ;;
    1)
        case "${NARC_INTERNAL_INSTALL_LOCK_HOLD_SECONDS:-0}" in
            0|1|2|3|4|5) ;;
            *) fail "内部安装锁测试等待时间必须是 0 到 5 秒。" 2 ;;
        esac
        ;;
    *) fail "NARC_INTERNAL_INSTALL_LOCK_TEST 只能是 0 或 1。" 2 ;;
esac

[ -z "${NARC_INTERNAL_INSTALL_FAILPOINT:-}" ] \
    || fail "内部安装故障注入不能用于普通安装入口。" 2

# This per-user lock is acquired before identity selection and before the
# shared build/NARC.app is touched. It remains held through replacement,
# cleanup, and the optional launch command.
acquire_install_lock

if [ "${NARC_INTERNAL_INSTALL_LOCK_TEST:-0}" = "1" ]; then
    printf 'LOCK_ACQUIRED pid=%s\n' "$$"
    /bin/sleep "${NARC_INTERNAL_INSTALL_LOCK_HOLD_SECONDS:-0}"
    exit 0
fi

# Never replace executable code while NARC is running. Skipping relaunch is
# not permission to overwrite a live process.
if pgrep -x NARC >/dev/null 2>&1; then
    fail "NARC 正在运行。请先在 NARC 菜单选择 Quit NARC，然后重新运行：bash scripts/install.sh" 3
fi

printf '🔐 正在检查当前用户的 NARC 本地签名身份…\n'
IDENTITY_ARGS=(--installed-app "$TARGET_APP")
if [ "$INSTALL_MODE" = "restore-legacy" ]; then
    IDENTITY_ARGS=(--restore-legacy-signer --installed-app "$TARGET_APP")
fi
if ! SIGN_IDENTITY="$(bash "${SCRIPT_DIR}/ensure-local-signing-identity.sh" "${IDENTITY_ARGS[@]}")"; then
    fail "本地签名身份不可用；为保护现有辅助功能授权，安装已停止且不会回退到 ad-hoc。" 4
fi

if ! [[ "$SIGN_IDENTITY" =~ ^[0-9A-F]{40}$ ]]; then
    fail "本地签名脚本返回了无效指纹；安装已停止。" 4
fi

read_marker_fingerprint() {
    local marker_line=""
    local extra_line=""

    [ ! -L "$MARKER_DIR" ] \
        || fail "NARC 应用数据目录不能是符号链接：$MARKER_DIR" 4
    [ ! -L "$MARKER_PATH" ] \
        || fail "签名身份指纹标记不能是符号链接：$MARKER_PATH" 4
    [ -f "$MARKER_PATH" ] \
        || fail "恢复旧签名前必须存在普通指纹标记文件。" 4

    exec 3<"$MARKER_PATH" || fail "无法读取当前签名身份指纹标记。" 4
    IFS= read -r marker_line <&3 \
        || { exec 3<&-; fail "当前签名身份指纹标记为空。" 4; }
    if IFS= read -r extra_line <&3 || [ -n "$extra_line" ]; then
        exec 3<&-
        fail "当前签名身份指纹标记必须且只能包含一行。" 4
    fi
    exec 3<&-
    [[ "$marker_line" =~ ^[0-9A-Fa-f]{40}$ ]] \
        || fail "当前签名身份指纹标记格式无效。" 4
    printf '%s' "$marker_line" | tr '[:lower:]' '[:upper:]'
    printf '\n'
}

verify_exact_designated_requirement() {
    local app_path="$1"
    local fingerprint="$2"
    local requirement_output=""
    local actual_requirement=""
    local actual_upper=""
    local expected_upper=""

    [ ! -L "$app_path" ] && [ -d "$app_path" ] \
        || return 1
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' \
        "$app_path/Contents/Info.plist" 2>/dev/null)" = "com.mickmi.narc" ] \
        || return 1
    codesign --verify --deep --strict "$app_path" || return 1
    codesign --verify --deep --strict \
        --test-requirement "=identifier \"com.mickmi.narc\" and certificate leaf = H\"${fingerprint}\"" \
        "$app_path" || return 1
    requirement_output="$(codesign -d -r- "$app_path" 2>&1)" || return 1
    actual_requirement="$(printf '%s\n' "$requirement_output" | awk '
        /^designated => / { count += 1; requirement = $0 }
        END { if (count == 1) print requirement; else exit 1 }
    ')" || return 1
    actual_upper="$(printf '%s' "$actual_requirement" | tr '[:lower:]' '[:upper:]')"
    expected_upper="$(printf '%s' \
        "designated => identifier \"com.mickmi.narc\" and certificate leaf = H\"${fingerprint}\"" \
        | tr '[:lower:]' '[:upper:]')"
    [ "$actual_upper" = "$expected_upper" ]
}

revalidate_normal_install_state() {
    local revalidated_identity=""
    local revalidated_marker=""

    if ! revalidated_identity="$(bash "${SCRIPT_DIR}/ensure-local-signing-identity.sh" \
        --installed-app "$TARGET_APP")"; then
        fail "构建期间本地签名状态发生变化；安装未切换。" 4
    fi
    [ "$revalidated_identity" = "$SIGN_IDENTITY" ] \
        || fail "构建前后选中的本地签名身份不一致；安装未切换。" 4
    revalidated_marker="$(read_marker_fingerprint)"
    [ "$revalidated_marker" = "$SIGN_IDENTITY" ] \
        || fail "构建期间指纹标记发生变化；安装未切换。" 4
}

if [ "$INSTALL_MODE" = "restore-legacy" ]; then
    CURRENT_SIGN_IDENTITY="$(read_marker_fingerprint)"
    [ "$CURRENT_SIGN_IDENTITY" != "$SIGN_IDENTITY" ] \
        || fail "当前已经使用所选旧签名，无需恢复。" 4
    verify_exact_designated_requirement "$TARGET_APP" "$CURRENT_SIGN_IDENTITY" \
        || fail "当前 App 与指纹标记在构建前已不一致；没有修改安装。" 4
fi

if [ -f "${HOME}/Library/Keychains/login.keychain-db" ]; then
    SIGN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
elif [ -f "${HOME}/Library/Keychains/login.keychain" ]; then
    SIGN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain"
else
    fail "无法定位当前用户的登录钥匙串；安装已停止。" 4
fi

printf '🔨 正在构建 NARC（%s）…\n' "$BUILD_CONFIG"
BUILD_LOG="$(mktemp "${TMPDIR:-/tmp}/narc-build.XXXXXX.log")"
if ! NARC_SIGNING_MODE=local \
    NARC_SIGN_IDENTITY="$SIGN_IDENTITY" \
    NARC_SIGN_KEYCHAIN="$SIGN_KEYCHAIN" \
    bash "${SCRIPT_DIR}/build-app.sh" "$BUILD_CONFIG" >"$BUILD_LOG" 2>&1; then
    printf '\n构建日志：\n' >&2
    cat "$BUILD_LOG" >&2
    rm -f "$BUILD_LOG"
    fail "构建或本地签名失败；请确认登录钥匙串已解锁，再重试或在 GitHub 提交 Issue。" 4
fi
rm -f "$BUILD_LOG"

if [ ! -d "$BUILT_APP" ]; then
    fail "构建未产生 build/NARC.app；请保留上方错误并在 GitHub 提交 Issue。" 4
fi

if [ -L "$INSTALL_ROOT" ]; then
    fail "安装目录不能是符号链接：$INSTALL_ROOT" 4
fi
mkdir -p "$INSTALL_ROOT"
[ -d "$INSTALL_ROOT" ] || fail "无法创建安装目录：$INSTALL_ROOT" 4

STAGING_APP="${INSTALL_ROOT}/.NARC.app.installing.$$"
BACKUP_APP="${INSTALL_ROOT}/.NARC.app.backup.$$"
FAILED_APP="${INSTALL_ROOT}/.NARC.app.failed.$$"
MARKER_STAGING="${MARKER_DIR}/.signing-identity.sha1.installing.$$"
MARKER_BACKUP="${MARKER_DIR}/.signing-identity.sha1.backup.$$"

if ! narc_install_assert_paths_absent \
    "$STAGING_APP" "$BACKUP_APP" "$FAILED_APP" \
    "$MARKER_STAGING" "$MARKER_BACKUP"; then
    fail "发现未清理的安装事务路径；没有覆盖任何现有文件。" 4
fi

trap narc_install_transaction_cleanup EXIT

/usr/bin/ditto "$BUILT_APP" "$STAGING_APP"
verify_exact_designated_requirement "$STAGING_APP" "$SIGN_IDENTITY" \
    || fail "暂存 App 未满足所选签名的精确 Designated Requirement；安装未切换。" 4

# The process may have been launched while the build was running. Recheck at
# the last safe point for every install mode, including NARC_SKIP_LAUNCH=1.
if pgrep -x NARC >/dev/null 2>&1; then
    fail "构建期间 NARC 被启动；为避免运行中覆盖，安装未切换。请退出后重试。" 3
fi

if [ -L "$TARGET_APP" ]; then
    fail "安装目标在构建期间变成了符号链接；安装未切换。" 3
fi

if [ "$INSTALL_MODE" = "normal" ]; then
    revalidate_normal_install_state
else
    [ "$(read_marker_fingerprint)" = "$CURRENT_SIGN_IDENTITY" ] \
        || fail "指纹标记在构建期间发生变化；恢复已停止。" 4
    verify_exact_designated_requirement "$TARGET_APP" "$CURRENT_SIGN_IDENTITY" \
        || fail "当前 App 在构建期间发生变化；恢复已停止。" 4

    [ ! -L "$MARKER_DIR" ] \
        || fail "NARC 应用数据目录不能是符号链接：$MARKER_DIR" 4
    [ -d "$MARKER_DIR" ] \
        || fail "NARC 应用数据目录不存在；恢复已停止。" 4
    [ ! -e "$MARKER_STAGING" ] && [ ! -L "$MARKER_STAGING" ] \
        || fail "指纹标记暂存路径已存在；恢复已停止。" 4
    if ! (set -o noclobber; printf '%s\n' "$SIGN_IDENTITY" >"$MARKER_STAGING"); then
        fail "无法安全创建旧签名指纹暂存文件；恢复已停止。" 4
    fi
    chmod 600 "$MARKER_STAGING"

    [ ! -e "$MARKER_BACKUP" ] && [ ! -L "$MARKER_BACKUP" ] \
        || fail "指纹标记备份路径已存在；恢复已停止。" 4
fi

narc_install_commit_switch

if [ "$INSTALL_MODE" = "restore-legacy" ]; then
    [ "$(read_marker_fingerprint)" = "$SIGN_IDENTITY" ] \
        || fail "旧签名指纹提交后校验失败；正在回滚 App 与指纹标记。" 4
fi

verify_exact_designated_requirement "$TARGET_APP" "$SIGN_IDENTITY" \
    || fail "已切换 App 的签名复核失败；正在回滚。" 4

TRANSACTION_COMMITTED=1

if [ -e "$BACKUP_APP" ]; then
    rm -rf -- "$BACKUP_APP"
fi
if [ -e "$MARKER_BACKUP" ]; then
    rm -f -- "$MARKER_BACKUP"
fi

if [ "$SKIP_LAUNCH" = "1" ]; then
    printf '\n✅ NARC 已安装到：%s\n' "$TARGET_APP"
    printf '   启动：open "%s"\n' "$TARGET_APP"
else
    open "$TARGET_APP"
    printf '\n✅ NARC 已安装并启动。\n'
fi

printf '\n只需记住：\n'
printf '  1. 默认 ⌃⌥N：把悬浮 N 召回鼠标所在屏幕（快捷键均可修改）\n'
printf '  2. 点击桌面悬浮 N：随手记录、查看未读和窗口\n'
printf '  3. 默认 ⌃⌥Q：先存入随手箱，再转 Todo 或 Note\n'
printf '  4. 默认 ⌃⌥⇧P：标记或取消当前窗口（可在偏好设置修改）\n'
printf '  5. 默认 ⌃⌥P：召回已标记窗口（已自定义时以设置显示为准）\n'
printf '  6. 首次使用窗口快捷键时，按引导开启辅助功能权限\n'
printf '  7. Windows 布局卡片可直接启停、改键；其他动作在偏好设置修改\n'
if [ "$INSTALL_MODE" = "restore-legacy" ]; then
    printf '\n已恢复旧 NARC Dev 签名并锁定其公开指纹；没有删除任何身份，也没有重置辅助功能权限。\n'
else
    printf '\n后续更新会复用当前 Mac、当前用户已锁定的本地签名身份。\n'
fi
