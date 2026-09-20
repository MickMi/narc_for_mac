#!/bin/bash

# Shared install transaction primitives. This file is sourced by install.sh
# and by the isolated transaction tests; it must not be executed directly.

narc_install_arm_signal_handlers() {
    # Bash does not run an EXIT trap for an unhandled terminating signal.
    # Convert the signal into an explicit exit so the currently installed App
    # and signer marker are restored before preserving the conventional code.
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

narc_install_release_lock() {
    [ "${INSTALL_LOCK_HELD:-0}" -eq 1 ] || return 0
    exec 9>&-
    INSTALL_LOCK_HELD=0
}

narc_install_early_cleanup() {
    local exit_code=$?
    trap - EXIT
    trap '' HUP INT TERM
    narc_install_release_lock
    exit "$exit_code"
}

narc_install_assert_paths_absent() {
    local transaction_path

    for transaction_path in "$@"; do
        if [ -e "$transaction_path" ] || [ -L "$transaction_path" ]; then
            printf '❌ 安装事务路径已存在，拒绝覆盖：%s\n' "$transaction_path" >&2
            return 1
        fi
    done
}

narc_install_remove_transaction_path() {
    local transaction_path="$1"

    if [ -L "$transaction_path" ] || [ -f "$transaction_path" ]; then
        rm -f -- "$transaction_path"
    elif [ -d "$transaction_path" ]; then
        rm -rf -- "$transaction_path"
    elif [ -e "$transaction_path" ]; then
        rm -f -- "$transaction_path"
    fi
}

narc_install_transaction_cleanup() {
    local exit_code=$?

    trap - EXIT
    # Do not allow a second signal to interrupt restoration halfway through.
    trap '' HUP INT TERM

    if [ "${TRANSACTION_COMMITTED:-0}" -ne 1 ]; then
        if [ "${APP_SWITCHED:-0}" -eq 1 ]; then
            if [ -e "$TARGET_APP" ] && [ ! -L "$TARGET_APP" ]; then
                if [ -e "$FAILED_APP" ] || [ -L "$FAILED_APP" ]; then
                    printf '⚠️ 无法隔离未完成安装的 App；故障路径已存在：%s\n' \
                        "$FAILED_APP" >&2
                    exit_code=1
                else
                    mv "$TARGET_APP" "$FAILED_APP" \
                        || { printf '⚠️ 无法隔离未完成安装的 App：%s\n' \
                            "$TARGET_APP" >&2; exit_code=1; }
                fi
            fi
        fi
        if [ -e "$BACKUP_APP" ] && [ ! -L "$BACKUP_APP" ]; then
            if [ ! -e "$TARGET_APP" ] && [ ! -L "$TARGET_APP" ]; then
                mv "$BACKUP_APP" "$TARGET_APP" \
                    || { printf '⚠️ 无法自动恢复原 NARC.app；备份仍位于：%s\n' \
                        "$BACKUP_APP" >&2; exit_code=1; }
            fi
        fi

        if [ -e "$MARKER_BACKUP" ] && [ ! -L "$MARKER_BACKUP" ]; then
            if [ -e "$MARKER_PATH" ] && [ ! -L "$MARKER_PATH" ]; then
                rm -f -- "$MARKER_PATH" \
                    || { printf '⚠️ 无法移除未提交的指纹标记：%s\n' \
                        "$MARKER_PATH" >&2; exit_code=1; }
            fi
            if [ ! -e "$MARKER_PATH" ] && [ ! -L "$MARKER_PATH" ]; then
                mv "$MARKER_BACKUP" "$MARKER_PATH" \
                    || { printf '⚠️ 无法自动恢复原指纹标记；备份仍位于：%s\n' \
                        "$MARKER_BACKUP" >&2; exit_code=1; }
            fi
        fi
    else
        # Once both the App and marker have passed final verification, a
        # signal must keep the new consistent pair and only remove backups.
        narc_install_remove_transaction_path "$BACKUP_APP" \
            || { printf '⚠️ 无法清理已提交的 App 备份：%s\n' "$BACKUP_APP" >&2; exit_code=1; }
        narc_install_remove_transaction_path "$MARKER_BACKUP" \
            || { printf '⚠️ 无法清理已提交的指纹标记备份：%s\n' \
                "$MARKER_BACKUP" >&2; exit_code=1; }
    fi

    narc_install_remove_transaction_path "$STAGING_APP" \
        || { printf '⚠️ 无法清理 App 暂存路径：%s\n' "$STAGING_APP" >&2; exit_code=1; }
    narc_install_remove_transaction_path "$FAILED_APP" \
        || { printf '⚠️ 无法清理 App 故障路径：%s\n' "$FAILED_APP" >&2; exit_code=1; }
    narc_install_remove_transaction_path "$MARKER_STAGING" \
        || { printf '⚠️ 无法清理指纹标记暂存路径：%s\n' "$MARKER_STAGING" >&2; exit_code=1; }
    narc_install_release_lock
    exit "$exit_code"
}

narc_install_commit_switch() {
    if [ -e "$BACKUP_APP" ] || [ -L "$BACKUP_APP" ] \
        || [ -e "$FAILED_APP" ] || [ -L "$FAILED_APP" ]; then
        printf '❌ App 事务备份路径在切换前被占用；安装已停止。\n' >&2
        return 96
    fi
    if [ "$INSTALL_MODE" = "restore-legacy" ] \
        && { [ -e "$MARKER_BACKUP" ] || [ -L "$MARKER_BACKUP" ]; }; then
        printf '❌ 指纹标记备份路径在切换前被占用；恢复已停止。\n' >&2
        return 96
    fi

    if [ -e "$TARGET_APP" ]; then
        mv "$TARGET_APP" "$BACKUP_APP"
    fi

    if [ "$INSTALL_MODE" = "restore-legacy" ]; then
        mv "$MARKER_PATH" "$MARKER_BACKUP"
    fi

    # Record rollback intent before the interruptible move. Together with the
    # explicit signal handlers, every HUP/INT/TERM boundary restores the old
    # App and signer marker.
    APP_SWITCHED=1
    mv "$STAGING_APP" "$TARGET_APP"

    case "${NARC_INTERNAL_INSTALL_FAILPOINT:-}" in
        "") ;;
        signal-after-app-move) kill -TERM "$$" ;;
        hold-after-app-move)
            case "${NARC_INTERNAL_INSTALL_HOLD_READY:-}" in
                /private/tmp/narc-install-transaction-tests.*) ;;
                *) return 96 ;;
            esac
            case "${NARC_INTERNAL_INSTALL_HOLD_RELEASE:-}" in
                /private/tmp/narc-install-transaction-tests.*) ;;
                *) return 96 ;;
            esac
            : >"$NARC_INTERNAL_INSTALL_HOLD_READY"
            hold_attempt=0
            while [ ! -e "$NARC_INTERNAL_INSTALL_HOLD_RELEASE" ] \
                && [ "$hold_attempt" -lt 500 ]; do
                /bin/sleep 0.01
                hold_attempt=$((hold_attempt + 1))
            done
            [ -e "$NARC_INTERNAL_INSTALL_HOLD_RELEASE" ] || return 93
            ;;
        fail-after-marker-move) ;;
        *)
            printf '❌ 未知的内部安装故障注入点。\n' >&2
            return 96
            ;;
    esac

    if [ "$INSTALL_MODE" = "restore-legacy" ]; then
        mv "$MARKER_STAGING" "$MARKER_PATH"
        if [ "${NARC_INTERNAL_INSTALL_FAILPOINT:-}" = "fail-after-marker-move" ]; then
            return 97
        fi
    fi
}
