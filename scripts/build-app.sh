
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
if [ "$BUILD_CONFIG" = "release" ]; then
    swift build -c release --package-path "$PROJECT_DIR"
    BUILD_DIR="${PROJECT_DIR}/.build/release"
else
    swift build --package-path "$PROJECT_DIR"
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

# Step 7: Generate a simple app icon (using system icon as placeholder)
# For a proper icon, replace with an .icns file
# We'll create a minimal icns from the SF Symbol later if needed

echo ""
echo "✅ Successfully built: ${APP_BUNDLE}"
echo ""
echo "📍 Location: ${APP_BUNDLE}"
echo "   Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"
echo ""
echo "🚀 To run:"
echo "   open ${APP_BUNDLE}"
echo ""
echo "📋 To install (copy to /Applications):"
echo "   cp -R ${APP_BUNDLE} /Applications/"
echo "   open /Applications/${APP_NAME}.app"
echo ""
echo "⚠️  Remember to grant Accessibility permission after first launch:"
echo "   System Settings → Privacy & Security → Accessibility → NARC ✅"
