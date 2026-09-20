#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TRANSACTION_LIBRARY="${PROJECT_DIR}/scripts/lib/install-transaction.sh"

# shellcheck source=../lib/install-transaction.sh
source "$TRANSACTION_LIBRARY"

run_probe() {
    local fixture_root="$1"
    local requested_failure="$2"

    INSTALL_ROOT="${fixture_root}/Applications"
    TARGET_APP="${INSTALL_ROOT}/NARC.app"
    STAGING_APP="${INSTALL_ROOT}/.NARC.app.installing.probe"
    BACKUP_APP="${INSTALL_ROOT}/.NARC.app.backup.probe"
    FAILED_APP="${INSTALL_ROOT}/.NARC.app.failed.probe"
    MARKER_DIR="${fixture_root}/home/Library/Application Support/NARC"
    MARKER_PATH="${MARKER_DIR}/signing-identity.sha1"
    MARKER_STAGING="${MARKER_DIR}/.signing-identity.sha1.installing.probe"
    MARKER_BACKUP="${MARKER_DIR}/.signing-identity.sha1.backup.probe"
    INSTALL_MODE="restore-legacy"
    TRANSACTION_COMMITTED=0
    APP_SWITCHED=0
    INSTALL_LOCK_HELD=0

    exec 9>>"${MARKER_DIR}/install.lock"
    narc_install_lock_descriptor 9
    INSTALL_LOCK_HELD=1
    trap narc_install_early_cleanup EXIT
    narc_install_arm_signal_handlers
    trap narc_install_transaction_cleanup EXIT

    case "$requested_failure" in
        signal-after-app-move|hold-after-app-move|fail-after-marker-move)
            NARC_INTERNAL_INSTALL_FAILPOINT="$requested_failure"
            if [ "$requested_failure" = "hold-after-app-move" ]; then
                NARC_INTERNAL_INSTALL_HOLD_READY="${fixture_root}/hold.ready"
                NARC_INTERNAL_INSTALL_HOLD_RELEASE="${fixture_root}/hold.release"
            fi
            narc_install_commit_switch
            ;;
        fail-after-final-verification)
            NARC_INTERNAL_INSTALL_FAILPOINT=""
            narc_install_commit_switch
            # Models the real post-switch signature verification failing.
            exit 98
            ;;
        signal-after-commit)
            NARC_INTERNAL_INSTALL_FAILPOINT=""
            narc_install_commit_switch
            TRANSACTION_COMMITTED=1
            kill -TERM "$$"
            ;;
        *) exit 95 ;;
    esac

    exit 94
}

case "${1:-}" in
    --probe)
        [ "$#" -eq 3 ] || exit 95
        run_probe "$2" "$3"
        exit $?
        ;;
esac

PASS_COUNT=0
TEST_ROOT="$(mktemp -d /private/tmp/narc-install-transaction-tests.XXXXXX)"
HOLD_PROBE_PID=""

cleanup_tests() {
    if [ -n "$HOLD_PROBE_PID" ] && kill -0 "$HOLD_PROBE_PID" 2>/dev/null; then
        kill -TERM "$HOLD_PROBE_PID" 2>/dev/null || true
        wait "$HOLD_PROBE_PID" 2>/dev/null || true
    fi
    case "$TEST_ROOT" in
        /private/tmp/narc-install-transaction-tests.*) rm -rf -- "$TEST_ROOT" ;;
        *) printf '❌ Refusing to clean unexpected path: %s\n' "$TEST_ROOT" >&2 ;;
    esac
}

assert_committed_without_residue() {
    local fixture_root="$1"
    local install_root="${fixture_root}/Applications"
    local marker_root="${fixture_root}/home/Library/Application Support/NARC"

    [ "$(cat "${install_root}/NARC.app/.fingerprint")" = "NEW-APP" ] \
        || { printf '❌ Committed App was not preserved\n' >&2; exit 1; }
    [ "$(sed -n '1p' "${marker_root}/signing-identity.sha1")" = "NEW-MARKER" ] \
        || { printf '❌ Committed signer marker was not preserved\n' >&2; exit 1; }
    [ "$(stat -f '%Lp' "${marker_root}/signing-identity.sha1")" = "600" ] \
        || { printf '❌ Committed signer marker mode changed\n' >&2; exit 1; }

    for residue in \
        "${install_root}/.NARC.app.installing.probe" \
        "${install_root}/.NARC.app.backup.probe" \
        "${install_root}/.NARC.app.failed.probe" \
        "${marker_root}/.signing-identity.sha1.installing.probe" \
        "${marker_root}/.signing-identity.sha1.backup.probe"; do
        if [ -e "$residue" ] || [ -L "$residue" ]; then
            printf '❌ Committed transaction residue remained: %s\n' "$residue" >&2
            exit 1
        fi
    done
    assert_lock_released "${marker_root}/install.lock"
}
trap cleanup_tests EXIT

prepare_fixture() {
    local fixture_root="$1"
    local install_root="${fixture_root}/Applications"
    local marker_root="${fixture_root}/home/Library/Application Support/NARC"

    mkdir -p "${install_root}/NARC.app" "$marker_root"
    printf 'OLD-APP\n' >"${install_root}/NARC.app/.fingerprint"
    cp -R "${install_root}/NARC.app" "${fixture_root}/expected-old.app"
    mkdir -p "${install_root}/.NARC.app.installing.probe"
    printf 'NEW-APP\n' >"${install_root}/.NARC.app.installing.probe/.fingerprint"
    printf 'OLD-MARKER\n' >"${marker_root}/signing-identity.sha1"
    chmod 600 "${marker_root}/signing-identity.sha1"
    printf 'NEW-MARKER\n' >"${marker_root}/.signing-identity.sha1.installing.probe"
    chmod 600 "${marker_root}/.signing-identity.sha1.installing.probe"
}

assert_lock_released() {
    local lock_path="$1"
    (exec 9>>"$lock_path"; narc_install_lock_descriptor 9) \
        || { printf '❌ Transaction lock remained held: %s\n' "$lock_path" >&2; exit 1; }
}

assert_rolled_back() {
    local fixture_root="$1"
    local install_root="${fixture_root}/Applications"
    local marker_root="${fixture_root}/home/Library/Application Support/NARC"
    local marker_lines=""

    diff -qr "${fixture_root}/expected-old.app" "${install_root}/NARC.app" >/dev/null \
        || { printf '❌ Original App was not restored for %s\n' "$fixture_root" >&2; exit 1; }
    [ "$(sed -n '1p' "${marker_root}/signing-identity.sha1")" = "OLD-MARKER" ] \
        || { printf '❌ Original signer marker was not restored for %s\n' "$fixture_root" >&2; exit 1; }
    marker_lines="$(wc -l <"${marker_root}/signing-identity.sha1" | tr -d '[:space:]')"
    [ "$marker_lines" = "1" ] \
        || { printf '❌ Restored signer marker is not exactly one line\n' >&2; exit 1; }
    [ "$(stat -f '%Lp' "${marker_root}/signing-identity.sha1")" = "600" ] \
        || { printf '❌ Restored signer marker mode changed\n' >&2; exit 1; }

    for residue in \
        "${install_root}/.NARC.app.installing.probe" \
        "${install_root}/.NARC.app.backup.probe" \
        "${install_root}/.NARC.app.failed.probe" \
        "${marker_root}/.signing-identity.sha1.installing.probe" \
        "${marker_root}/.signing-identity.sha1.backup.probe"; do
        if [ -e "$residue" ] || [ -L "$residue" ]; then
            printf '❌ Transaction residue remained: %s\n' "$residue" >&2
            exit 1
        fi
    done
    assert_lock_released "${marker_root}/install.lock"
}

run_failure_case() {
    local case_name="$1"
    local requested_failure="$2"
    local expected_status="$3"
    local fixture_root="${TEST_ROOT}/${case_name}"
    local probe_status=0

    mkdir -p "$fixture_root"
    prepare_fixture "$fixture_root"
    set +e
    bash "$0" --probe "$fixture_root" "$requested_failure"
    probe_status=$?
    set -e
    [ "$probe_status" -eq "$expected_status" ] \
        || { printf '❌ %s exited %s, expected %s\n' \
            "$case_name" "$probe_status" "$expected_status" >&2; exit 1; }
    assert_rolled_back "$fixture_root"
    PASS_COUNT=$((PASS_COUNT + 1))
}

run_failure_case "signal-after-app-move" "signal-after-app-move" 143
run_failure_case "failure-after-marker-move" "fail-after-marker-move" 97
run_failure_case "failure-after-final-verification" "fail-after-final-verification" 98

# Hold a real kernel lock after the App move. A competing process must still
# be rejected until the same transaction reaches cleanup.
HOLD_ROOT="${TEST_ROOT}/lock-held-during-switch"
mkdir -p "$HOLD_ROOT"
prepare_fixture "$HOLD_ROOT"
bash "$0" --probe "$HOLD_ROOT" "hold-after-app-move" \
    >"${HOLD_ROOT}/probe.out" 2>"${HOLD_ROOT}/probe.err" &
HOLD_PROBE_PID=$!
hold_wait_attempt=0
while [ ! -e "${HOLD_ROOT}/hold.ready" ] && [ "$hold_wait_attempt" -lt 3000 ]; do
    /bin/sleep 0.01
    hold_wait_attempt=$((hold_wait_attempt + 1))
done
[ -e "${HOLD_ROOT}/hold.ready" ] \
    || { printf '❌ Transaction did not reach the post-move lock probe\n' >&2; exit 1; }
if (exec 9>>"${HOLD_ROOT}/home/Library/Application Support/NARC/install.lock"; narc_install_lock_descriptor 9); then
    printf '❌ Install lock was released while the App switch was in progress\n' >&2
    exit 1
fi
: >"${HOLD_ROOT}/hold.release"
set +e
wait "$HOLD_PROBE_PID"
hold_probe_status=$?
set -e
HOLD_PROBE_PID=""
[ "$hold_probe_status" -eq 94 ] \
    || { printf '❌ Held transaction exited %s, expected 94\n' \
        "$hold_probe_status" >&2; exit 1; }
assert_rolled_back "$HOLD_ROOT"
PASS_COUNT=$((PASS_COUNT + 1))

# Once final verification has committed the pair, a signal preserves the new
# App + marker and removes both backups instead of attempting a rollback.
COMMITTED_ROOT="${TEST_ROOT}/signal-after-commit"
mkdir -p "$COMMITTED_ROOT"
prepare_fixture "$COMMITTED_ROOT"
set +e
bash "$0" --probe "$COMMITTED_ROOT" "signal-after-commit"
committed_status=$?
set -e
[ "$committed_status" -eq 143 ] \
    || { printf '❌ Committed signal probe exited %s, expected 143\n' \
        "$committed_status" >&2; exit 1; }
assert_committed_without_residue "$COMMITTED_ROOT"
PASS_COUNT=$((PASS_COUNT + 1))

# Collision checks must fail closed and preserve the pre-existing path.
COLLISION_ROOT="${TEST_ROOT}/collision"
mkdir -p "$COLLISION_ROOT"
printf 'KEEP\n' >"${COLLISION_ROOT}/existing"
if narc_install_assert_paths_absent \
    "${COLLISION_ROOT}/missing" "${COLLISION_ROOT}/existing" \
    2>"${COLLISION_ROOT}/collision.err"; then
    printf '❌ Transaction collision was unexpectedly accepted\n' >&2
    exit 1
fi
grep -Fq '安装事务路径已存在' "${COLLISION_ROOT}/collision.err" \
    || { printf '❌ Collision check did not explain the refusal\n' >&2; exit 1; }
[ "$(cat "${COLLISION_ROOT}/existing")" = "KEEP" ] \
    || { printf '❌ Collision check modified the existing path\n' >&2; exit 1; }
PASS_COUNT=$((PASS_COUNT + 1))

printf '✅ Install transaction tests passed: %d\n' "$PASS_COUNT"
