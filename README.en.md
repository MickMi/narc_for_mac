[中文](README.md) | [**English**](README.en.md)

# NARC for Mac

> A local personal assistant that lives in the menu bar and can always be summoned back into view.

NARC has two durable entry points: the menu bar provides a stable home, while a floating `N` anchors attention on the current display. Capture a thought, notice app-level unread activity, or recover scattered windows without leaving the work in front of you.

> **Status: v2 development preview.** Source installation, local data, and summon-placement logic have been verified locally or through automated tests. Menu-bar clicks, global shortcuts, real multi-display summon, full-screen Spaces, and first-time permission flows still need hands-on validation. This is not a stable-release promise.

## Start with one command

NARC requires macOS 14 or later, Git, and Xcode Command Line Tools. The first build needs internet access.

Paste this line into Terminal:

```bash
git clone https://github.com/MickMi/narc_for_mac.git && cd narc_for_mac && bash scripts/install.sh
```

The script builds NARC locally from source, places it at `~/Applications/NARC.app`, and launches it. It does not need `sudo`, and Terminal does not need to remain open afterward.

If Xcode Command Line Tools are missing, run:

```bash
xcode-select --install
```

NARC is source-only. This is the only supported setup path for regular users. The project does not provide a DMG, PKG, prebuilt app ZIP, or binary GitHub Release, and users do not need a developer certificate, notarization, or a separate signing step.

## Where NARC lives

NARC is a menu-bar app. It does not show a Dock icon by default.

| Entry point | Action |
|---|---|
| Left-click the menu bar `N` | Summon the floating `N` and open its adjacent lightweight panel |
| Right-click the menu bar `N` | Open the User Guide, Preferences, About, or Quit menu |
| Left-click the floating `N` | Open or close the lightweight panel |
| Right-click the floating `N` | Open Assistant, the User Guide, or Preferences |
| Press `⌃⌥N` | Summon the floating `N` to the display under the pointer and keep the panel open |

The floating `N` can be dragged. Its size and position can also be adjusted or reset in Preferences. Summoning preserves a valid position on the same display and uses a safe visible position when moving to another display.

## Three core workflows

### 1. Capture first, organize later

Press `⌃⌥Q`, or use the Inbox in the lightweight panel:

1. Enter the thought without first choosing Todo or Note.
2. Press Return to save it to the local Inbox. Blank content is not submitted.
3. The panel keeps the three most recent Inbox items visible.
4. Later, explicitly convert an item to Todo or Note. The original Inbox item is removed after a successful conversion.

Summoning capture again does not discard an unsubmitted draft. If saving fails, the content remains in place with a visible error.

The full Assistant opens in a separate window: Todo supports open/completed state, while Notes supports search and deletion.

### 2. See app-level unread activity

NARC aggregates Dock badges that enabled apps expose to macOS. WeChat, WeCom, and Lark are monitored by default. The aggregate appears in the menu bar and on the floating `N`; values above 99 are shown as `99+`.

This number is app-level only:

- NARC does not read message content.
- NARC cannot identify which conversation produced an unread item.
- Multiple system instances of the same app are reconciled using the largest trustworthy value, never added together.
- If an app does not expose a trustworthy badge, NARC appends `?` to the last trusted value (for example, `14?`). With no trusted prior value it shows `?`, never a fabricated new zero.

### 3. Recover and arrange windows

These actions require macOS Accessibility permission:

| Shortcut | Action |
|---|---|
| `⌃⌥P` | Pin the current window so it can be recovered from the panel later |
| `⌃⌥←` / `⌃⌥→` | Left half / right half |
| `⌃⌥↑` / `⌃⌥↓` | Top half / bottom half |
| `⌃⌥U` / `⌃⌥I` / `⌃⌥J` / `⌃⌥K` | Four corners |
| `⌃⌥↩` / `⌃⌥C` | Full screen / centered |

Repeating the same directional shortcut within five seconds attempts to move the window to an adjacent display. Multi-display and full-screen Space behavior remains part of preview validation.

## Current maturity

| Capability | Status | Boundary |
|---|---|---|
| One-command setup from GitHub source | Verified | Builds locally, installs under the user account, and creates no installer package |
| Menu bar + floating `N` | Development preview | No Dock icon and floating-widget clicks have been checked locally; placement has automated coverage, while menu-bar, global-shortcut, and real multi-display QA remain |
| Inbox capture | Development preview | Persistence, migration, draft retention, and conversion have automated coverage; complete interaction QA continues |
| Todo / Notes / Assistant | Development preview | Core management paths are connected and still gaining hands-on interaction coverage |
| App-level unread aggregation | Depends on the source app | Reads only the badge macOS can see; not every app provides a reliable value at all times |
| Window pinning and arrangement | Available with permission | Multi-display, cross-Space, and some window types remain subject to macOS behavior |

See [Features](docs/FEATURES.md) for detailed maturity and [Version Plan](docs/VERSIONS.md) for release scope.

## First use and permissions

The first time the Inbox opens, a short inline guide introduces capture. The core guide is completed only after the first successful record; choosing “Later” applies only to the current run.

Inbox, Todo, Notes, and app-level badges do not require Accessibility permission. NARC does not request Accessibility or notification access on launch. Window tools explain their need first; notification access is requested only when a real notification is first delivered.

For window tools, enable NARC under:

**System Settings → Privacy & Security → Accessibility → NARC**

## Data and privacy

- Inbox, Todo, and Notes are stored locally by default.
- The data file is `~/Library/Application Support/NARC/assistant-v1.json`.
- Existing Todo and Note data is preserved when the file migrates to the current format.
- This version does not call an external model API and has no cloud sync or team collaboration.
- NARC does not read WeChat or WeCom message content and does not use screenshot OCR, private databases, process injection, or private hooks.

Removing the app does not automatically erase personal records.

## Current boundaries

- No Dock icon, Workspace entry point, or embedded terminal entry point.
- No conversational AI, automatic classification, or cross-module AI execution.
- No Apple Notes, Reminders, Calendar, GitHub, or other external connectors.
- No per-conversation WeChat/WeCom unread state or message content.
- No third-party dynamic plugins, script marketplace, or plugin permission system.
- No automatic updater, DMG, PKG, prebuilt app, or certificate/notarization distribution chain.

These boundaries keep capture, awareness, and recovery focused on a reliable, low-interruption local loop.

## Update

Choose **Quit NARC**, then run this from the repository directory:

```bash
git pull && bash scripts/install.sh
```

The installer does not force-quit a running NARC instance and does not delete personal records.

## Uninstall

1. Choose **Quit NARC**.
2. Delete `~/Applications/NARC.app`.

Personal records remain. Only if you are sure you no longer need them, delete:

`~/Library/Application Support/NARC`

## Troubleshooting

### NARC is not visible

NARC does not appear in the Dock by default. Look for the `N` in the menu bar, or run:

```bash
open ~/Applications/NARC.app
```

If NARC is already running, press `⌃⌥N` to summon the floating `N`.

### A shortcut does nothing

- `⌃⌥N` and `⌃⌥Q` register when NARC starts and do not require Accessibility permission.
- Window pinning and arrangement explain and request Accessibility permission on first use.
- If another app owns the same shortcut, quit the conflicting app and restart NARC.

### The WeCom or WeChat number does not match

NARC reads the Dock badge that macOS LaunchServices exposes. The value may lag while an app is signed out, does not expose a badge, has multiple instances, or has not refreshed its state. Unknown state appears as `?`, or as a last trusted value such as `14?`.

### Update says NARC is running

Choose **Quit NARC**, then run:

```bash
bash scripts/install.sh
```

## Development and verification

```bash
# Build a runnable Debug app
bash scripts/build-app.sh debug
open build/NARC.app

# Full test suite
swift test

# Guard against installers, certificate chains, and automatic updaters
bash scripts/verify-source-only-distribution.sh

# Build the Swift package only
swift build
```

Stack: Swift 5.9 Package, SwiftUI + AppKit, and macOS 14+. See [Project Profile](docs/PROJECT.md) for product goals and boundaries.
