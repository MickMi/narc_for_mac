[**English**](README.en.md) | [中文](README.md)

# NARC for Mac

NARC is a local desktop personal assistant. Its floating `N` combines app-level unread badges, fast Todo/Note capture, and shortcuts for pinning and arranging windows.

NARC is obtained from GitHub source. One command clones the repository, prepares the app locally, places it under your user account, and launches it.

## Install

Requires macOS 14 or later. Copy this one line into Terminal:

```bash
git clone https://github.com/MickMi/narc_for_mac.git && cd narc_for_mac && bash scripts/install.sh
```

The first build needs an internet connection and may take a few minutes. The script checks the environment, prepares NARC locally, and places it at `~/Applications/NARC.app`. Terminal does not need to remain open afterward.

This is the only supported end-user setup path. NARC does not provide a DMG, PKG, prebuilt app ZIP, or GitHub Release installer, and it does not ask users to prepare a developer certificate, notarize the app, or run a separate signing step.

If Xcode Command Line Tools are missing, run:

```bash
xcode-select --install
```

Then run the install command again.

## Open NARC

Remember only two actions:

| Action | Result |
|---|---|
| Click the floating `N` | See unread apps, monitoring status, and pinned windows |
| Press `⌃⌥Q` | Capture a Todo or Note from anywhere |

Secondary entry points:

- Right-click the floating `N`: open Assistant, the User Guide, or Preferences.
- `⌃⌥N`: toggle the NARC panel on the display under the pointer.
- To reopen later: launch `~/Applications/NARC.app`, or run `open ~/Applications/NARC.app`.

The first launch shows a short guide. It will not appear on every launch after you close it, and you can reopen it at any time from the floating `N` context menu.

## What NARC Does

### Assistant

- **Quick Capture**: explicitly choose Todo or Note, then save it quickly.
- **Todo**: view open and completed items and change their state.
- **Notes**: save, search, and delete local notes.
- Data stays at `~/Library/Application Support/NARC/assistant-v1.json`; it is not uploaded to a cloud service.

### Unread awareness

- Aggregates macOS Dock badges from WeChat, WeCom, and Lark.
- The red number on the floating `N` is the total unread count from enabled apps.
- NARC currently reads only app-level unread counts. It **does not read message content or monitor an individual WeChat conversation**.

### Window tools

- `⌃⌥P`: pin the current window so it can be found later from the NARC panel.
- `⌃⌥←` / `⌃⌥→` / `⌃⌥↑` / `⌃⌥↓`: left, right, top, and bottom halves.
- `⌃⌥U` / `⌃⌥I` / `⌃⌥J` / `⌃⌥K`: four corners.
- `⌃⌥↩` / `⌃⌥C`: full screen / centered.
- Repeat the same direction shortcut within five seconds to move the window to an adjacent display.

## Permissions

Assistant, Todo, Notes, Quick Capture, and Dock badge aggregation do not require Accessibility permission.

Window arrangement, pinning, and reactivating another app's window require permission under **System Settings → Privacy & Security → Accessibility**.

After a rebuild, macOS may ask you to enable NARC again for these optional window tools. The Assistant and unread badge continue to work without that permission.

## Update

Choose **Quit NARC** from the NARC menu, then run:

```bash
cd narc_for_mac
git pull && bash scripts/install.sh
```

The installer will not force-quit a running NARC instance.

## Uninstall

1. Choose **Quit NARC** from the NARC menu.
2. Delete `~/Applications/NARC.app`.

Removing the app does not delete Todo or Note data. To erase that data too, manually delete `~/Library/Application Support/NARC`.

## Troubleshooting

### The floating N is missing

```bash
open ~/Applications/NARC.app
```

If NARC is already running, select the NARC menu bar icon and choose **Show NARC**.

### `⌃⌥Q` or a window shortcut does nothing

- `⌃⌥Q` and `⌃⌥N` register when NARC starts.
- Window arrangement and pinning also require Accessibility permission.
- If another app owns the same shortcut, quit the conflicting app and restart NARC.

### The WeCom or WeChat number does not match

NARC reads the badge state that macOS LaunchServices exposes to the Dock. The value can lag when an app does not expose a badge, is still signing in, or has not refreshed multi-instance state.

## Current Boundaries

- NARC does not read WeChat/WeCom message content and does not support per-conversation monitoring.
- There is no cloud sync, team collaboration, or automatic update.
- Distribution is source-only through the one-line GitHub command. There is no DMG, PKG, prebuilt app ZIP, GitHub Release installer, developer-certificate setup, or notarization workflow.
- Updating requires rerunning the installer from the repository directory.
- Workspace and the embedded terminal are not current user entry points; this version focuses on Assistant, unread awareness, and window tools.

## Development and Verification

```bash
# Debug app
bash scripts/build-app.sh debug
open build/NARC.app

# Full test suite
swift test

# Source-only distribution guard
bash scripts/verify-source-only-distribution.sh

# Command-line build only
swift build
```

Stack: Swift 5.9 package, SwiftUI + AppKit, macOS 14+, and SwiftTerm. See [docs/PROJECT.md](docs/PROJECT.md) and [docs/VERSIONS.md](docs/VERSIONS.md) for detailed product boundaries and version planning.

## License

MIT
