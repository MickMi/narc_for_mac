#!/bin/bash
# Build and run NARC as a terminal-hosted development process.
#
# This restores the early high-frequency test workflow:
# - no Dock icon
# - no .app bundle identity churn
# - Accessibility-dependent features stay enabled
# - window pinning (⌃⌥P), panel (⌃⌥N), Workspace (⌃⌥W), and layout hotkeys run normally
#
# Grant Accessibility to the terminal host you launch this from once
# (Terminal, iTerm, Codex, etc.). Do not use NARC_DEV_NO_AX with this script.
#
# Usage:
#   bash scripts/dev-run-terminal-host.sh [debug|release]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_CONFIG="${1:-debug}"

echo "🧪 Running NARC in terminal-host AX dev mode (${BUILD_CONFIG})..."
echo "   Dock icon hidden; AX-dependent features remain enabled."
echo "   ⌃⌥P / ⌃⌥N / ⌃⌥W and layout hotkeys use the terminal host's Accessibility grant."

echo "🛑 Stopping any running NARC process..."
pkill -x NARC 2>/dev/null || true
sleep 0.3

unset NARC_DEV_NO_AX
export NARC_DEV_TERMINAL_HOST=1

if [ "$BUILD_CONFIG" = "release" ]; then
    swift run --package-path "$PROJECT_DIR" -c release NARC
else
    swift run --package-path "$PROJECT_DIR" NARC
fi
