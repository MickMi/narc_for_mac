
# NARC for Mac

**Notification & Application Resource Center** — a native macOS Dock app that unifies notification awareness, app status monitoring, window pinning, window management, and a built-in multi-terminal Claude Code workspace into a single desktop entry point.

> No more switching between apps to check messages or hunt for the right Claude terminal. NARC sits on your desktop, watches everything, and lets you act instantly.

## Features

### 🛠 NARC Workspace (Embedded Multi-Terminal Dashboard)

- **Multiple Claude Code (or any shell) sessions in one window** — left tab list, right interactive terminal pane
- **Real PTY-backed terminals** powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — full ANSI support, kitty keyboard protocol, OSC 7 cwd tracking
- **Persistent across window close** — closing the Dashboard does *not* kill child processes; reopen and pick up exactly where you left off (Option A persistence)
- **Live status badges per tab** — every tab shows the live Claude state from the hook stream:
  - `⏳ 思考中` / `→ 工具名` / `⚠️ 待审批` / `💬 等待输入` / `🗜 压缩上下文` / `■ 已结束`
- **Attention highlighting** — tabs flash red when Claude is waiting for permission
- **Auto-tracked cwd + project name** via OSC 7 escape sequences
- **Custom tab titles** — double-click to rename, or hover for a pencil button
- **Right-click the floating widget** to summon / dismiss the Dashboard

### 🔔 Unified Notification Center

- Real-time monitoring of **WeChat**, **WeCom (企业微信)**, and **Lark (飞书)** message badges
- Floating widget displays aggregated badge count with red dot indicator
- **Claude section in the panel** — pending approvals and Stop/Error notifications get their own list with single-click dismiss and jump-to-Dashboard
- Click any IM app row to **summon its window to your current screen** — even if it's minimized or on another display
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
- **Three notification surfaces** — pick the one that fits the moment:
  - **Workspace tab badge** — every Claude session in the Dashboard shows its live state inline
  - **Panel "Claude" section** — pending approvals and Stop/Error events with single-click dismiss
  - **Toast banner** — for sessions running outside the Dashboard (e.g. external iTerm)
- **Precise terminal targeting** — `NARC_SESSION_ID` env var ties hook events back to the workspace tab that spawned them; falls back to TTY device path + CWD for external terminals
- **Quick actions on toast** — Allow/Deny permission requests without leaving your current app
- **Hook system** — lightweight Python hook (`~/.claude/hooks/narc-hook.py`) intercepts Claude Code events

### 🖥 Floating Widget (per design spec)

- Always-on-top draggable circular icon (48×48pt)
- **`.regularMaterial` halo** with bloom + slow sonar ripple + breathing "NARC" wordmark (spec D)
- **Soft dual-layer drop shadow** rendered in a 128×128 transparent canvas — only the central 48pt is hit-testable, surrounding shadow area is click-through
- **Red badge** with aggregated count (IM messages + Claude pending items)
- **Tilt + lift** when dragged
- Click → expand the notification panel
- Right-click → toggle the Dashboard
- Drag anywhere on screen — panel follows; menu bar icon as fallback entry

### ⌨️ Keyboard Navigation

- Press `⌃⌥N` from anywhere to toggle the NARC panel
- Use `↑` / `↓` to navigate items in the panel (auto-scrolls to selection)
- Press `↩` to activate the selected item
- Press `1`–`0` for quick access by index
- Press `Esc` to close the panel

## Two-Zone Activation Strategy

NARC uses different activation behaviors depending on the window type:

| Zone | Type | Activation Behavior | Rationale |
|------|------|---------------------|-----------|
| **Monitoring** | IM apps (WeChat, Lark, etc.) | Summon to current screen center | Quick message reply |
| **Pinned** | Workspace windows (IDE, docs, etc.) | Switch to window's Space via AppleScript | Preserve workspace layout |
| **Workspace** | Embedded NARC terminals | Right-click widget → switch tab | No external window juggling |

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

# Build NARC.app (release mode) — also signs with a stable self-signed
# identity so Accessibility permission survives rebuilds
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
swift run -c release NARC
```

> **Note**: SwiftTerm is fetched on first build (~30s). Subsequent builds are incremental.

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

The hook reads `NARC_SESSION_ID` from the environment when set (NARC injects this for terminals spawned inside the Workspace), so events route back to the exact tab that triggered them.

### First Launch

On first launch, NARC will prompt you to grant **Accessibility permission** (System Settings → Privacy & Security → Accessibility). After granting, restart NARC for full functionality.

## Usage

### Quick Start

1. Run NARC — a small floating circle appears at the bottom-right of your screen, the Dashboard auto-opens on first launch
2. **Grant Accessibility permission** when prompted (required for window management and badge reading)
3. Click the floating widget (or press `⌃⌥N`) to expand the notification panel
4. **Right-click** the widget to summon the Workspace Dashboard
5. Click "+ 新建终端" in the Dashboard to start a new shell or `claude` session
6. Use `⌃⌥` + arrow keys to snap windows to screen edges
7. Use `⌃⌥P` to pin the current window for quick access

### Workspace Dashboard

- **Toolbar**: project counter + "+ 新建终端" button
- **Left tabs**: each row shows status dot, custom or auto title, cwd (~ collapsed), creation time, and Claude state badge
- **Right pane**: the live, interactive terminal of the selected tab (input goes to whichever tab is selected)
- **Persistence**: closing the Dashboard window keeps PTYs alive — reopen and your tabs are still there
- **Rename a tab**: double-click the title or click the pencil button
- **Close a tab**: hover and click ✕ (terminates the PTY)

### Notification Panel

- **Claude** section (when active) — top of the list, shows pending approvals (red tint) and Stop/Error notifications. Tap row → dismiss + open Dashboard. Tap ✕ → dismiss only.
- **Monitoring** — IM apps with running status and badge count
  - **Green dot** = running, no new messages
  - **Red badge** = has unread messages
  - **Gray dot** = not running
  - Click an app row to summon its window to your current screen
- **Pinned** — user-pinned windows
  - Click to activate the window (switches Space if needed)
  - Hover to toggle persistence (📌 ↔ 🔒) or remove
  - **Gray dot** = window/app not running

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
│   │   └── AppDelegate.swift          # Window lifecycle, menu bar, hotkeys, dashboard summoning
│   ├── Models/
│   │   ├── Models.swift               # MonitoredApp, NotificationState, WindowLayout, PinnedWindow
│   │   └── KeyboardSelection.swift    # KeyboardSelectionState, PanelItem enum
│   ├── Services/
│   │   ├── AppMonitorService.swift    # Dock badge polling via lsappinfo, app activation
│   │   ├── ClaudeSessionService.swift # Unix socket listener, sessions / approvals / notifications
│   │   ├── HotkeyService.swift        # Carbon Event hotkey registration and dispatch
│   │   ├── PinnedWindowService.swift  # Cross-Space window pinning via AppleScript
│   │   ├── ScreenNavigator.swift      # Multi-monitor edge detection, cross-screen navigation
│   │   ├── TerminalSessionManager.swift # OwnedSession state, Claude state projection by NARC_SESSION_ID
│   │   ├── WindowLayoutState.swift    # State machine for cross-screen decisions (5s TTL)
│   │   └── WindowManagerService.swift # AX API window control, layout application
│   ├── Utils/
│   │   └── AXWindowHelper.swift       # Low-level AX API, AXEnhancedUserInterface handling
│   └── Views/
│       ├── ClaudeApprovalView.swift   # Full approval panel (panel integration)
│       ├── ClaudeToastView.swift      # Lightweight toast notification banner
│       ├── DashboardView.swift        # Workspace toolbar + HSplitView (tabs / pane)
│       ├── DashboardWindow.swift      # Standalone NSWindow for the workspace
│       ├── FloatingWidgetView.swift   # Spec-D circle + halo + bloom + ripple + wordmark + badge
│       ├── FloatingWidgetWindow.swift # 128×128 NSPanel with central 48pt hit-test
│       ├── NotificationListView.swift # Claude / Monitoring / Pinned sections
│       ├── PanelView.swift            # Main expandable panel (tabs)
│       ├── TerminalPaneView.swift     # SwiftUI wrapper around SwiftTerm + PTY plumbing
│       ├── WindowGridView.swift       # Keyboard shortcuts reference guide
│       └── PreferencesView.swift      # Settings panel
├── Resources/
│   ├── Info.plist                     # App bundle configuration
│   └── placeholder.json
├── Tests/
│   └── NARCTests.swift
└── scripts/
    ├── build-app.sh                   # Build .app bundle + stable self-signed identity
    └── narc-hook.py                   # Claude Code hook script (copy to ~/.claude/hooks/)
```

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9 |
| UI Framework | SwiftUI + AppKit (NSPanel, NSStatusBar, NSHostingView) |
| Embedded Terminal | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.2.x (LocalProcessTerminalView) |
| Window Control | Accessibility API (AXUIElement) |
| Cross-Space | AppleScript (Apple Events) |
| Badge Reading | `lsappinfo` CLI (reliable on macOS 14+) |
| Hotkeys | Carbon Event API (RegisterEventHotKey) |
| Claude Integration | Unix socket IPC + Python hook + `NARC_SESSION_ID` env var |
| Build System | Swift Package Manager |
| Min. Deployment | macOS 14 Sonoma |

### Key Design Decisions

- **Native macOS Dock app** — `setActivationPolicy(.regular)` so it shows in the Dock and Cmd+Tab; closing all windows keeps the floating widget + menu bar item alive
- **Not sandboxed** — full Accessibility API + PTY spawning + AppleScript privileges
- **AppleScript for cross-Space** — `set index + activate` for zero-animation Space switching (CGS private APIs unreliable on macOS 15)
- **PTY persistence** — `TerminalSessionManager` lives on `AppDelegate`, not `@StateObject` inside the Dashboard, so closing the window doesn't tear down child processes
- **Hit-tested transparent canvas** — the floating widget panel is 128×128 to give the SwiftUI drop shadow room (radius 32 + offset 12), but `FirstMouseView.hitTest` restricts AppKit click delivery to the central 48pt circle so the surrounding shadow area is click-through
- **AXEnhancedUserInterface handling** — disable before resize, Size→Position→Size order (Rectangle/Magnet pattern)
- **Stable title matching** — strips dynamic content (spinners ⠂⠈⠐, dimensions 80×24) from terminal titles, matches by directory prefix only
- **Stable self-signed identity** — `build-app.sh` signs with `NARC Dev` so the cdhash stays constant across rebuilds and Accessibility permission survives

## Changelog

### v1.3 (Current)

- ✅ **NARC Workspace** — embedded multi-terminal dashboard powered by SwiftTerm; spawn shells / `claude` sessions inside NARC, switch between them with one click
- ✅ **Tab persistence (Option A)** — closing the Dashboard window keeps PTYs alive; reopen and find your tabs intact
- ✅ **Live Claude badges per tab** — hook events route back to the originating tab via `NARC_SESSION_ID`; tabs flash red on permission requests
- ✅ **Custom tab titles + auto-tracked cwd** — double-click to rename, OSC 7 keeps the cwd label live
- ✅ **Spec-D floating widget** — round `.regularMaterial` halo, bloom, slow sonar ripple, breathing "NARC" wordmark, soft dual-layer drop shadow
- ✅ **Panel "Claude" section** — pending approvals + Stop/Error notifications now have a real UI exit; no more stuck red dots
- ✅ **Right-click widget → Dashboard** — the workspace lives one gesture away from the floating circle
- ✅ **128×128 transparent canvas with central hit-test** — fixes the long-standing rectangular-halo-around-the-circle bug
- ✅ **Stable self-signed builds** — Accessibility permission no longer evaporates between rebuilds

### v1.2

- ✅ Claude Code Integration — real-time session monitoring with toast notifications and precise terminal jump
- ✅ Cross-Space Window Activation — AppleScript-based Space switching for pinned windows (replaces broken CGS API)
- ✅ Magnet-equivalent Window Management — zero-delay snapping with AXEnhancedUserInterface handling
- ✅ State Machine Cross-Screen — press same hotkey within 5s to move window to adjacent display
- ✅ TTY-based Terminal Targeting — click toast to jump to exact terminal tab, not random window
- ✅ ScrollView Keyboard Following — panel auto-scrolls when navigating past visible area
- ✅ Shortcuts Reference Tab — Window Management tab now shows hotkey reference instead of redundant buttons

### v1.1

- ✅ Window Pinning — pin any window via `⌃⌥P` for quick access from the NARC panel
- ✅ Persistence modes — temporary (📌) or persistent (🔒) pinned windows
- ✅ Keyboard navigation — `⌃⌥N` to toggle panel, `↑↓↩` to navigate and activate, `1`–`0` for quick index access
- ✅ Two-zone activation strategy — Monitoring windows summon to current screen; Pinned windows activate in place
- ✅ Pinned window alive polling — real-time status and title tracking for pinned windows

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
- Inside the embedded terminal, the full Claude Code TUI works but a few kitty-keyboard-protocol-only key combos may behave differently than in a native terminal
- No auto-update mechanism yet (planned: Sparkle framework)

## Roadmap

| Version | Focus |
|---------|-------|
| **v1.3** ← current | NARC Workspace (embedded multi-terminal), spec-D floating widget, panel Claude exit |
| v1.4 | Tab font size (`⌘+` / `⌘-`), `⌘1`–`⌘9` tab switching, drag-reorder tabs, scrollback search |
| v1.5 | Developer ID signing + Notarization + GitHub Release CI |
| v2.0 | IDE task monitoring (VS Code extension bridge) |
| v2.1 | Message content preview ("who sent what") |
| v3.0 | Plugin/extension system for third-party integrations |

## License

MIT

## Contributing

This project is in active development. Issues and PRs are welcome.

---

*Built with Swift, SwiftUI, SwiftTerm, and a lot of ⌃⌥ key combos.*
