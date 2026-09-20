#!/bin/bash

set -euo pipefail

# This is a deliberately narrow source guard, not a substitute for pointer UI
# testing. It prevents the exact hover replacement and ancestor-tap patterns
# that moved the persistence target underneath the user's pointer.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
SOURCE_PATH="${1:-${PROJECT_DIR}/NARC/Sources/Views/NotificationListView.swift}"
ROW_SOURCE="$(awk '/^struct PinnedWindowRow: View \{/ { copying=1 } /^\/\/ MARK: - App Item Row/ { copying=0 } copying { print }' "$SOURCE_PATH")"
PASS_COUNT=0

fail_test() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

expect_count() {
    local pattern="$1"
    local expected="$2"
    local explanation="$3"
    local actual
    actual="$(printf '%s\n' "$ROW_SOURCE" | grep -Fc "$pattern" || true)"
    [ "$actual" -eq "$expected" ] || fail_test "$explanation (found ${actual}, expected ${expected})"
    PASS_COUNT=$((PASS_COUNT + 1))
}

[ -n "$ROW_SOURCE" ] || fail_test "PinnedWindowRow was not found"
expect_count 'if isHovering' 0 'Hover must not insert/remove persistence or removal targets'
expect_count '.onTapGesture' 0 'Recall must not be an ancestor gesture of maintenance buttons'
expect_count 'Button(action: onTap)' 1 'Recall needs its own semantic button'
expect_count 'Button(action: onTogglePersistence)' 1 'Persistence must always be a semantic button'
expect_count 'Button(role: .destructive, action: onRemove)' 1 'Removal must have a distinct semantic button'
expect_count '.frame(width: 28, height: 28)' 2 'Both maintenance buttons need stable, usable hit areas'
expect_count '.focusable(false)' 3 'Row controls must not take over the existing keyboard-selection route'
expect_count '.accessibilityValue(pinned.isPersistent ? "长期保留" : "临时")' 1 'Persistence state must be exposed to assistive technology'

printf 'Pinned row structure checks passed: %d\n' "$PASS_COUNT"
