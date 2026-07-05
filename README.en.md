**English** | [中文](README.md)

# NARC for Mac

**Notification & Application Resource Center**

IM notifications, Claude Code sessions, and window operations — folded into one desktop floating widget. NARC is the attention gatekeeper for macOS developers. It supplements the terminal, not replaces it.

> Repository: `narc_for_mac`. Product: **NARC**.

## Why It Exists

Working with a single terminal, single IDE, and single display — you won't feel the friction. Problems surface when your daily workflow looks like this:

- WeChat badge lights up → ⌘Tab over → it's a group announcement → switch back → forgot what you were doing
- Claude Code sits in some buried iTerm tab waiting for permission approval → you don't know → check 3 minutes later → it already timed out
- 4 projects, 6 terminal windows across 3 Spaces → swiping the trackpad every time to find the right one → dozens of repetitions per day
- Pinned a reference document in Space 2 → ⌘Tab through 20 apps but can't find it → open it again from scratch
- Drag a window to the left edge, another to the right, a third to center — repeat dozens of times a day

What breaks you isn't one big problem. It's the accumulation of micro-operations. **Attention gets fragmented, context gets washed away, operations get wasted on repeat.**

NARC solves this fragmentation — collapsing three recurring costs into one 48pt circle.

## Who It's For

NARC is for you if:

- You run Claude Code in the terminal daily and get frequently interrupted by permission prompts
- You use WeChat, WeCom, and Lark simultaneously and hate checking each one for unread messages
- You work across multiple monitors and Spaces, constantly switching between windows
- You prefer keyboard-driven operations and want hotkeys instead of dragging
- You want all Claude Code session states visible in one window — no more "which project is in tab 3?"

**If you only occasionally use AI completions in an IDE, don't need IM notification management, or work on a single monitor and single Space — NARC is probably too heavy for you.** It's an attention-management tool built for heavy terminal + AI workflow users.

## Start in 5 Minutes

### 1. Build

```bash
git clone https://github.com/MickMi/narc_for_mac.git
cd narc_for_mac
./scripts/build-app.sh
open build/NARC.app
```

The build script signs with a stable `NARC Dev` identity. Accessibility permission survives rebuilds.

### 2. Install Claude Code Hook (optional but recommended)

```bash
cp scripts/narc-hook.py ~/.claude/hooks/narc-hook.py
chmod +x ~/.claude/hooks/narc-hook.py
```

Then add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PermissionRequest": [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "Stop":              [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "SessionStart":      [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "SessionEnd":        [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }]
  }
}
```

### 3. First Launch

NARC will prompt you to grant **Accessibility permission** (System Settings → Privacy & Security → Accessibility). Restart NARC after granting.

### 4. Verify

After the three steps above, confirm these behaviors:

- A floating circle appears at the bottom-right of your screen, with an aggregated badge count
- Left-click → notification panel slides out, showing WeChat/WeCom/Lark running status
- Right-click → Dashboard opens. Click "+" to add a new terminal → type `claude` → an interactive terminal appears in a new tab
- `⌃⌥N` toggles the panel, `⌃⌥→` snaps the current window to the right half, `⌃⌥P` pins the current window

**If the floating circle doesn't appear**: verify Accessibility permission is granted and restart NARC.

## What Success Looks Like

The floating circle (bottom-right, 48pt, always on top):

- **Red badge** — aggregated count of IM messages + pending Claude approvals
- **Left-click** → notification panel (IM status, Claude approvals, pinned windows)
- **Right-click** → workspace Dashboard (multi-terminal tabs + live Claude state)

Inside the Dashboard:

- Each tab shows a **live Claude state badge**: `⏳ Thinking` / `⚠️ Approval` / `💬 Waiting` / `■ Ended`
- When Claude waits for permission, the corresponding tab **flashes red**
- Closing the Dashboard window keeps terminal sessions **running**; reopen picks up from where you left off

| Before | Now |
|--------|-----|
| ⌘Tab through 3 IM apps to check badges | Glance at the floating circle |
| Hunt through iTerm tabs for the Claude session awaiting approval | See a red flashing tab → click it |
| Drag windows to arrange | `⌃⌥→` half-screen, `⌃⌥C` center |
| Swipe trackpad between Spaces to find pinned windows | `⌃⌥P` to pin → panel click to jump |

## Core Capabilities

| Capability | Supported | Notes |
|-----------|-----------|-------|
| Unified IM notification source (WeChat/WeCom/Lark) | ✅ | One aggregated badge replaces three scattered notification sources |
| Real-time Claude Code session monitoring | ✅ | 6 states via Unix socket + Python hook |
| Embedded multi-terminal Dashboard | ✅ | SwiftTerm-powered, closing the window doesn't kill processes |
| Keyboard-driven window snapping (10 presets) | ✅ | Single setFrame call, zero delay |
| Cross-Space window pinning & activation | ✅ | AppleScript-driven, no animation flicker |
| Force Claude Code to respond 100% on time | ❌ | It monitors and notifies you; it doesn't control execution |
| Cross-Space activation 100% accurate | ❌ | AppleScript depends on window title matching; nearly identical titles may cause ambiguity |
| WeCom badge 100% accurate | ❌ | WeCom uses custom Dock rendering; `lsappinfo` can't guarantee detection |
| Message content preview ("who sent what") | ❌ | Planned for v2.1; currently badge count only |
| Auto-update | ❌ | Planned for v1.5 (Sparkle framework) |

**In short: NARC collapses passive notification awareness, active window management, and real-time Claude session oversight into one floating widget. It's not a universal panel — it targets the three attention taxes that weigh on heavy terminal users.**

## What It Writes

| Action | Write Location | Purpose | Rollback |
|--------|---------------|---------|----------|
| `./scripts/build-app.sh` | `build/NARC.app` | Build artifact | `rm -rf build/` |
| `cp scripts/narc-hook.py ...` | `~/.claude/hooks/narc-hook.py` | Claude Code event interception | `rm ~/.claude/hooks/narc-hook.py` |
| Edit `settings.json` | `~/.claude/settings.json` | Hook registration (manual) | Remove hook config block |
| Normal usage | `~/Library/Preferences/com.narc.NARC.plist` | App preferences & pinned windows | `defaults delete com.narc.NARC` |
| `cp -R build/NARC.app /Applications/` | `/Applications/NARC.app` | Install to Applications (optional) | Drag to Trash |

## How It Works

NARC has four layers:

| Layer | Responsibility | Key Files / Tech |
|-------|---------------|-----------------|
| Perception | Dock badge polling, Claude event listening, hotkey registration | `AppMonitorService` (lsappinfo), `ClaudeSessionService` (Unix Socket), `HotkeyService` (Carbon Event) |
| State | Session lifecycle, window state machine, pin persistence | `TerminalSessionManager`, `WindowLayoutState` (5s TTL), `PinnedWindowService` (AppleScript) |
| View | Floating widget, notification panel, Dashboard, toast banners | SwiftUI + AppKit (NSPanel), SwiftTerm embedded terminal |
| Integration | Claude Code hook event routing, `NARC_SESSION_ID` injection | Python hook → Unix Socket → precise tab matching |

Recommended interaction topology:

```text
macOS Dock Badge (lsappinfo)
        │
        ▼
  NARC Floating Circle ──left-click──▶ Notification Panel (IM + Claude + Pinned)
        │
     right-click
        │
        ▼
  Workspace Dashboard ──▶ Tab 1: Claude Code (project A)
                      ──▶ Tab 2: Claude Code (project B)
                      ──▶ Tab 3: zsh (server logs)
                      ──▶ Tab 4: claude (debug session)
        │
  NARC_SESSION_ID ──▶ Hook events route back to originating tab
```

## Keyboard Shortcuts

Daily high-frequency — just these:

| Shortcut | Effect |
|----------|--------|
| `⌃⌥N` | Toggle NARC panel |
| `⌃⌥→` | Current window → right half |
| `⌃⌥←` | Current window → left half |
| `⌃⌥P` | Pin current window |
| `Esc` | Close panel |

Full list:

```text
⌃⌥←  ⌃⌥→  ⌃⌥↑  ⌃⌥↓    Halves (left/right/top/bottom)
⌃⌥U  ⌃⌥I  ⌃⌥J  ⌃⌥K    Corners (top-left / top-right / bottom-left / bottom-right)
⌃⌥↩  ⌃⌥C               Full Screen / Center
```

**Cross-screen tip**: press the same direction key twice within 5 seconds → window jumps to the adjacent display.

## Design Principles

- **Float, don't block**: 48pt circle, always on top, freely draggable. The 128×128 transparent canvas keeps the shadow uncropped, but only the central 48pt registers clicks.
- **Close ≠ kill**: closing the Dashboard window keeps PTY child processes alive. Inspired by tmux detach — the window is just a view, the session is the asset.
- **Visible state, not interruption**: badges and status indicators let you perceive state without context-switching. Only Claude awaiting approval triggers an active red flash.
- **Keyboard-first**: window snapping and pinning are two-keystroke operations. No precise dragging, no Space-number memorization.
- **Stable identity**: builds are self-signed with a fixed `NARC Dev` identity. The cdhash stays constant across rebuilds, so Accessibility permission survives.
- **Not a universal panel**: NARC doesn't read message content (until v2.1), doesn't replace iTerm, doesn't manage the Dock. It focuses on three attention taxes and leaves the rest to specialized tools.

## Current Limitations

- Prompt constraints can't force Claude Code to respond 100% on time; NARC monitors and notifies, it doesn't control execution
- Cross-Space window activation depends on AppleScript title matching; nearly identical titles may result in incorrect targeting
- WeCom badge detection relies on `lsappinfo` CLI; WeCom's custom Dock rendering may cause missed detections
- Claude Code hook requires manual installation (copy script + edit settings.json); not yet automated
- Inside the embedded terminal, a few kitty-keyboard-protocol-specific key combos may behave differently than in a native terminal
- No auto-update mechanism yet (Sparkle planned for v1.5)
- Window snapping doesn't support custom layout ratios (e.g., 1/3 screen); only fixed presets currently

## Roadmap

| Version | Focus |
|---------|-------|
| **v1.3** ← current | Workspace Dashboard, spec-D floating widget, panel Claude exit |
| v1.4 | Tab font size `⌘+`/`⌘-`, `⌘1`–`⌘9` tab switching, drag-reorder tabs, scrollback search |
| v1.5 | Developer ID signing + Notarization + GitHub Release CI |
| v2.0 | IDE task monitoring (VS Code extension bridge) |
| v2.1 | Message content preview |
| v3.0 | Plugin system for third-party integrations |

## Development & Verification

```bash
# Full build
./scripts/build-app.sh

# Development mode
swift run -c release NARC

# Check Gatekeeper acceptance
spctl --assess --verbose build/NARC.app

# Test Accessibility permission flow
tccutil reset Accessibility com.narc.NARC   # reset then restart NARC to test auth flow

# Test hook communication
echo '{"event":"test"}' | nc -U /tmp/narc-claude.sock
```

Language: Swift 5.9. UI: SwiftUI + AppKit. Embedded terminal: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Minimum deployment: macOS 14 Sonoma.

## License

MIT

---

*Built with Swift, SwiftUI, SwiftTerm, and a lot of ⌃⌥ key combos.*
