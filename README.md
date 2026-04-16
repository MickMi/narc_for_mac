
# NARC for Mac

**Notification & Application Resource Center** — a native macOS floating widget that unifies notification awareness, app status monitoring, and window management into a single desktop entry point.

> No more switching between apps to check messages. NARC sits on your desktop, watches everything, and lets you act instantly.

## Features

### 🔔 Unified Notification Center

- Real-time monitoring of **WeChat**, **WeCom (企业微信)**, and **Lark (飞书)** message badges
- Floating widget displays aggregated badge count with red dot indicator
- Click any app in the panel to **summon its window to your current screen** — even if it's minimized or on another display
- Notification filter rules: mute, highlight, badge threshold, keyword matching (extensible)

### 🪟 Window Management (Magnet-like)

- **10 layout presets**: Left/Right/Top/Bottom half, four corners, full screen, center
- **Global hotkeys** for instant window snapping:

  | Hotkey | Layout |
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

- **Multi-monitor support** with cross-screen switching — press the same direction key twice at a screen edge to move the window to the adjacent display
- **Diagonal screen arrangements** supported (e.g., top-left / bottom-right layout)

### 🖥 Desktop Widget

- Always-on-top draggable floating icon (48×48pt)
- Click to expand a detail panel with two tabs: **Notifications** and **Window Management**
- Menu bar icon as a fallback entry point (works in full-screen mode)
- Panel follows the widget when dragged

## Requirements

- **macOS 14 Sonoma** or later
- **Accessibility permission** required (System Settings → Privacy & Security → Accessibility)

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/MickMi/narc_for_mac.git
cd narc_for_mac

# Build
swift build

# Run
swift run NARC
```

On first launch, NARC will prompt you to grant **Accessibility permission**. After granting, restart NARC for full functionality.

### GitHub Releases

Pre-built binaries will be available on the [Releases](https://github.com/MickMi/narc_for_mac/releases) page (coming soon).

## Usage

### Quick Start

1. Run NARC — a small floating icon appears at the bottom-right of your screen
2. **Grant Accessibility permission** when prompted (required for window management and badge reading)
3. Click the floating icon to expand the notification panel
4. Use `⌃⌥` + arrow keys to snap windows to screen edges

### Notification Panel

- Shows monitored apps with their running status and badge count
- **Green dot** = running, no new messages
- **Red badge** = has unread messages
- **Gray dot** = not running
- Click an app row to activate it and bring its window to your current screen

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
│   │   └── AppDelegate.swift          # Window lifecycle, menu bar, hotkeys
│   ├── Models/
│   │   └── Models.swift               # MonitoredApp, NotificationState, WindowLayout, NotificationFilter
│   ├── Services/
│   │   ├── AppMonitorService.swift    # Dock badge polling via lsappinfo, app activation
│   │   └── WindowManagerService.swift # Accessibility API window control, global hotkeys
│   └── Views/
│       ├── FloatingWidgetView.swift   # Draggable floating icon
│       ├── FloatingWidgetWindow.swift # NSPanel configuration
│       ├── PanelView.swift            # Main expandable panel (tabs)
│       ├── NotificationListView.swift # App status list with badges
│       ├── WindowGridView.swift       # Visual layout grid
│       └── PreferencesView.swift      # Settings panel
├── Resources/
│   └── placeholder.json
└── Tests/
    └── NARCTests.swift
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

## v1.0 Changelog

### What's Included

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
| **v1.0** ← current | Core notification center + window management |
| v1.1 | Drag-to-edge window snapping, user preference persistence |
| v1.2 | Developer ID signing + Notarization + GitHub Release CI |
| v2.0 | IDE task monitoring (VS Code extension bridge) |
| v2.1 | Message content preview ("who sent what") |
| v3.0 | Plugin/extension system for third-party integrations |

## License

MIT

## Contributing

This project is in active development. Issues and PRs are welcome.

---

*Built with Swift, SwiftUI, and a lot of ⌃⌥ key combos.*
