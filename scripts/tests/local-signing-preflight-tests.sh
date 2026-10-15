#!/bin/bash

set -euo pipefail

# Tool doubles only operate on this test's private fixtures, never real keys.
if [ "$(basename "$0")" = "codesign" ]; then
    if [ "${1:-}" = "--force" ]; then
        printf '%s\n' "$@" >"${NARC_SIGNING_TEST_FIXTURE}/sign.args"
        if [ "$NARC_SIGNING_TEST_RESULT" = "sign-failure" ]; then
            printf 'errSecInternalComponent: fixture private key denied\n' >&2
            exit 23
        fi
    elif [ "${1:-}" = "--verify" ]; then
        printf '%s\n' "$@" >"${NARC_SIGNING_TEST_FIXTURE}/verify.args"
        if [ "$NARC_SIGNING_TEST_RESULT" = "verify-failure" ]; then
            printf 'fixture exact certificate requirement failed\n' >&2
            exit 24
        fi
    else
        exit 25
    fi
    exit 0
fi

if [ "${1:-}" = "--bootstrap" ]; then
    fixture="$2"
    mode="$3"
    source "${fixture}/scripts/ensure-local-signing-identity.sh"
    # Replace OS enumeration/creation with deterministic fixture state; retain
    # the real selection, signing, marker-writing and commit paths.
    require_runtime() {
        LOGIN_KEYCHAIN="${fixture}/keychain"
        MARKER_DIR="${fixture}/data"
        MARKER_PATH="${MARKER_DIR}/signing-identity.sha1"
    }
    parse_arguments() { INSTALLED_APP_PATH="${fixture}/Applications/NARC.app"; }
    install_cleanup_traps() { :; }
    create_private_temp_dir() { TEMP_DIR="${fixture}/probe"; }
    inspect_installed_app() {
        if [ "$mode" = "create" ]; then
            INSTALLED_APP_STATE=absent
            INSTALLED_APP_LEAF_FINGERPRINT=""
        else
            INSTALLED_APP_STATE=stable
            INSTALLED_APP_LEAF_FINGERPRINT="$NARC_SIGNING_TEST_FP"
        fi
    }
    scan_identity_state() {
        if [ "$mode" = "create" ] && [ -z "$CREATED_IDENTITY_FINGERPRINT" ]; then
            VALID_IDENTITY_FINGERPRINTS=()
            VALID_IDENTITY_NAMES=()
            LOCAL_CERTIFICATE_FINGERPRINTS=()
        else
            VALID_IDENTITY_FINGERPRINTS=("$NARC_SIGNING_TEST_FP")
            VALID_IDENTITY_NAMES=("$LOCAL_IDENTITY_CN")
            LOCAL_CERTIFICATE_FINGERPRINTS=("$NARC_SIGNING_TEST_FP")
        fi
    }
    create_identity() { CREATED_IDENTITY_FINGERPRINT="$NARC_SIGNING_TEST_FP"; }
    main
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
source "${PROJECT_DIR}/scripts/lib/local-signing-preflight.sh"
TEST_ROOT="$(mktemp -d /private/tmp/narc-signing-preflight-tests.XXXXXX)"
PASS_COUNT=0
NARC_SIGNING_TEST_FP="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
export NARC_SIGNING_TEST_FP

cleanup_tests() {
    case "$TEST_ROOT" in
        /private/tmp/narc-signing-preflight-tests.*) rm -rf -- "$TEST_ROOT" ;;
        *) printf 'Refusing to clean unexpected fixture path: %s\n' "$TEST_ROOT" >&2 ;;
    esac
}
trap cleanup_tests EXIT
fail_test() { printf '❌ %s\n' "$1" >&2; exit 1; }

prepare_fixture() {
    local fixture="$1"
    mkdir -p "${fixture}/probe" "${fixture}/tools" "${fixture}/scripts/lib" "${fixture}/data"
    chmod 700 "${fixture}/probe"
    printf 'fixture-keychain\n' >"${fixture}/keychain"
    cp "$0" "${fixture}/tools/codesign"
    chmod +x "${fixture}/tools/codesign"
    cp "${PROJECT_DIR}/scripts/lib/local-signing-preflight.sh" "${fixture}/scripts/lib/"
    # Only the copied script uses the stub executable; production paths stay
    # fixed to Apple's codesign and cannot be replaced via environment flags.
    sed "s|readonly CODESIGN_BIN=\"/usr/bin/codesign\"|readonly CODESIGN_BIN=\"${fixture}/tools/codesign\"|" \
        "${PROJECT_DIR}/scripts/ensure-local-signing-identity.sh" \
        >"${fixture}/scripts/ensure-local-signing-identity.sh"
}

run_probe_case() {
    local case_name="$1"
    local result="$2"
    local expected_status="$3"
    local fixture="${TEST_ROOT}/${case_name}"
    local fingerprint="$NARC_SIGNING_TEST_FP"
    local status=0
    prepare_fixture "$fixture"
    case "$case_name" in
        invalid-fingerprint) fingerprint="-" ;;
        missing-keychain) rm "${fixture}/keychain" ;;
        occupied-path) printf 'preserve-me\n' >"${fixture}/probe/signing-probe" ;;
    esac
    if NARC_SIGNING_TEST_FIXTURE="$fixture" NARC_SIGNING_TEST_RESULT="$result" \
        narc_verify_local_signing "$fingerprint" "${fixture}/keychain" \
        "${fixture}/probe" "${fixture}/tools/codesign" \
        >"${fixture}/out" 2>"${fixture}/err"; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq "$expected_status" ] || fail_test "$case_name: exit $status"
    case "$case_name" in
        success)
            printf '%s\n' --force --sign "$NARC_SIGNING_TEST_FP" --keychain "${fixture}/keychain" \
                --identifier com.mickmi.narc.signing-probe --options runtime --timestamp=none \
                --requirements "=designated => identifier \"com.mickmi.narc.signing-probe\" and certificate leaf = H\"${NARC_SIGNING_TEST_FP}\"" \
                "${fixture}/probe/signing-probe" >"${fixture}/expected-sign.args"
            diff -u "${fixture}/expected-sign.args" "${fixture}/sign.args" || fail_test 'wrong signer or keychain'
            printf '%s\n' --verify --strict --test-requirement \
                "=identifier \"com.mickmi.narc.signing-probe\" and certificate leaf = H\"${NARC_SIGNING_TEST_FP}\"" \
                "${fixture}/probe/signing-probe" >"${fixture}/expected-verify.args"
            diff -u "${fixture}/expected-verify.args" "${fixture}/verify.args" || fail_test 'exact signer was not verified'
            ;;
        sign-failure)
            [ ! -e "${fixture}/verify.args" ] || fail_test 'verification ran after rejected signature'
            grep -Fq 'codesign exit 23' "${fixture}/err" || fail_test 'signing exit code was lost'
            grep -Fq 'errSecInternalComponent: fixture private key denied' "${fixture}/err" || fail_test 'original signing error was lost'
            ;;
        verify-failure)
            grep -Fq 'codesign exit 24' "${fixture}/err" || fail_test 'verification exit code was lost'
            grep -Fq 'fixture exact certificate requirement failed' "${fixture}/err" || fail_test 'original verification error was lost'
            ;;
        *)
            [ ! -e "${fixture}/sign.args" ] || fail_test 'invalid inputs invoked private-key operation'
            if [ "$case_name" = "occupied-path" ]; then
                [ "$(cat "${fixture}/probe/signing-probe")" = 'preserve-me' ] || fail_test 'occupied path was overwritten'
            fi
            ;;
    esac
    PASS_COUNT=$((PASS_COUNT + 1))
}

run_bootstrap_case() {
    local mode="$1"
    local result="$2"
    local expected_status="$3"
    local fixture="${TEST_ROOT}/bootstrap-${mode}-${result}"
    local status=0
    prepare_fixture "$fixture"
    if [ "$mode" = "reuse" ]; then
        printf '%s\n' "$NARC_SIGNING_TEST_FP" >"${fixture}/data/signing-identity.sha1"
    fi
    if NARC_SIGNING_TEST_FIXTURE="$fixture" NARC_SIGNING_TEST_RESULT="$result" \
        bash "$0" --bootstrap "$fixture" "$mode" >"${fixture}/out" 2>"${fixture}/err"; then
        status=0
    else
        status=$?
    fi
    [ "$status" -eq "$expected_status" ] || fail_test "bootstrap ${mode}/${result}: exit $status"
    if [ "$status" -eq 0 ] || [ "$mode" = "reuse" ]; then
        [ "$(cat "${fixture}/data/signing-identity.sha1")" = "$NARC_SIGNING_TEST_FP" ] || fail_test 'marker missing or changed'
    else
        [ ! -e "${fixture}/data/signing-identity.sha1" ] || fail_test 'failed key was committed to marker'
    fi
    if [ "$status" -eq 0 ]; then
        [ "$(cat "${fixture}/out")" = "$NARC_SIGNING_TEST_FP" ] || fail_test 'success did not return selected signer'
    else
        [ ! -s "${fixture}/out" ] || fail_test 'failed preflight returned a usable signer'
    fi
    PASS_COUNT=$((PASS_COUNT + 1))
}

run_probe_case success success 0
run_probe_case sign-failure sign-failure 1
run_probe_case verify-failure verify-failure 1
run_probe_case invalid-fingerprint success 1
run_probe_case missing-keychain success 1
run_probe_case occupied-path success 1
for mode in create adopt reuse; do
    run_bootstrap_case "$mode" success 0
    run_bootstrap_case "$mode" sign-failure 1
done
run_bootstrap_case create verify-failure 1

printf '✅ Local signing preflight tests passed: %d\n' "$PASS_COUNT"
