#!/bin/bash

set -euo pipefail

# The test itself doubles as tool stubs inside an isolated fixture. Neither
# Swift compilation nor codesign is invoked against the real project.
case "$(basename "$0")" in
    swift)
        if [ "${1:-}" != "build" ]; then
            : >"${NARC_BUILD_TEST_FIXTURE}/icon.called"
            printf 'ICON\n' >"${NARC_BUILD_TEST_FIXTURE}/build/NARC.icns"
            exit 0
        fi
        if [ "${!#}" = "--show-bin-path" ]; then
            printf '%s\n' "$@" >"${NARC_BUILD_TEST_FIXTURE}/query.args"
            case "$NARC_BUILD_TEST_CASE" in
                query-failure) exit 42 ;;
                empty-output) exit 0 ;;
            esac
            printf '%s\n' "${NARC_BUILD_TEST_FIXTURE}/custom output/${NARC_BUILD_TEST_CONFIG}"
        else
            printf '%s\n' "$@" >"${NARC_BUILD_TEST_FIXTURE}/build.args"
            [ "$NARC_BUILD_TEST_CASE" != "build-failure" ] || exit 41
        fi
        exit 0
        ;;
    codesign)
        printf '%s\n' "$*" >>"${NARC_BUILD_TEST_FIXTURE}/codesign.calls"
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
TEST_ROOT="$(mktemp -d /private/tmp/narc-build-output-tests.XXXXXX)"
PASS_COUNT=0

cleanup_tests() {
    case "$TEST_ROOT" in
        /private/tmp/narc-build-output-tests.*) rm -rf -- "$TEST_ROOT" ;;
        *) printf 'Refusing to clean unexpected test path: %s\n' "$TEST_ROOT" >&2 ;;
    esac
}
trap cleanup_tests EXIT

fail_test() {
    printf '❌ %s\n' "$1" >&2
    exit 1
}

run_case() {
    local case_name="$1"
    local config="$2"
    local expected_status="$3"
    local fixture="${TEST_ROOT}/${case_name}-${config}"
    local build_status=0

    mkdir -p "${fixture}/scripts" "${fixture}/NARC/Resources" \
        "${fixture}/tools" "${fixture}/.build/${config}/NARC_NARC.bundle" \
        "${fixture}/custom output/${config}/NARC_NARC.bundle" \
        "${fixture}/build/NARC.app"
    cp "${PROJECT_DIR}/scripts/build-app.sh" "${fixture}/scripts/build-app.sh"
    cp "${PROJECT_DIR}/scripts/narc-codex-hook.py" "${fixture}/scripts/narc-codex-hook.py"
    cp "$0" "${fixture}/tools/swift"
    cp "$0" "${fixture}/tools/codesign"
    chmod +x "${fixture}/tools/swift" "${fixture}/tools/codesign"
    printf 'PLIST\n' >"${fixture}/NARC/Resources/Info.plist"
    printf 'OLD-APP\n' >"${fixture}/build/NARC.app/keep"
    printf 'STALE-EXECUTABLE\n' >"${fixture}/.build/${config}/NARC"
    printf 'STALE-RESOURCE\n' >"${fixture}/.build/${config}/NARC_NARC.bundle/value"
    if [ "$case_name" != "missing-executable" ]; then
        printf 'FRESH-EXECUTABLE\n' >"${fixture}/custom output/${config}/NARC"
    fi
    printf 'FRESH-RESOURCE\n' >"${fixture}/custom output/${config}/NARC_NARC.bundle/value"

    set +e
    PATH="${fixture}/tools:$PATH" \
        NARC_BUILD_TEST_FIXTURE="$fixture" \
        NARC_BUILD_TEST_CASE="$case_name" \
        NARC_BUILD_TEST_CONFIG="$config" \
        SWIFT_BUILD_FLAGS="--scratch-path ${fixture}/scratch --disable-sandbox" \
        NARC_SIGNING_MODE=adhoc \
        bash "${fixture}/scripts/build-app.sh" "$config" \
        >"${fixture}/build.out" 2>"${fixture}/build.err"
    build_status=$?
    set -e
    [ "$build_status" -eq "$expected_status" ] \
        || fail_test "${case_name}/${config}: exit ${build_status}, expected ${expected_status}"

    if [ "$expected_status" -eq 0 ]; then
        cmp "${fixture}/scripts/narc-codex-hook.py" \
            "${fixture}/build/NARC.app/Contents/Resources/narc-codex-hook.py" \
            || fail_test "${case_name}/${config}: completion adapter resource is missing or stale"
        cmp "${fixture}/custom output/${config}/NARC" \
            "${fixture}/build/NARC.app/Contents/MacOS/NARC" \
            || fail_test "${case_name}/${config}: assembled a stale executable"
    fi

    printf '%s\n' build --scratch-path "${fixture}/scratch" --disable-sandbox \
        -c "$config" --package-path "$fixture" >"${fixture}/expected-build.args"
    diff -u "${fixture}/expected-build.args" "${fixture}/build.args" \
        || fail_test "${case_name}/${config}: build did not use the expected flags"

    if [ "$case_name" = "build-failure" ]; then
        [ ! -e "${fixture}/query.args" ] \
            || fail_test "failed compilation still queried the output path"
    else
        [ -e "${fixture}/query.args" ] \
            || fail_test "${case_name}/${config}: build output was not queried"
        sed '$d' "${fixture}/query.args" >"${fixture}/query-build.args"
        diff -u "${fixture}/build.args" "${fixture}/query-build.args" \
            || fail_test "${case_name}/${config}: output query used different build flags"
    fi

    if [ "$expected_status" -eq 0 ]; then
        cmp "${fixture}/custom output/${config}/NARC_NARC.bundle/value" \
            "${fixture}/build/NARC.app/Contents/Resources/NARC_NARC.bundle/value" \
            || fail_test "${case_name}/${config}: assembled stale resources"
        [ -s "${fixture}/codesign.calls" ] \
            || fail_test "${case_name}/${config}: bundle signing stage did not run"
        if grep -Eq '^[[:space:]]*open[[:space:]]' "${fixture}/build.out"; then
            fail_test "${case_name}/${config}: ad-hoc output suggested an unisolated App launch"
        fi
        grep -Fq 'cannot inherit the installed App' "${fixture}/build.out" \
            || fail_test "${case_name}/${config}: ad-hoc output omitted the permission warning"
        grep -Fq 'NARC_DEV_NO_AX=1' "${fixture}/build.out" \
            || fail_test "${case_name}/${config}: ad-hoc output omitted the no-AX launch mode"
    else
        [ "$(sed -n '1p' "${fixture}/build/NARC.app/keep")" = "OLD-APP" ] \
            || fail_test "${case_name}/${config}: previous App changed after a build failure"
        [ ! -e "${fixture}/build/NARC.app/Contents" ] \
            || fail_test "${case_name}/${config}: assembly continued after a build failure"
        [ ! -e "${fixture}/icon.called" ] && [ ! -e "${fixture}/codesign.calls" ] \
            || fail_test "${case_name}/${config}: icon/signing continued after a build failure"
    fi
    PASS_COUNT=$((PASS_COUNT + 1))
}

run_case custom-output debug 0
run_case custom-output release 0
run_case build-failure debug 41
run_case query-failure debug 42
run_case empty-output debug 1
run_case missing-executable debug 1

printf '✅ Build output path tests passed: %d\n' "$PASS_COUNT"
