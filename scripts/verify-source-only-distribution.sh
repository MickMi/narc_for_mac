#!/bin/bash
# Guard the product boundary: NARC is obtained as source and prepared locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

fail() {
    echo "❌ $1" >&2
    exit 1
}

active_delivery_files() {
    local candidate
    local tracked_record
    local tracked_mode
    local tracked_path

    find "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/.github" \
        -type f ! -path "${PROJECT_DIR}/scripts/verify-source-only-distribution.sh" \
        -print0 2>/dev/null

    for candidate in \
        "${PROJECT_DIR}/Makefile" \
        "${PROJECT_DIR}/GNUmakefile" \
        "${PROJECT_DIR}/Justfile" \
        "${PROJECT_DIR}/Taskfile.yml" \
        "${PROJECT_DIR}/Taskfile.yaml" \
        "${PROJECT_DIR}/Package.swift" \
        "${PROJECT_DIR}/Package.resolved" \
        "${PROJECT_DIR}/.gitlab-ci.yml" \
        "${PROJECT_DIR}/.circleci/config.yml"; do
        [ ! -f "$candidate" ] || printf '%s\0' "$candidate"
    done

    find "$PROJECT_DIR" -type f \
        \( -path '*/Plugins/*' \
        -o -path '*/fastlane/*' \
        -o -name '*.xcconfig' \
        -o -name '*.entitlements' \
        -o -name 'project.pbxproj' \
        -o -name 'ExportOptions*.plist' \) \
        ! -path '*/.git/*' ! -path '*/.build/*' ! -path '*/build/*' \
        -print0 2>/dev/null

    # A tracked executable outside the conventional locations is still part
    # of the delivery surface and must not become a hidden release path.
    while IFS= read -r -d '' tracked_record; do
        tracked_mode="${tracked_record%% *}"
        tracked_path="${tracked_record#*$'\t'}"
        [ "$tracked_mode" = "100755" ] || continue
        [ "$tracked_path" != "scripts/verify-source-only-distribution.sh" ] || continue
        printf '%s\0' "${PROJECT_DIR}/${tracked_path}"
    done < <(git -C "$PROJECT_DIR" ls-files -s -z)
}

[ ! -e "${PROJECT_DIR}/.github/workflows/release.yml" ] \
    || fail "prebuilt-app release workflow must not exist"
[ ! -e "${PROJECT_DIR}/scripts/update-restart.sh" ] \
    || fail "certificate-based update script must not exist"

if active_delivery_files \
    | xargs -0 grep -Ein \
        'hdiutil|create-dmg|pkgbuild|productbuild|productsign|action-gh-release|ncipollo/release-action|softprops/action-gh-release|release-action|gh[[:space:]]+release|gh[[:space:]]+api.*releases|contents:[[:space:]]+write|NARC\.app\.zip|ditto.*--keepParent|actions/upload-artifact|upload-artifact|notarytool|stapler|sparkle|Developer ID (Application|Installer)|Apple Distribution|Mac App Distribution|3rd Party Mac Developer|CODE_SIGN_IDENTITY.*Developer ID|APPLE_ID|AC_PASSWORD|ASC_PROVIDER|spctl.*--master-disable|xattr.*com\.apple\.quarantine|tccutil.*reset' \
        >/dev/null 2>&1; then
    fail "an executable packaging, release, Gatekeeper-bypass, TCC-reset, notarization, or updater path was found"
fi

if active_delivery_files \
    | xargs -0 grep -En \
        'security[[:space:]]+import.*[[:space:]]-A([[:space:]]|$)|(^|[[:space:]])-A([[:space:]\\]|$)|add-trusted-cert.*[[:space:]]-d([[:space:]]|$)' \
        >/dev/null 2>&1; then
    fail "local signing must not grant all-app private-key access or administrator-domain trust"
fi

while IFS= read -r tracked_file; do
    case "$tracked_file" in
        *.dmg|*.pkg|*.mpkg|*.zip|*.app/*|build/*)
            fail "tracked prebuilt or packaged artifact is forbidden: ${tracked_file}"
            ;;
        *.p12|*.pfx|*.pem|*.key|*.cer|*.crt|*.der|*.keychain|*.keychain-db)
            fail "tracked signing material is forbidden: ${tracked_file}"
            ;;
    esac
done < <(git -C "$PROJECT_DIR" ls-files)

if git -C "$PROJECT_DIR" grep -I -E \
    'BEGIN (RSA |EC |ENCRYPTED )?PRIVATE KEY' -- . >/dev/null 2>&1; then
    fail "tracked private-key material is forbidden"
fi

BUILD_SCRIPT="${PROJECT_DIR}/scripts/build-app.sh"
grep -Fq 'SIGNING_MODE="${NARC_SIGNING_MODE:-}"' "$BUILD_SCRIPT" \
    || fail "build-app.sh must require an explicit signing mode"
grep -Eq -- '--sign[[:space:]]+-' "$BUILD_SCRIPT" \
    || fail "build-app.sh must retain an explicit ad-hoc development/CI path"
grep -Fq 'certificate leaf = H' "$BUILD_SCRIPT" \
    || fail "local signing must bind the designated requirement to the exact certificate"
grep -Fq 'codesign --verify --deep --strict' "$BUILD_SCRIPT" \
    || fail "build-app.sh must strictly verify the completed bundle"

INSTALL_SCRIPT="${PROJECT_DIR}/scripts/install.sh"
TRANSACTION_LIBRARY="${PROJECT_DIR}/scripts/lib/install-transaction.sh"
grep -Fq 'INSTALL_ROOT="${NARC_INSTALL_DIR:-${HOME}/Applications}"' "$INSTALL_SCRIPT" \
    || fail "install.sh must keep the default app under the user Applications directory"
grep -Fq 'ensure-local-signing-identity.sh' "$INSTALL_SCRIPT" \
    || fail "normal installation must provision or reuse the per-user local identity"
grep -Fq 'NARC_SIGNING_MODE=local' "$INSTALL_SCRIPT" \
    || fail "normal installation must force stable local signing"
grep -Fq 'LOCKF_BIN="/usr/bin/lockf"' "$INSTALL_SCRIPT" \
    || fail "normal installation must use the system kernel-backed lock helper"
grep -Fq '"$LOCKF_BIN" -s -t 0 9' "$INSTALL_SCRIPT" \
    || fail "normal installation must acquire its per-user lock without waiting or stale PID ownership"
[ "$(grep -Ec 'exec 9>&-' "$INSTALL_SCRIPT")" -eq 2 ] \
    || fail "install.sh may close fd 9 only on the two pre-acquisition error paths"
[ "$(grep -Ec 'exec 9>&-' "$TRANSACTION_LIBRARY")" -eq 1 ] \
    || fail "the held install lock may be released only by transaction cleanup"
grep -Fq 'revalidate_normal_install_state' "$INSTALL_SCRIPT" \
    || fail "normal installation must revalidate marker, App, and signer state after building"
grep -Fq 'source "${SCRIPT_DIR}/lib/install-transaction.sh"' "$INSTALL_SCRIPT" \
    || fail "install.sh must use the transaction implementation exercised by tests"
[ -f "$TRANSACTION_LIBRARY" ] \
    || fail "the shared install transaction library is missing"
grep -Fq "trap 'exit 129' HUP" "$TRANSACTION_LIBRARY" \
    || fail "install transactions must turn HUP into a cleanup-preserving exit"
grep -Fq "trap 'exit 130' INT" "$TRANSACTION_LIBRARY" \
    || fail "install transactions must turn INT into a cleanup-preserving exit"
grep -Fq "trap 'exit 143' TERM" "$TRANSACTION_LIBRARY" \
    || fail "install transactions must turn TERM into a cleanup-preserving exit"
grep -Fq 'if pgrep -x NARC' "$INSTALL_SCRIPT" \
    || fail "install.sh must block replacement while NARC is running"
if grep -Eq 'SKIP_LAUNCH.*pgrep|pgrep.*SKIP_LAUNCH' "$INSTALL_SCRIPT"; then
    fail "NARC_SKIP_LAUNCH must not bypass the running-process replacement guard"
fi
grep -Fq -- '--restore-legacy-signer' "$INSTALL_SCRIPT" \
    || fail "install.sh must expose the explicit legacy signer recovery path"
grep -Fq 'verify_exact_designated_requirement "$STAGING_APP" "$SIGN_IDENTITY"' "$INSTALL_SCRIPT" \
    || fail "every staging App must satisfy the selected exact designated requirement"
grep -Fq 'MARKER_STAGING=' "$INSTALL_SCRIPT" \
    || fail "legacy signer recovery must stage the replacement marker"
grep -Fq 'MARKER_BACKUP=' "$INSTALL_SCRIPT" \
    || fail "legacy signer recovery must retain a rollback marker"
if grep -Eq '^trap - EXIT$' "$INSTALL_SCRIPT" "$TRANSACTION_LIBRARY"; then
    fail "install.sh must not disable lock cleanup before its launch step completes"
fi

lock_line="$(grep -n '^acquire_install_lock$' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
identity_line="$(grep -n 'ensure-local-signing-identity.sh" "${IDENTITY_ARGS\[@\]}' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
build_line="$(grep -n 'bash "${SCRIPT_DIR}/build-app.sh"' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
revalidate_line="$(grep -n '^    revalidate_normal_install_state$' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
commit_line="$(grep -n '^narc_install_commit_switch$' "$INSTALL_SCRIPT" | head -1 | cut -d: -f1)"
switch_mark_line="$(grep -n '^    APP_SWITCHED=1$' "$TRANSACTION_LIBRARY" | tail -1 | cut -d: -f1)"
switch_move_line="$(grep -n '^    mv "$STAGING_APP" "$TARGET_APP"$' "$TRANSACTION_LIBRARY" | tail -1 | cut -d: -f1)"
[ -n "$lock_line" ] && [ -n "$identity_line" ] && [ -n "$build_line" ] \
    && [ "$lock_line" -lt "$identity_line" ] && [ "$lock_line" -lt "$build_line" ] \
    || fail "the per-user install lock must cover identity selection and shared build/NARC.app"
[ -n "$revalidate_line" ] && [ -n "$commit_line" ] \
    && [ "$revalidate_line" -lt "$commit_line" ] \
    || fail "normal signer state must be revalidated immediately before replacement"
[ -n "$switch_mark_line" ] && [ "$switch_mark_line" -lt "$switch_move_line" ] \
    || fail "rollback intent must be marked before the interruptible App move"

while IFS= read -r local_install_entry; do
    [ "$local_install_entry" = "$INSTALL_SCRIPT" ] \
        || fail "an unlocked local-signing install entry point was found: ${local_install_entry}"
done < <(active_delivery_files \
    | xargs -0 grep -Il 'NARC_SIGNING_MODE=local' 2>/dev/null || true)
grep -Fq '${HOME}/Library/Keychains/login.keychain-db' "$INSTALL_SCRIPT" \
    || fail "install.sh must resolve the login keychain with the same stable path as the identity bootstrap"
if grep -Fq 'security login-keychain' "$INSTALL_SCRIPT"; then
    fail "install.sh must not depend on the unavailable security login-keychain subcommand"
fi

IDENTITY_SCRIPT="${PROJECT_DIR}/scripts/ensure-local-signing-identity.sh"
[ -f "$IDENTITY_SCRIPT" ] \
    || fail "the local signing identity bootstrap script is missing"
grep -Fq 'signing-identity.sha1' "$IDENTITY_SCRIPT" \
    || fail "the bootstrap must persist a non-secret fingerprint marker"
grep -Fq 'readonly LEGACY_IDENTITY_CN="NARC Dev"' "$IDENTITY_SCRIPT" \
    || fail "the migration policy must recognize the legacy local NARC Dev identity"
grep -Fq 'determine_normal_signing_policy' "$IDENTITY_SCRIPT" \
    || fail "the bootstrap must use the tested signer migration policy"
grep -Fq 'POLICY_ACTION="reuse-marker"' "$IDENTITY_SCRIPT" \
    || fail "an existing marker must remain the highest-priority continuity source"
grep -Fq 'POLICY_ACTION="adopt-installed"' "$IDENTITY_SCRIPT" \
    || fail "an eligible installed App signer must be adoptable when the marker is absent"
grep -Fq 'Signature=adhoc' "$IDENTITY_SCRIPT" \
    || fail "ad-hoc installed Apps must be classified separately and never inherited"
grep -Fq '现有 NARC.app 不能是符号链接' "$IDENTITY_SCRIPT" \
    || fail "installed signer migration must reject a symlink App path"
grep -Fq "Print :CFBundleIdentifier" "$IDENTITY_SCRIPT" \
    || fail "installed signer migration must verify the Bundle ID"
grep -Fq 'actual_requirement_upper' "$IDENTITY_SCRIPT" \
    || fail "installed signer migration must compare the exact designated requirement"
grep -Fq -- '--restore-legacy-signer' "$IDENTITY_SCRIPT" \
    || fail "the identity selector must require explicit legacy restore mode"
grep -Fq '完整 40 位指纹' "$IDENTITY_SCRIPT" \
    || fail "legacy signer recovery must require the full old fingerprint"
grep -Fq -- '-T /usr/bin/codesign' "$IDENTITY_SCRIPT" \
    || fail "the bootstrap must scope private-key access to the system codesign tool"
grep -Fq -- '-x' "$IDENTITY_SCRIPT" \
    || fail "the imported local private key must be non-extractable"
grep -Fq '非交互环境不会自动采用来源未知的私钥' "$IDENTITY_SCRIPT" \
    || fail "an unmarked pre-existing identity must require explicit interactive confirmation"
grep -Fq 'remove-trusted-cert' "$IDENTITY_SCRIPT" \
    || fail "failed identity creation must roll back user-domain trust as well as the key and certificate"
if grep -Eq -- '(^|[[:space:]])-A([[:space:]]|$)' "$IDENTITY_SCRIPT"; then
    fail "the identity bootstrap must never grant all applications private-key access"
fi
if grep -Eq -- 'add-trusted-cert.*[[:space:]]-d([[:space:]]|$)|^[[:space:]]+-d[[:space:]]' "$IDENTITY_SCRIPT"; then
    fail "the identity bootstrap must never write administrator-domain trust"
fi

CI_WORKFLOW="${PROJECT_DIR}/.github/workflows/ci.yml"
grep -Fq 'contents: read' "$CI_WORKFLOW" \
    || fail "CI must keep repository contents read-only"
grep -Fq 'NARC_SIGNING_MODE=adhoc bash scripts/build-app.sh release' "$CI_WORKFLOW" \
    || fail "CI must select ad-hoc signing explicitly"
grep -Fq 'bash scripts/tests/signing-migration-policy-tests.sh' "$CI_WORKFLOW" \
    || fail "CI must run the pure signing migration policy tests"
grep -Fq 'bash scripts/tests/install-transaction-tests.sh' "$CI_WORKFLOW" \
    || fail "CI must run signal-safe install transaction tests"

POLICY_TEST_SCRIPT="${PROJECT_DIR}/scripts/tests/signing-migration-policy-tests.sh"
[ -f "$POLICY_TEST_SCRIPT" ] \
    || fail "the pure signing migration policy test suite is missing"
grep -Fq 'expect_normal_success "reuse-marker"' "$POLICY_TEST_SCRIPT" \
    || fail "policy tests must cover marker priority"
grep -Fq 'expect_normal_failure 1 "$LOCAL_FP" stable "$LEGACY_FP"' "$POLICY_TEST_SCRIPT" \
    || fail "policy tests must reject a stable installed signer that conflicts with the marker"
grep -Fq 'expect_normal_success "adopt-installed"' "$POLICY_TEST_SCRIPT" \
    || fail "policy tests must cover safe installed-signer adoption"
grep -Fq 'expect_normal_success "create-local-v1" "" 0 "" adhoc' "$POLICY_TEST_SCRIPT" \
    || fail "policy tests must prove ad-hoc code is not inherited"
grep -Fq 'expect_restore_success' "$POLICY_TEST_SCRIPT" \
    || fail "policy tests must cover explicit legacy signer recovery"
grep -Fq 'NARC_INTERNAL_INSTALL_LOCK_TEST=1' "$POLICY_TEST_SCRIPT" \
    || fail "policy tests must exercise the real install lock path"
grep -Fq 'normal state is not revalidated before replacement' "$POLICY_TEST_SCRIPT" \
    || fail "policy tests must guard normal pre-switch revalidation ordering"

TRANSACTION_TEST_SCRIPT="${PROJECT_DIR}/scripts/tests/install-transaction-tests.sh"
[ -f "$TRANSACTION_TEST_SCRIPT" ] \
    || fail "the install transaction test suite is missing"
grep -Fq 'signal-after-app-move' "$TRANSACTION_TEST_SCRIPT" \
    || fail "transaction tests must send a real signal after the App move"
grep -Fq 'fail-after-marker-move' "$TRANSACTION_TEST_SCRIPT" \
    || fail "transaction tests must fail after the signer marker move"
grep -Fq 'fail-after-final-verification' "$TRANSACTION_TEST_SCRIPT" \
    || fail "transaction tests must cover a post-switch verification failure"
grep -Fq 'hold-after-app-move' "$TRANSACTION_TEST_SCRIPT" \
    || fail "transaction tests must contend for the lock while an App switch is in progress"
grep -Fq 'signal-after-commit' "$TRANSACTION_TEST_SCRIPT" \
    || fail "transaction tests must clean backups when a signal follows commit"

echo "✅ Source-only distribution boundary verified"
