
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

echo "🔨 Building NARC (${BUILD_CONFIG})..."

# Step 1: Build with Swift Package Manager
SWIFT_BUILD_FLAGS="${SWIFT_BUILD_FLAGS:-}"
if [ "$BUILD_CONFIG" = "release" ]; then
    swift build $SWIFT_BUILD_FLAGS -c release --package-path "$PROJECT_DIR"
    BUILD_DIR="${PROJECT_DIR}/.build/release"
else
    swift build $SWIFT_BUILD_FLAGS --package-path "$PROJECT_DIR"
    BUILD_DIR="${PROJECT_DIR}/.build/debug"
fi

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

# Step 8: Apply a local ad-hoc signature LAST so macOS can validate the complete
# bundle. This is an automatic build detail: users never need a certificate,
# signing identity, paid developer account, or separate signing command.
echo "🔏 Finalizing local app bundle..."
codesign --force --deep \
    --sign - \
    --identifier "$BUNDLE_ID" \
    "$APP_BUNDLE"

# Every branch must produce a valid, sealed bundle. Do not print success when
# codesign only appeared to run or a resource changed after signing.
codesign --verify --deep --strict "$APP_BUNDLE"

echo ""
echo "✅ Successfully built: ${APP_BUNDLE}"
echo ""
echo "📍 Location: ${APP_BUNDLE}"
echo "   Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"
echo ""
echo "🚀 To run:"
echo "   open ${APP_BUNDLE}"
echo ""
echo "🧪 Dev no-AX mode (no permission prompts; panel/quick-capture hotkeys only):"
echo "   NARC_DEV_NO_AX=1 ${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
echo "   or: bash ${SCRIPT_DIR}/dev-run-no-ax.sh ${BUILD_CONFIG}"
echo ""
echo "🧪 Terminal-host AX dev mode (no Dock icon; pinning/hotkeys enabled):"
echo "   bash ${SCRIPT_DIR}/dev-run-terminal-host.sh debug"
echo ""
echo "📋 Normal local setup:"
echo "   bash ${SCRIPT_DIR}/install.sh"
echo "   Window-management tools may request Accessibility permission when used."
