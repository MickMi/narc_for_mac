#!/bin/bash
# Build and run NARC in development mode without Accessibility-dependent paths.
#
# This is for high-frequency UI / Workspace / terminal testing. It intentionally
# skips permission prompts, AX-based pin/layout hotkeys, window snapping,
# AX window control, and system notification authorization. Monitoring still
# runs for non-AX badge/status data, and panel/workspace hotkeys stay available.
#
# Usage:
#   bash scripts/dev-run-no-ax.sh [debug|release]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_CONFIG="${1:-debug}"
APP_BUNDLE="${PROJECT_DIR}/build/NARC.app"
EXECUTABLE="${APP_BUNDLE}/Contents/MacOS/NARC"

echo "🧪 Building NARC for dev no-AX mode (${BUILD_CONFIG})..."
bash "${SCRIPT_DIR}/build-app.sh" "${BUILD_CONFIG}"

echo "🛑 Stopping any running NARC process..."
pkill -x NARC 2>/dev/null || true
sleep 0.3

echo "🚀 Running with NARC_DEV_NO_AX=1"
echo "   AX-dependent features disabled; Workspace / terminal / UI remain available."
echo "   ⌃⌥N / ⌃⌥W remain active; ⌃⌥P and layout hotkeys require normal AX mode."
NARC_DEV_NO_AX=1 "${EXECUTABLE}"
