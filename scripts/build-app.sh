
#!/bin/bash
# build-app.sh — Build NARC.app from Swift Package
# Usage: ./scripts/build-app.sh [release|debug]

set -euo pipefail

BUILD_CONFIG="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="NARC"
APP_BUNDLE="${PROJECT_DIR}/build/${APP_NAME}.app"
BUNDLE_ID="com.mickmi.narc"
SIGNING_MODE="${NARC_SIGNING_MODE:-}"

fail() {
    echo "❌ $1" >&2
    exit "${2:-1}"
}

case "$BUILD_CONFIG" in
    debug|release) ;;
    *) fail "Build configuration must be debug or release." 2 ;;
esac

case "$SIGNING_MODE" in
    local)
        SIGN_IDENTITY="${NARC_SIGN_IDENTITY:-}"
        SIGN_KEYCHAIN="${NARC_SIGN_KEYCHAIN:-}"
        [[ "$SIGN_IDENTITY" =~ ^[0-9A-Fa-f]{40}$ ]] \
            || fail "Local signing requires NARC_SIGN_IDENTITY to be an exact 40-character certificate fingerprint." 2
        [ -n "$SIGN_KEYCHAIN" ] && [ -f "$SIGN_KEYCHAIN" ] \
            || fail "Local signing requires NARC_SIGN_KEYCHAIN to point to an existing keychain." 2
        SIGN_IDENTITY="$(printf '%s' "$SIGN_IDENTITY" | tr '[:lower:]' '[:upper:]')"
        ;;
    adhoc)
        SIGN_IDENTITY="-"
        SIGN_KEYCHAIN=""
        ;;
    "")
        fail "Choose signing explicitly: use scripts/install.sh for normal setup, or set NARC_SIGNING_MODE=adhoc for a disposable development build." 2
        ;;
    *)
        fail "NARC_SIGNING_MODE must be local or adhoc." 2
        ;;
esac

echo "🔨 Building NARC (${BUILD_CONFIG})..."

# Step 1: Build with Swift Package Manager
SWIFT_BUILD_FLAGS="${SWIFT_BUILD_FLAGS:-}"
# Preserve the existing whitespace-separated flag interface while sharing
# exactly one argument list between compilation and output-path discovery.
# shellcheck disable=SC2206
SWIFT_BUILD_ARGS=( $SWIFT_BUILD_FLAGS -c "$BUILD_CONFIG" --package-path "$PROJECT_DIR" )
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
[ -n "$BUILD_DIR" ] || fail "Build failed: Swift returned an empty executable directory."

EXECUTABLE="${BUILD_DIR}/${APP_NAME}"

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Build failed: executable not found at ${EXECUTABLE}"
    exit 1
fi

echo "📦 Assembling ${APP_NAME}.app..."

# Step 2: Create .app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# The one-time AI reminder setup must not depend on a checkout-specific path.
cp "${SCRIPT_DIR}/narc-codex-hook.py" "${APP_BUNDLE}/Contents/Resources/narc-codex-hook.py"

# Step 3: Copy executable
cp "$EXECUTABLE" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Step 4: Copy Info.plist
cp "${PROJECT_DIR}/NARC/Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Step 5: Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Step 6: Copy any bundled resources from SPM build
# SPM puts processed resources in NARC_NARC.bundle
RESOURCE_BUNDLE="${BUILD_DIR}/NARC_NARC.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/Contents/Resources/"
fi

# Step 7 (was after sign — moved BEFORE so codesign seals the icon too):
# Generate + copy app icon. Doing this AFTER codesign would invalidate the
# signature ("a sealed resource is missing or invalid: file added").
echo "🎨 Generating app icon..."
swift "${SCRIPT_DIR}/generate-icon.swift"

if [ -f "${PROJECT_DIR}/build/NARC.icns" ]; then
    cp "${PROJECT_DIR}/build/NARC.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    echo "✓ App icon copied"
else
    echo "⚠️  Icon generation failed — app will show default folder icon"
fi

# Step 8: Sign LAST so macOS validates the complete bundle. Normal installs
# provide the persistent per-user identity; CI and disposable developer builds
# must opt in to ad-hoc explicitly. Never fall back from local to ad-hoc.
echo "🔏 Finalizing local app bundle..."
if [ "$SIGNING_MODE" = "local" ]; then
    DESIGNATED_REQUIREMENT="designated => identifier \"${BUNDLE_ID}\" and certificate leaf = H\"${SIGN_IDENTITY}\""
    codesign --force --deep \
        --sign "$SIGN_IDENTITY" \
        --keychain "$SIGN_KEYCHAIN" \
        --identifier "$BUNDLE_ID" \
        --options runtime \
        --timestamp=none \
        --requirements "=${DESIGNATED_REQUIREMENT}" \
        "$APP_BUNDLE"
else
    codesign --force --deep \
        --sign - \
        --identifier "$BUNDLE_ID" \
        "$APP_BUNDLE"
fi

# Every branch must produce a valid, sealed bundle. Do not print success when
# codesign only appeared to run or a resource changed after signing.
codesign --verify --deep --strict "$APP_BUNDLE"

if [ "$SIGNING_MODE" = "local" ]; then
    codesign --verify --deep --strict \
        --test-requirement "=identifier \"${BUNDLE_ID}\" and certificate leaf = H\"${SIGN_IDENTITY}\"" \
        "$APP_BUNDLE"
    if codesign --display --verbose=4 "$APP_BUNDLE" 2>&1 | grep -Fq 'Signature=adhoc'; then
        fail "Local signing unexpectedly produced an ad-hoc signature."
    fi
fi

echo ""
echo "✅ Successfully built: ${APP_BUNDLE}"
echo ""
echo "📍 Location: ${APP_BUNDLE}"
echo "   Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"
echo ""
if [ "$SIGNING_MODE" = "local" ]; then
    echo "🚀 To run:"
    echo "   open \"${APP_BUNDLE}\""
else
    echo "⚠️  Ad-hoc build: disposable development only."
    echo "   It cannot inherit the installed App's Accessibility permission."
    echo "   Use the no-AX mode below, or install normally to test window tools."
fi
echo ""
echo "🧪 Dev no-AX mode (no permission prompts; panel/quick-capture hotkeys only):"
echo "   NARC_DEV_NO_AX=1 \"${APP_BUNDLE}/Contents/MacOS/${APP_NAME}\""
echo "   or: bash ${SCRIPT_DIR}/dev-run-no-ax.sh ${BUILD_CONFIG}"
if [ "$SIGNING_MODE" = "local" ]; then
    echo ""
    echo "🧪 Terminal-host AX dev mode (no Dock icon; pinning/hotkeys enabled):"
    echo "   bash ${SCRIPT_DIR}/dev-run-terminal-host.sh debug"
fi
echo ""
echo "📋 Normal local setup:"
echo "   bash ${SCRIPT_DIR}/install.sh"
echo "   Window-management tools may request Accessibility permission when used."
