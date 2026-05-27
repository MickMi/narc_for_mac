
# NARC for Mac

**Notification & Application Resource Center** — a native macOS floating widget that unifies notification awareness, app status monitoring, window pinning, window management, and Claude Code session monitoring into a single desktop entry point.

> No more switching between apps to check messages. NARC sits on your desktop, watches everything, and lets you act instantly.

## Features

### 🔔 Unified Notification Center

- Real-time monitoring of **WeChat**, **WeCom (企业微信)**, and **Lark (飞书)** message badges
- Floating widget displays aggregated badge count with red dot indicator
- Click any app in the panel to **summon its window to your current screen** — even if it's minimized or on another display
- Notification filter rules: mute, highlight, badge threshold, keyword matching (extensible)

### 📌 Window Pinning (Cross-Space)

- **Pin any window** to the NARC panel for quick access via `⌃⌥P`
- **Cross-Space activation** — pinned windows on other macOS Spaces are activated via AppleScript, with smooth Space switching (no animation flicker)
- Two persistence modes:
  - **Temporary (📌)** — cleared on restart (default)
  - **Persistent (🔒)** — saved to disk, survives restarts
- Uses **CGWindowID** for precise window identification (no ambiguity with multi-window apps)
- Stable title matching — strips dynamic content (spinners, dimensions) from terminal titles
- Real-time alive status polling and window title tracking
- Up to **10 pinned windows** supported
- Hover to reveal inline actions: toggle persistence, remove

### 🪟 Window Management (Magnet-equivalent)

- **10 layout presets**: Left/Right/Top/Bottom half, four corners, full screen, center
- **Zero-delay window snapping** — single setFrame call, no correction passes or flicker
- Properly handles `AXEnhancedUserInterface` (WeChat, Electron apps)
- **State machine cross-screen** — press same direction within 5s to cross to adjacent display
- **Global hotkeys** for instant window snapping:

  | Hotkey | Action |
  |--------|--------|
  | `⌃⌥←` | Left Half |
  | `⌃⌥→` | Right Half |
  | `⌃⌥↑` | Top Half |
  | `⌃⌥↓` | Bottom Half |
  | `⌃⌥↩` | Full Screen |
  | `⌃⌥C` | Center |
  | `⌃⌥U` | Top Left |
  | `⌃⌥I` | Top Right |
  | `⌃⌥J` | Bottom Left |
  | `⌃⌥K` | Bottom Right |
  | `⌃⌥P` | Pin current window |
  | `⌃⌥N` | Toggle NARC panel |

- **Multi-monitor support** with diagonal screen arrangements

### 🤖 Claude Code Integration

- **Real-time session monitoring** via Unix socket (`/tmp/narc-claude.sock`)
- **Toast notifications** — lightweight, non-intrusive banners at top-right of focused screen
  - Appear for: permission requests, waiting for input, errors, stale sessions
  - Stay visible until resolved (no auto-dismiss)
  - One-click jump to the exact terminal window/tab running Claude
- **Precise terminal targeting** — uses TTY device path + CWD fallback to find the correct terminal tab among multiple windows
- **Quick actions on toast** — Allow/Deny permission requests without leaving your current app
- **NARC circle indicator** — turns orange when Claude needs attention
- **Hook system** — lightweight Python hook (`~/.claude/hooks/narc-hook.py`) intercepts Claude Code events

### ⌨️ Keyboard Navigation

- Press `⌃⌥N` from anywhere to toggle the NARC panel
- Use `↑` / `↓` to navigate items in the panel (auto-scrolls to selection)
- Press `↩` to activate the selected item
- Press `1`–`0` for quick access by index
- Press `Esc` to close the panel

### 🖥 Desktop Widget

- Always-on-top draggable floating icon (48×48pt)
- Click to expand a detail panel with two tabs: **Notifications** and **Shortcuts Reference**
- Orange glow + badge when Claude Code needs attention
- Menu bar icon as a fallback entry point (works in full-screen mode)
- Panel follows the widget when dragged

## Two-Zone Activation Strategy

NARC uses different activation behaviors depending on the window type:

| Zone | Type | Activation Behavior | Rationale |
|------|------|---------------------|-----------|
| **Monitoring** | IM apps (WeChat, Lark, etc.) | Summon to current screen center | Quick message reply |
| **Pinned** | Workspace windows (IDE, docs, etc.) | Switch to window's Space via AppleScript | Preserve workspace layout |

## Requirements

- **macOS 14 Sonoma** or later
- **Accessibility permission** required (System Settings → Privacy & Security → Accessibility)
- **Screen Recording permission** (optional, for cross-Space window detection via CGWindowList)

## Installation

### Build as App (Recommended)

Build a standard macOS `.app` bundle that you can double-click to launch, drag to the Dock, or copy to `/Applications`:

```bash
# Clone the repository
git clone https://github.com/MickMi/narc_for_mac.git
cd narc_for_mac

# Build NARC.app (release mode)
./scripts/build-app.sh

# Launch the app
open build/NARC.app

# (Optional) Install to Applications folder
cp -R build/NARC.app /Applications/
```

After installation, you can launch NARC like any other macOS app — from **Launchpad**, **Spotlight** (`⌘Space` → type "NARC"), or the **Applications folder**. No terminal needed.

### Run from Terminal (Development)

If you prefer to run directly from source during development:

```bash
swift build
swift run NARC
```

### Claude Code Hook Setup

To enable Claude Code integration:

```bash
# Copy the hook script
cp scripts/narc-hook.py ~/.claude/hooks/narc-hook.py
chmod +x ~/.claude/hooks/narc-hook.py
```

Then add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "PermissionRequest": [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "Stop": [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "SessionStart": [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "SessionEnd": [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }]
  }
}
```

### First Launch

On first launch, NARC will prompt you to grant **Accessibility permission** (System Settings → Privacy & Security → Accessibility). After granting, restart NARC for full functionality.

## Usage

### Quick Start

1. Run NARC — a small floating icon appears at the bottom-right of your screen
2. **Grant Accessibility permission** when prompted (required for window management and badge reading)
3. Click the floating icon (or press `⌃⌥N`) to expand the notification panel
4. Use `⌃⌥` + arrow keys to snap windows to screen edges
5. Use `⌃⌥P` to pin the current window for quick access

### Notification Panel

- Divided into two sections: **Monitoring** and **Pinned**
- **Monitoring** — shows IM apps with running status and badge count
  - **Green dot** = running, no new messages
  - **Red badge** = has unread messages
  - **Gray dot** = not running
  - Click an app row to summon its window to your current screen
- **Pinned** — shows user-pinned windows
  - Click to activate the window (switches Space if needed)
  - Hover to toggle persistence (📌 ↔ 🔒) or remove
  - **Gray dot** = window/app not running

### Claude Code Monitoring

- NARC automatically monitors active Claude Code sessions
- When Claude needs attention, a toast notification appears at the top-right
- Click the notification to jump directly to the correct terminal tab
- Permission requests can be approved/denied from the toast itself
- The NARC circle turns orange when there are pending items

### Settings

- Access via the gear icon in the panel header
- Configure which apps to monitor
- Manage notification filter rules
- Customize general preferences

## Architecture

```
NARC/
├── Sources/
│   ├── App/
│   │   ├── NARCApp.swift              # App entry point
│   │   └── AppDelegate.swift          # Window lifecycle, menu bar, hotkeys, toast notifications
│   ├── Models/
│   │   ├── Models.swift               # MonitoredApp, NotificationState, WindowLayout, PinnedWindow
│   │   └── KeyboardSelection.swift    # KeyboardSelectionState, PanelItem enum
│   ├── Services/
│   │   ├── AppMonitorService.swift    # Dock badge polling via lsappinfo, app activation
│   │   ├── ClaudeSessionService.swift # Unix socket listener, session state, approval handling
│   │   ├── HotkeyService.swift        # Carbon Event hotkey registration and dispatch
│   │   ├── PinnedWindowService.swift  # Cross-Space window pinning via AppleScript
│   │   ├── ScreenNavigator.swift      # Multi-monitor edge detection, cross-screen navigation
│   │   ├── WindowLayoutState.swift    # State machine for cross-screen decisions (5s TTL)
│   │   └── WindowManagerService.swift # AX API window control, layout application
│   ├── Utils/
│   │   └── AXWindowHelper.swift       # Low-level AX API, AXEnhancedUserInterface handling
│   └── Views/
│       ├── ClaudeApprovalView.swift   # Full approval panel (panel integration)
│       ├── ClaudeToastView.swift      # Lightweight toast notification banner
│       ├── FloatingWidgetView.swift   # Draggable floating icon with Claude badge
│       ├── FloatingWidgetWindow.swift # NSPanel configuration
│       ├── NotificationListView.swift # Two-section list with keyboard scroll-follow
│       ├── PanelView.swift            # Main expandable panel (tabs)
│       ├── WindowGridView.swift       # Keyboard shortcuts reference guide
│       └── PreferencesView.swift      # Settings panel
├── Resources/
│   ├── Info.plist                     # App bundle configuration
│   └── placeholder.json
├── Tests/
│   └── NARCTests.swift
└── scripts/
    ├── build-app.sh                   # Build .app bundle from Swift Package
    └── narc-hook.py                   # Claude Code hook script (copy to ~/.claude/hooks/)
```

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9 |
| UI Framework | SwiftUI + AppKit (NSPanel, NSStatusBar) |
| Window Control | Accessibility API (AXUIElement) |
| Cross-Space | AppleScript (Apple Events) |
| Badge Reading | `lsappinfo` CLI (reliable on macOS 14+) |
| Hotkeys | Carbon Event API (RegisterEventHotKey) |
| Claude Integration | Unix socket IPC + Python hook |
| Build System | Swift Package Manager |
| Min. Deployment | macOS 14 Sonoma |

### Key Design Decisions

- **Native macOS app** — deepest system integration, no Electron overhead
- **Not sandboxed** — full Accessibility API access for window management and badge reading
- **AppleScript for cross-Space** — `set index + activate` for zero-animation Space switching (CGS private APIs unreliable on macOS 15)
- **TTY-based terminal targeting** — each terminal tab has a unique TTY, enabling precise jump-to-window across multiple terminal sessions
- **State machine for cross-screen** — remembers last layout per window (5s TTL) instead of frame detection, eliminating unreliable geometry matching
- **AXEnhancedUserInterface handling** — disable before resize, Size→Position→Size order (Rectangle/Magnet pattern)
- **Stable title matching** — strips dynamic content (spinners ⠂⠈⠐, dimensions 80×24) from terminal titles, matches by directory prefix only
- **Non-activating panels** — toast notifications and floating widget never steal keyboard focus from the current app

## Changelog

### v1.2 (Current)

- ✅ **Claude Code Integration** — real-time session monitoring with toast notifications and precise terminal jump
- ✅ **Cross-Space Window Activation** — AppleScript-based Space switching for pinned windows (replaces broken CGS API)
- ✅ **Magnet-equivalent Window Management** — zero-delay snapping with AXEnhancedUserInterface handling
- ✅ **State Machine Cross-Screen** — press same hotkey within 5s to move window to adjacent display
- ✅ **TTY-based Terminal Targeting** — click toast to jump to exact terminal tab, not random window
- ✅ **ScrollView Keyboard Following** — panel auto-scrolls when navigating past visible area
- ✅ **Shortcuts Reference Tab** — Window Management tab now shows hotkey reference instead of redundant buttons

### v1.1

- ✅ **Window Pinning** — pin any window via `⌃⌥P` for quick access from the NARC panel
- ✅ **Persistence modes** — temporary (📌) or persistent (🔒) pinned windows
- ✅ **Keyboard navigation** — `⌃⌥N` to toggle panel, `↑↓↩` to navigate and activate, `1`–`0` for quick index access
- ✅ **Two-zone activation strategy** — Monitoring windows summon to current screen; Pinned windows activate in place
- ✅ **Pinned window alive polling** — real-time status and title tracking for pinned windows

### v1.0

- ✅ Draggable floating widget with badge aggregation
- ✅ Expandable panel with Notifications and Window Management tabs
- ✅ Menu bar fallback entry point
- ✅ Real-time Dock badge monitoring (WeChat, WeCom, Lark)
- ✅ Click-to-activate with window summoning to current screen
- ✅ Minimized window unminimize support
- ✅ 10 window layout presets with global hotkeys
- ✅ Multi-monitor support with cross-screen switching
- ✅ Notification filter rules (mute, highlight, threshold, keyword)
- ✅ Settings panel with app management and filter configuration
- ✅ Accessibility permission auto-detection and guided setup

### Known Limitations

- WeCom (企业微信) badge detection relies on `lsappinfo`; WeCom uses custom Dock badge rendering which may not always be detected
- Claude Code hook requires manual installation (copy script + edit settings.json)
- Cross-Space window activation depends on AppleScript window title matching; very similar titles may cause ambiguity
- No auto-update mechanism yet (planned: Sparkle framework)

## Roadmap

| Version | Focus |
|---------|-------|
| **v1.2** ← current | Claude Code integration, cross-Space activation, Magnet-equivalent window management |
| v1.3 | Developer ID signing + Notarization + GitHub Release CI |
| v1.4 | Drag-to-edge window snapping, user preference persistence |
| v2.0 | IDE task monitoring (VS Code extension bridge) |
| v2.1 | Message content preview ("who sent what") |
| v3.0 | Plugin/extension system for third-party integrations |

## License

MIT

## Contributing

This project is in active development. Issues and PRs are welcome.

---

*Built with Swift, SwiftUI, and a lot of ⌃⌥ key combos.*
