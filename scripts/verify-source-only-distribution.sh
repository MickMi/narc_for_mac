#!/bin/bash
# Guard the product boundary: NARC is obtained as source and prepared locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

fail() {
    echo "❌ $1" >&2
    exit 1
}

[ ! -e "${PROJECT_DIR}/.github/workflows/release.yml" ] \
    || fail "prebuilt-app release workflow must not exist"
[ ! -e "${PROJECT_DIR}/scripts/update-restart.sh" ] \
    || fail "certificate-based update script must not exist"

if find "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/.github" \
    -type f ! -name "verify-source-only-distribution.sh" -print0 2>/dev/null \
    | xargs -0 grep -Ein \
        'hdiutil|create-dmg|pkgbuild|productbuild|action-gh-release|gh[[:space:]]+release|NARC\.app\.zip|ditto.*--keepParent|upload-artifact.*NARC|find-identity|NARC_SIGN_IDENTITY|notarytool|stapler|sparkle' \
        >/dev/null 2>&1; then
    fail "an executable packaging, release, certificate, notarization, or updater path was found"
fi

BUILD_SCRIPT="${PROJECT_DIR}/scripts/build-app.sh"
grep -Eq -- '--sign[[:space:]]+-' "$BUILD_SCRIPT" \
    || fail "build-app.sh must finalize the local bundle with an ad-hoc signature"
grep -Fq 'codesign --verify --deep --strict' "$BUILD_SCRIPT" \
    || fail "build-app.sh must strictly verify the completed bundle"

INSTALL_SCRIPT="${PROJECT_DIR}/scripts/install.sh"
grep -Fq 'INSTALL_ROOT="${NARC_INSTALL_DIR:-${HOME}/Applications}"' "$INSTALL_SCRIPT" \
    || fail "install.sh must keep the default app under the user Applications directory"

echo "✅ Source-only distribution boundary verified"
