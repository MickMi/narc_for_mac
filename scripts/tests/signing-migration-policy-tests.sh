#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# shellcheck source=../ensure-local-signing-identity.sh
source "${PROJECT_DIR}/scripts/ensure-local-signing-identity.sh"

PASS_COUNT=0

fail_test() {
    printf '❌ %s\n' "$1" >&2
    exit 1
}

set_identities() {
    VALID_IDENTITY_FINGERPRINTS=()
    VALID_IDENTITY_NAMES=()
    while [ "$#" -gt 0 ]; do
        VALID_IDENTITY_FINGERPRINTS+=("${1%%|*}")
        VALID_IDENTITY_NAMES+=("${1#*|}")
        shift
    done
}

expect_normal_success() {
    local expected_action="$1"
    local expected_fingerprint="$2"
    shift 2

    determine_normal_signing_policy "$@" \
        || fail_test "normal policy unexpectedly failed: ${POLICY_ERROR}"
    [ "$POLICY_ACTION" = "$expected_action" ] \
        || fail_test "expected action ${expected_action}, got ${POLICY_ACTION}"
    [ "$POLICY_FINGERPRINT" = "$expected_fingerprint" ] \
        || fail_test "expected fingerprint ${expected_fingerprint}, got ${POLICY_FINGERPRINT}"
    PASS_COUNT=$((PASS_COUNT + 1))
}

expect_normal_failure() {
    if determine_normal_signing_policy "$@"; then
        fail_test "normal policy unexpectedly succeeded with ${POLICY_ACTION}"
    fi
    [ -n "$POLICY_ERROR" ] || fail_test "normal policy failure lacked an error"
    PASS_COUNT=$((PASS_COUNT + 1))
}

expect_restore_success() {
    local expected_fingerprint="$1"
    shift

    determine_legacy_restore_policy "$@" \
        || fail_test "restore policy unexpectedly failed: ${POLICY_ERROR}"
    [ "$POLICY_ACTION" = "restore-legacy" ] \
        || fail_test "expected restore-legacy, got ${POLICY_ACTION}"
    [ "$POLICY_FINGERPRINT" = "$expected_fingerprint" ] \
        || fail_test "expected legacy fingerprint ${expected_fingerprint}, got ${POLICY_FINGERPRINT}"
    PASS_COUNT=$((PASS_COUNT + 1))
}

expect_restore_failure() {
    if determine_legacy_restore_policy "$@"; then
        fail_test "restore policy unexpectedly succeeded with ${POLICY_FINGERPRINT}"
    fi
    [ -n "$POLICY_ERROR" ] || fail_test "restore policy failure lacked an error"
    PASS_COUNT=$((PASS_COUNT + 1))
}

LOCAL_FP="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
LEGACY_FP="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
OTHER_LOCAL_FP="CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"

# Marker continuity outranks other available identities when no stable App
# contradicts it. It may never silently rotate.
set_identities \
    "${LOCAL_FP}|${LOCAL_IDENTITY_CN}" \
    "${LEGACY_FP}|${LEGACY_IDENTITY_CN}"
expect_normal_success "reuse-marker" "$LOCAL_FP" \
    1 "$LOCAL_FP" absent "" 1

expect_normal_success "reuse-marker" "$LOCAL_FP" \
    1 "$LOCAL_FP" stable "$LOCAL_FP" 1

# A marker must not silently overwrite an installed App that still has a
# different, strictly valid stable signer. This is the original TCC-breaking
# migration shape and must stop for explicit recovery.
expect_normal_failure 1 "$LOCAL_FP" stable "$LEGACY_FP" 1

# Repairing an ad-hoc App with the locked marker is safe: ad-hoc has no leaf
# identity that could be inherited or preserved.
expect_normal_success "reuse-marker" "$LOCAL_FP" \
    1 "$LOCAL_FP" adhoc "" 1

# A stale marker must fail closed instead of falling through to another valid
# signer or creating a replacement.
set_identities "${LEGACY_FP}|${LEGACY_IDENTITY_CN}"
expect_normal_failure 1 "$LOCAL_FP" stable "$LEGACY_FP" 0

# With no marker, a strictly inspected installed App is sufficient evidence to
# adopt its unique eligible Local v1 or NARC Dev leaf without another prompt.
set_identities "${LEGACY_FP}|${LEGACY_IDENTITY_CN}"
expect_normal_success "adopt-installed" "$LEGACY_FP" \
    0 "" stable "$LEGACY_FP" 0

set_identities "${LOCAL_FP}|${LOCAL_IDENTITY_CN}"
expect_normal_success "adopt-installed" "$LOCAL_FP" \
    0 "" stable "$LOCAL_FP" 1

# Duplicate matches are ambiguous even when their fingerprints happen to be
# equal; migration must stop.
set_identities \
    "${LEGACY_FP}|${LEGACY_IDENTITY_CN}" \
    "${LEGACY_FP}|${LEGACY_IDENTITY_CN}"
expect_normal_failure 0 "" stable "$LEGACY_FP" 0

# Ad-hoc code has no certificate continuity to inherit. It follows the same
# fresh Local v1 path as a machine with no installed App.
set_identities "${LEGACY_FP}|${LEGACY_IDENTITY_CN}"
expect_normal_success "create-local-v1" "" 0 "" adhoc "" 0

set_identities
expect_normal_success "create-local-v1" "" 0 "" absent "" 0

# An unmarked Local v1 private key is never silently adopted without App
# evidence; it remains an explicit fingerprint-confirmation path.
set_identities "${LOCAL_FP}|${LOCAL_IDENTITY_CN}"
expect_normal_success "confirm-existing-local" "$LOCAL_FP" \
    0 "" absent "" 1

# A certificate without a unique valid private-key identity blocks rotation.
set_identities
expect_normal_failure 0 "" absent "" 1

# Explicit restore requires current marker/App consistency plus exactly one
# distinct, valid NARC Dev candidate.
set_identities \
    "${LOCAL_FP}|${LOCAL_IDENTITY_CN}" \
    "${LEGACY_FP}|${LEGACY_IDENTITY_CN}"
expect_restore_success "$LEGACY_FP" "$LOCAL_FP" "$LOCAL_FP"
expect_restore_failure "$LOCAL_FP" "$LEGACY_FP"

set_identities \
    "${LOCAL_FP}|${LOCAL_IDENTITY_CN}" \
    "${LEGACY_FP}|${LEGACY_IDENTITY_CN}" \
    "${OTHER_LOCAL_FP}|${LEGACY_IDENTITY_CN}"
expect_restore_failure "$LOCAL_FP" "$LOCAL_FP"

INSTALL_SCRIPT="${PROJECT_DIR}/scripts/install.sh"
TRANSACTION_LIBRARY="${PROJECT_DIR}/scripts/lib/install-transaction.sh"
LOCK_TEST_ROOT="$(mktemp -d /private/tmp/narc-install-lock-tests.XXXXXX)"
LOCK_TEST_HOME="${LOCK_TEST_ROOT}/home"
LOCK_TEST_PATH="${LOCK_TEST_HOME}/Library/Application Support/NARC/install.lock"
FIRST_LOCK_PID=""

cleanup_lock_tests() {
    if [ -n "$FIRST_LOCK_PID" ] && kill -0 "$FIRST_LOCK_PID" 2>/dev/null; then
        kill "$FIRST_LOCK_PID" 2>/dev/null || true
        wait "$FIRST_LOCK_PID" 2>/dev/null || true
    fi
    case "$LOCK_TEST_ROOT" in
        /private/tmp/narc-install-lock-tests.*) rm -rf -- "$LOCK_TEST_ROOT" ;;
        *) fail_test "refusing to clean unexpected lock test path: ${LOCK_TEST_ROOT}" ;;
    esac
}
trap cleanup_lock_tests EXIT
mkdir -p "$LOCK_TEST_HOME"

# One per-user lock serializes the complete critical section. The second
# process must stop before identity selection or shared build output is used.
HOME="$LOCK_TEST_HOME" \
NARC_INTERNAL_INSTALL_LOCK_TEST=1 \
NARC_INTERNAL_INSTALL_LOCK_HOLD_SECONDS=2 \
    bash "$INSTALL_SCRIPT" >"${LOCK_TEST_ROOT}/first.out" 2>"${LOCK_TEST_ROOT}/first.err" &
FIRST_LOCK_PID=$!

lock_wait_attempt=0
while ! grep -Fq 'LOCK_ACQUIRED' "${LOCK_TEST_ROOT}/first.out" 2>/dev/null \
    && [ "$lock_wait_attempt" -lt 50 ]; do
    /bin/sleep 0.05
    lock_wait_attempt=$((lock_wait_attempt + 1))
done
if ! grep -Fq 'LOCK_ACQUIRED' "${LOCK_TEST_ROOT}/first.out"; then
    cat "${LOCK_TEST_ROOT}/first.out" "${LOCK_TEST_ROOT}/first.err" >&2
    fail_test "first install probe did not acquire its lock"
fi

set +e
SECOND_LOCK_OUTPUT="$(HOME="$LOCK_TEST_HOME" \
    NARC_INTERNAL_INSTALL_LOCK_TEST=1 \
    NARC_INTERNAL_INSTALL_LOCK_HOLD_SECONDS=0 \
    bash "$INSTALL_SCRIPT" 2>&1)"
SECOND_LOCK_STATUS=$?
set -e
[ "$SECOND_LOCK_STATUS" -eq 5 ] \
    || fail_test "concurrent install probe exited ${SECOND_LOCK_STATUS}, expected 5"
case "$SECOND_LOCK_OUTPUT" in
    *"另一个 NARC 安装正在进行"*) ;;
    *) fail_test "concurrent install probe lacked the lock-holder error" ;;
esac
wait "$FIRST_LOCK_PID" || fail_test "first install lock probe failed"
FIRST_LOCK_PID=""
[ -f "$LOCK_TEST_PATH" ] || fail_test "lockf coordination file unexpectedly disappeared"
PASS_COUNT=$((PASS_COUNT + 1))

# A leftover coordination file carries no stale ownership: lockf uses the
# kernel lock on its inode, so the next process can acquire it immediately.
mkdir -p "$(dirname "$LOCK_TEST_PATH")"
printf '999999\n' >"$LOCK_TEST_PATH"
HOME="$LOCK_TEST_HOME" \
NARC_INTERNAL_INSTALL_LOCK_TEST=1 \
NARC_INTERNAL_INSTALL_LOCK_HOLD_SECONDS=0 \
    bash "$INSTALL_SCRIPT" >"${LOCK_TEST_ROOT}/stale.out" 2>"${LOCK_TEST_ROOT}/stale.err" \
    || fail_test "stale install lock was not recovered"
grep -Fq 'LOCK_ACQUIRED' "${LOCK_TEST_ROOT}/stale.out" \
    || fail_test "stale lock probe did not enter the critical section"
[ -f "$LOCK_TEST_PATH" ] || fail_test "lockf coordination file unexpectedly disappeared"
PASS_COUNT=$((PASS_COUNT + 1))

# A symlink is not treated as a stale lock candidate and must be preserved.
rm -f -- "$LOCK_TEST_PATH"
ln -s "${LOCK_TEST_ROOT}/not-a-lock" "$LOCK_TEST_PATH"
set +e
HOME="$LOCK_TEST_HOME" \
NARC_INTERNAL_INSTALL_LOCK_TEST=1 \
NARC_INTERNAL_INSTALL_LOCK_HOLD_SECONDS=0 \
    bash "$INSTALL_SCRIPT" >"${LOCK_TEST_ROOT}/symlink.out" 2>"${LOCK_TEST_ROOT}/symlink.err"
SYMLINK_LOCK_STATUS=$?
set -e
[ "$SYMLINK_LOCK_STATUS" -eq 4 ] \
    || fail_test "symlink lock probe exited ${SYMLINK_LOCK_STATUS}, expected 4"
[ -L "$LOCK_TEST_PATH" ] || fail_test "symlink lock was unexpectedly removed"
rm -f -- "$LOCK_TEST_PATH"
PASS_COUNT=$((PASS_COUNT + 1))

# Source ordering is part of the policy: acquire before shared build output,
# revalidate normal state before replacement, and mark rollback intent before
# the move that can be interrupted.
LOCK_LINE="$(grep -n '^acquire_install_lock$' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
BUILD_LINE="$(grep -n 'bash "${SCRIPT_DIR}/build-app.sh"' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
REVALIDATE_LINE="$(grep -n '^    revalidate_normal_install_state$' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
COMMIT_LINE="$(grep -n '^narc_install_commit_switch$' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
SWITCH_MARK_LINE="$(grep -n '^    APP_SWITCHED=1$' "$TRANSACTION_LIBRARY" | tail -1 | cut -d: -f1)"
SWITCH_MOVE_LINE="$(grep -n '^    mv "$STAGING_APP" "$TARGET_APP"$' "$TRANSACTION_LIBRARY" | tail -1 | cut -d: -f1)"
[ "$LOCK_LINE" -lt "$BUILD_LINE" ] \
    || fail_test "install lock is not acquired before the shared build"
[ "$REVALIDATE_LINE" -lt "$COMMIT_LINE" ] \
    || fail_test "normal state is not revalidated before replacement"
[ "$SWITCH_MARK_LINE" -lt "$SWITCH_MOVE_LINE" ] \
    || fail_test "rollback intent is not marked before the interruptible move"
if grep -Eq '^trap - EXIT$' "$INSTALL_SCRIPT" "$TRANSACTION_LIBRARY"; then
    fail_test "install script can disable lock cleanup before launch completes"
fi
[ "$(grep -Ec 'exec 9>&-' "$INSTALL_SCRIPT")" -eq 2 ] \
    || fail_test "install script can close the held lock outside cleanup"
[ "$(grep -Ec 'exec 9>&-' "$TRANSACTION_LIBRARY")" -eq 1 ] \
    || fail_test "transaction library has more than one lock-release path"
PASS_COUNT=$((PASS_COUNT + 1))

printf '✅ Signing migration policy tests passed: %d\n' "$PASS_COUNT"
