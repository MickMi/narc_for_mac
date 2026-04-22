
# NARC for Mac

**Notification & Application Resource Center** — a native macOS floating widget that unifies notification awareness, app status monitoring, window pinning, and window management into a single desktop entry point.

> No more switching between apps to check messages. NARC sits on your desktop, watches everything, and lets you act instantly.

## Features

### 🔔 Unified Notification Center

- Real-time monitoring of **WeChat**, **WeCom (企业微信)**, and **Lark (飞书)** message badges
- Floating widget displays aggregated badge count with red dot indicator
- Click any app in the panel to **summon its window to your current screen** — even if it's minimized or on another display
- Notification filter rules: mute, highlight, badge threshold, keyword matching (extensible)

### 📌 Window Pinning

- **Pin any window** to the NARC panel for quick access via `⌃⌥P`
- Two persistence modes:
  - **Temporary (📌)** — cleared on restart (default)
  - **Persistent (🔒)** — saved to disk, survives restarts
- Pinned windows are **workspace windows** — activating them preserves their original position and size (no relocation)
- Real-time alive status polling and window title tracking
- Up to **10 pinned windows** supported
- Hover to reveal inline actions: toggle persistence, remove

### 🪟 Window Management (Magnet-like)

- **10 layout presets**: Left/Right/Top/Bottom half, four corners, full screen, center
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

- **Multi-monitor support** with cross-screen switching — press the same direction key twice at a screen edge to move the window to the adjacent display
- **Diagonal screen arrangements** supported (e.g., top-left / bottom-right layout)

### ⌨️ Keyboard Navigation

- Press `⌃⌥N` from anywhere to toggle the NARC panel
- Use `↑` / `↓` to navigate items in the panel
- Press `↩` to activate the selected item
- Press `1`–`0` for quick access by index
- Press `Esc` to close the panel

### 🖥 Desktop Widget

- Always-on-top draggable floating icon (48×48pt)
- Click to expand a detail panel with two tabs: **Notifications** and **Window Management**
- Menu bar icon as a fallback entry point (works in full-screen mode)
- Panel follows the widget when dragged

## Two-Zone Activation Strategy

NARC uses different activation behaviors depending on the window type:

| Zone | Type | Activation Behavior | Rationale |
|------|------|---------------------|-----------|
| **Monitoring** | IM apps (WeChat, Lark, etc.) | Summon to current screen center | Quick message reply |
| **Pinned** | Workspace windows (IDE, docs, etc.) | Activate in place — no move, no resize | Preserve workspace layout |

## Requirements

- **macOS 14 Sonoma** or later
- **Accessibility permission** required (System Settings → Privacy & Security → Accessibility)

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

### First Launch

On first launch, NARC will prompt you to grant **Accessibility permission** (System Settings → Privacy & Security → Accessibility). After granting, restart NARC for full functionality.

### GitHub Releases

Pre-built binaries will be available on the [Releases](https://github.com/MickMi/narc_for_mac/releases) page (coming soon).

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
  - Click to activate the window in its original position
  - Hover to toggle persistence (📌 ↔ 🔒) or remove
  - **Gray dot** = window/app not running

### Window Management

- Use the **Window Management** tab in the panel for visual layout selection
- Or use **global hotkeys** from anywhere — no need to open NARC first
- At a screen edge, press the same direction again to **cross to the next monitor**

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
│   │   └── AppDelegate.swift          # Window lifecycle, menu bar, hotkeys, keyboard nav
│   ├── Models/
│   │   ├── Models.swift               # MonitoredApp, NotificationState, WindowLayout, NotificationFilter, PinnedWindow
│   │   └── KeyboardSelection.swift    # KeyboardSelectionState, PanelItem enum
│   ├── Services/
│   │   ├── AppMonitorService.swift    # Dock badge polling via lsappinfo, app activation
│   │   ├── HotkeyService.swift        # Carbon Event hotkey registration and dispatch
│   │   ├── PinnedWindowService.swift  # Pinned window CRUD, polling, persistence, activation
│   │   ├── ScreenNavigator.swift      # Multi-monitor edge detection, cross-screen navigation
│   │   └── WindowManagerService.swift # Accessibility API window control, layout application
│   ├── Utils/
│   │   └── AXWindowHelper.swift       # Low-level AX API operations, coordinate conversion
│   └── Views/
│       ├── FloatingWidgetView.swift   # Draggable floating icon
│       ├── FloatingWidgetWindow.swift # NSPanel configuration
│       ├── NotificationListView.swift # Two-section list (Monitoring + Pinned) with keyboard highlight
│       ├── PanelView.swift            # Main expandable panel (tabs)
│       ├── WindowGridView.swift       # Visual layout grid
│       └── PreferencesView.swift      # Settings panel
├── Resources/
│   ├── Info.plist                     # App bundle configuration
│   └── placeholder.json
├── Tests/
│   └── NARCTests.swift
└── scripts/
    └── build-app.sh                   # Build .app bundle from Swift Package
```

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9 |
| UI Framework | SwiftUI + AppKit (NSPanel, NSStatusBar) |
| Window Control | Accessibility API (AXUIElement) |
| Badge Reading | `lsappinfo` CLI (reliable on macOS 14+) |
| Hotkeys | Carbon Event API (RegisterEventHotKey) |
| Build System | Swift Package Manager |
| Min. Deployment | macOS 14 Sonoma |

### Key Design Decisions

- **Native macOS app** — deepest system integration, no Electron overhead
- **Not sandboxed** — full Accessibility API access for window management and badge reading
- **Dock badge via `lsappinfo`** — more reliable than AXStatusLabel on macOS 14+/15+
- **Edge-based cross-screen detection** — supports diagonal multi-monitor arrangements
- **AX API for window unminimize** — handles minimized windows when summoning apps
- **Two-zone activation** — IM windows summon to current screen for quick reply; pinned workspace windows stay in place to preserve layout

## Changelog

### v1.1 (Current)

- ✅ **Window Pinning** — pin any window via `⌃⌥P` for quick access from the NARC panel
- ✅ **Persistence modes** — temporary (📌) or persistent (🔒) pinned windows
- ✅ **Keyboard navigation** — `⌃⌥N` to toggle panel, `↑↓↩` to navigate and activate, `1`–`0` for quick index access
- ✅ **Two-zone activation strategy** — Monitoring windows summon to current screen; Pinned windows activate in place
- ✅ **Pinned window alive polling** — real-time status and title tracking for pinned windows
- ✅ **Panel sections** — Monitoring and Pinned sections with section headers and keyboard index display

### v1.0

- ✅ Draggable floating widget with badge aggregation
- ✅ Expandable panel with Notifications and Window Management tabs
- ✅ Menu bar fallback entry point
- ✅ Real-time Dock badge monitoring (WeChat, WeCom, Lark)
- ✅ Click-to-activate with window summoning to current screen
- ✅ Minimized window unminimize support
- ✅ 10 window layout presets with global hotkeys
- ✅ Multi-monitor support with cross-screen switching
- ✅ Diagonal screen arrangement support (edge-based detection)
- ✅ Notification filter rules (mute, highlight, threshold, keyword)
- ✅ Settings panel with app management and filter configuration
- ✅ Accessibility permission auto-detection and guided setup

### Known Limitations

- WeCom (企业微信) badge detection relies on `lsappinfo`; WeCom uses custom Dock badge rendering which may not always be detected
- IDE task monitoring (VS Code Copilot status) is planned for v2.0
- Drag-to-edge window snapping is planned for a future release
- No auto-update mechanism yet (planned: Sparkle framework)

## Roadmap

| Version | Focus |
|---------|-------|
| **v1.1** ← current | Window pinning, keyboard navigation, two-zone activation |
| v1.2 | Developer ID signing + Notarization + GitHub Release CI |
| v1.3 | Drag-to-edge window snapping, user preference persistence |
| v2.0 | IDE task monitoring (VS Code extension bridge) |
| v2.1 | Message content preview ("who sent what") |
| v3.0 | Plugin/extension system for third-party integrations |

## License

MIT

## Contributing

This project is in active development. Issues and PRs are welcome.

---

*Built with Swift, SwiftUI, and a lot of ⌃⌥ key combos.*
