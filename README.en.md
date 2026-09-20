[中文](README.md) | [**English**](README.en.md)

# NARC for Mac

**Attention Is All You Need. Save it for what matters.**

NARC brings your attention back to what matters when you juggle multiple tasks. Todos, AI reply reminders, and frequently used windows come together around a floating desktop `N`, with a permanent menu-bar entry and no Dock icon.

For Codex reply reminders, open **Preferences → AI Replies** and follow the connection guidance. Replies can trigger a reminder you click to return to the task; individual conversations can be muted. This requires Python 3.11 or newer and currently supports Codex tasks, not ordinary GPT chats or chatting with AI inside NARC.

> **Status: v2 development preview.** Source installation, local data, and summon-placement logic have been verified locally or through automated tests. The refocused Inbox, proactive floating Todo reminder, and keyboard-first pinned-window switcher are now experience previews. Menu-bar clicks, real multi-display summon, full-screen Spaces, first-time permission flows, exact-window recall, and selected-text Todo compatibility in specific app surfaces still need hands-on validation. This is not a stable-release promise.

## Start with one command

NARC requires macOS 14 or later, Git, and Xcode Command Line Tools. The first build needs internet access.

Paste this line into Terminal:

```bash
git clone https://github.com/MickMi/narc_for_mac.git && cd narc_for_mac && bash scripts/install.sh
```

The script builds NARC locally from source, places it at `~/Applications/NARC.app`, and launches it. It does not need `sudo`, and Terminal does not need to remain open afterward. If the target already contains a strictly valid NARC whose private key is still available, the installer inherits that local signer (including legacy `NARC Dev`). Only a clean new user gets a new `NARC Local Code Signing Identity v1`; later updates keep reusing the locked identity.

If Xcode Command Line Tools are missing, run:

```bash
xcode-select --install
```

NARC is source-only. This is the only supported setup path for regular users. The project does not provide a DMG, PKG, prebuilt app ZIP, or binary GitHub Release, and users do not need to prepare a developer certificate, notarize the app, or run a separate signing step. The local identity is not a Developer ID or distribution certificate and never leaves the current Mac.

## Where NARC lives

NARC is a menu-bar app. It does not show a Dock icon by default.

| Entry point | Action |
|---|---|
| Left-click the menu bar `N` | Summon the floating `N` and open its adjacent lightweight panel |
| Right-click the menu bar `N` | Open the User Guide, Preferences, About, or Quit menu |
| Left-click the floating `N` | Open or close the lightweight panel |
| Right-click the floating `N` | Open Assistant, the User Guide, or Preferences |
| Default `⌃⌥N` (editable) | Summon the floating `N` to the display under the pointer and keep the panel open |

The floating `N` can be dragged. Its size and position can also be adjusted or reset in Preferences. Summoning preserves a valid position on the same display and uses a safe visible position when moving to another display.

## Three core workflows

### 1. Capture first, organize later

Use your Quick Capture shortcut (default `⌃⌥Q`, editable), or the Inbox in the lightweight panel:

1. Enter the thought without first choosing Todo or Note.
2. Press Return to save it to the local Inbox. Blank content is not submitted.
3. If it is already clearly a task, press `⌘Return` or click the Todo button to create a Todo directly.
4. Unsorted Inbox items are collapsed by default into a one-line count. Expand them only when you want to organize a record into Todo or Note; the original Inbox item is removed after a successful conversion.

Summoning capture again does not discard an unsubmitted draft. If saving fails, the content remains in place with a visible error.

This entire path works without AI, an account, or a network connection. When actionable Todos exist, a separate blue count appears at the lower-left of the floating `N`. It never reveals task text or changes the app-unread number at the upper-right. In the panel, “Next action” moves above capture and becomes the primary visual when a Todo is available; when none is available, capture naturally returns to the top. The card can complete the task, defer it for one hour, or show the next item. Deferral is stored locally and the task returns when it expires; “Next” changes only the current view and does not rewrite task order.

Configure daily review times under **Preferences → Reminders (提醒)**. Defaults are 11:00 and 14:30; add, edit, remove, or disable them. A separate nonactivating card beside the widget highlights the top task, previews up to three others, and shows the remaining count. It does not open the main panel, steal keyboard focus, or use system notifications or sound.

Under **Assistant → Todo → Plan (安排)**, optionally choose one explicit next task, high/normal/low priority, and a deadline. Explicit next comes first, then priority, then earlier deadlines (undated tasks last), with newer creation time as the tie-breaker. Completed or deferred tasks are excluded. Quick capture requires none of these fields.

The review offers Complete, 1 Hour, View All, and Dismiss. Snoozing the review postpones the whole review without changing task deadlines; the main panel's existing deferral still applies to one task. NARC must be running. Times follow the local time zone; empty lists stay quiet and each slot is consumed once. Typing, NARC management windows, and screen sleep defer presentation; only the latest slot within ten minutes can catch up. Startup warm-up and card visibility are both 30 seconds. Settings include a read-only preview; long-running behavior still awaits user validation.

The full Assistant opens in a separate window. Todo supports completion, shows when a task is deferred, and lets you restore it to “Now”; Notes supports search and deletion.

If the content already exists in another app, select it and press the default `⌃⌥T` shortcut to create a local Todo. Choose supported modifiers and a key under **Preferences → Shortcuts**; existing preset choices migrate without being reset. If registration fails, NARC keeps the previously active binding.

- When the shortcut fires, NARC locks the frontmost app and focused control, then immediately starts one standard Accessibility selection read. It does not continuously monitor the screen or keyboard input.
- A selection of at most 240 characters and three non-empty lines is saved directly; other normal selections require confirmation first. A successful read becomes one snapshot, which confirmation uses without rereading after focus changes.
- One capture is limited to 65,536 UTF-16 text units. Anything larger asks you to narrow the selection, is not saved or shown in feedback, and creates no Todo; the range fallback stops before fetching its body.
- The success notice does not reveal the selected text and briefly offers Undo. Undo deletes the exact UUID created by that capture, never another Todo with the same title.
- An empty selection, protected input, or a surface without a standard selection creates nothing. NARC does not fall back to the clipboard, simulated `⌘C`, OCR, or AI.

Compatibility must be checked per app surface. Web content and text fields, text-layer and scanned PDFs, and WeCom message and compose areas cannot share one blanket result. Every row in the current [compatibility matrix](docs/research/selected-text-todo-compatibility.md) still awaits hands-on validation in the real app.

### 2. See app-level unread activity

NARC aggregates Dock badges that enabled apps expose to macOS. WeChat, WeCom, and Lark are monitored by default. The aggregate appears in the menu bar and on the floating `N`; values above 99 are shown as `99+`.

This number is app-level only:

- The app-level unread path does not read message content.
- NARC cannot identify which conversation produced an unread item.
- Multiple system instances of the same app are reconciled using the largest trustworthy value, never added together.
- If an app does not expose a trustworthy badge, NARC appends `?` to the last trusted value (for example, `14?`). With no trusted prior value it shows `?`, never a fabricated new zero.

### 3. Recover and arrange windows

These actions require macOS Accessibility permission:

| Shortcut | Action |
|---|---|
| Default `⌃⌥P` | Open the pinned-window switcher on the display under the pointer |
| Default `⌃⌥⇧P` | Mark or unmark the currently focused exact window |
| Default `⌃⌥←` / `⌃⌥→` | Left half / right half |
| Default `⌃⌥↑` / `⌃⌥↓` | Top half / bottom half |
| Default `⌃⌥U` / `⌃⌥I` / `⌃⌥J` / `⌃⌥K` | Four corners |
| Default `⌃⌥↩` / `⌃⌥C` | Full screen / centered |

**All 15 global actions are configurable** under **Preferences → Shortcuts**. Select at least two modifiers and a supported primary key, then Apply. Changes take effect immediately, survive restarts, and can be reset individually. NARC-internal conflicts or a registration failure keep the previous binding intact; other apps' shortcuts are not always detectable.

Window layouts can also be configured directly in **Floating panel → Windows**. Each card has an enable checkbox and an editable shortcut. Disabling releases its binding but keeps the card available for editing; a conflict when re-enabling leaves it disabled with an explanation. Editing or checking a card does not move a window: use the corresponding shortcut to arrange it. Standard in-window Return, Esc, and list navigation remain unchanged.

The switcher selects its first row immediately; no click is required. Press `1`–`9` to recall one of the first nine marked windows, use the arrow keys and Return to choose, or press Esc to close. NARC keeps at most ten marked windows, so the tenth remains available through the arrow keys or mouse rather than a new global number shortcut. Number slots contain only marked windows and never shift when the monitored-app list changes.

NARC first tries to recover the marked window. A window already on a visible desktop can move to the display captured when the switcher opens. A window in another Space or native full screen is revealed in place when macOS permits it. If exact recovery is unavailable, NARC attempts to open the owning app and clearly reports the app-level fallback; re-marking is not a prerequisite for opening the app. Space switching depends on the macOS setting “When switching to an application, switch to a Space with open windows for the application” and the target app. This remains a development preview.

Once a window is stably placed in a directional layout, pressing the same direction again attempts to move it to an adjacent display; this decision no longer depends on a fixed five-second window. Multi-display and full-screen Space behavior remains part of preview validation.

## Current maturity

| Capability | Status | Boundary |
|---|---|---|
| One-command setup from GitHub source | Verified | Builds locally, installs under the user account, prepares a local identity once, and creates no installer package |
| Menu bar + floating `N` | Development preview | No Dock icon and floating-widget clicks have been checked locally; placement has automated coverage, while menu-bar, global-shortcut, and real multi-display QA remain |
| Inbox capture | Development preview | “Next action” leads when a Todo is available, capture leads when none is available, and unsorted records are collapsed by default; the latest hierarchy still needs experience confirmation |
| Todo / Notes / Assistant | Development preview | Direct Todo capture, the blue numeric cue, single-task card, local deferral, and a separate nonactivating reminder are in the experience preview; an isolated hands-on check covered the first background click without focus theft, while the default cadence still needs experience confirmation |
| Selected text to Todo | Development preview | Defaults to `⌃⌥T`, with configurable modifiers and key; locks the trigger-time control for one standard AX read. Confirmation, Undo, and configuration migration have automated coverage; the target-app matrix still needs hands-on validation |
| App-level unread aggregation | Depends on the source app | Reads only the badge macOS can see; not every app provides a reliable value at all times |
| Pinned-window keyboard recall | Development preview | Defaults to `⌃⌥P` for recall and `⌃⌥⇧P` for marking; both are editable in Preferences. Full multi-display, same-app multi-window, and cross-Space validation remains |
| Window arrangement | Development preview | Enable or edit each shortcut directly from its Windows card; arranging windows requires permission and remains subject to macOS multi-display, Space, and window-type limitations |

See [Features](docs/FEATURES.md) for detailed maturity and [Version Plan](docs/VERSIONS.md) for release scope.

## First use and permissions

The first time the Inbox opens, a short inline guide introduces capture. The core guide is completed only after the first successful record; choosing “Later” applies only to the current run.

Manual Inbox, Todo, and Notes actions and app-level badges do not require Accessibility permission. Selected-text Todo capture, window arrangement, and marking, unmarking, or recalling windows do require it because they read a selection or window state explicitly exposed by another app. NARC does not request Accessibility or notification access on launch. It explains the need when one of those capabilities is first invoked; notification access is requested only when a real notification is first delivered.

The local signing identity and Accessibility are separate concerns. The installer first creates or inherits a local identity for the current user; the first real selected-text or window action then asks you to grant Accessibility. Later source updates keep the same authorization identity unless you change Mac or macOS user, delete the locked keychain identity, reset privacy permissions, or manually change NARC's signer.

For selected-text and window tools, enable NARC under:

**System Settings → Privacy & Security → Accessibility → NARC**

NARC rechecks the permission every three seconds after you enable it, and a quit or restart is normally unnecessary. Once confirmed, close System Settings and return to the original app. Press a window shortcut again for a window action; for selected-text Todo, select the text again and press the currently configured shortcut. NARC deliberately does not replay the interrupted action automatically because System Settings would usually be frontmost by then. If macOS still rejects the current app while the switch is on, NARC shows the actual running path and stale-entry recovery guidance; reopening NARC is only the fallback.

## Data and privacy

- Inbox, Todo, and Notes are stored locally by default.
- The data file is `~/Library/Application Support/NARC/assistant-v1.json`.
- The installer stores only the signing certificate's public SHA-1 fingerprint to detect identity loss. For a new Local v1 identity, it imports the private key as non-extractable and initially limits access to the system `codesign` tool. An inherited legacy identity is never exported, copied, or rewritten. Private keys never enter Git, logs, CI, or the network.
- To avoid a confirmation on every later update, another local process running as the same user may also invoke the system `codesign` tool with an installer-created Local v1 identity. It cannot obtain the private-key file, and this local identity does not provide Developer ID publisher assurance. This is the explicit tradeoff between automatic local update builds and approving every signature manually.
- Existing data migrates to schema v4 on the first successful save; loading alone does not rewrite it. Priority, deadlines, the explicit next task, and task deferrals stay in the local file. Daily schedules, consumption timestamps, and review snoozes are stored in local preferences without Todo text or task UUIDs.
- This version does not call an external model API and has no cloud sync or team collaboration.
- NARC does not continuously monitor or automatically read message content in WeChat, WeCom, or other apps. Only when you explicitly select text and press the selected-text Todo shortcut does it lock the frontmost app and focused control, then immediately begin one standard AX selection read; the successful read becomes the capture snapshot. It does not read or modify the clipboard, simulate `⌘C`, or use screenshot OCR, AI, private databases, process injection, or private hooks.

Removing the app does not automatically erase personal records.

## Current boundaries

- No Dock icon, Workspace entry point, or embedded terminal entry point.
- No conversational AI, automatic classification, or cross-module AI execution. Basic Todo surfacing and deferral do not depend on AI.
- No recurring tasks or macOS system-notification reminders. Deadlines affect ordering, not extra alerts; daily reviews follow your configured times.
- No Apple Notes, Reminders, Calendar, GitHub, or other external connectors.
- No per-conversation WeChat/WeCom unread state or automatic message-content reading. Explicitly selecting text and pressing the Todo shortcut is one user-initiated capture, not message monitoring.
- No third-party dynamic plugins, script marketplace, or plugin permission system.
- No automatic updater, DMG, PKG, prebuilt app, or certificate/notarization distribution chain.

These boundaries keep capture, awareness, and recovery focused on a reliable, low-interruption local loop.

## Update

Choose **Quit NARC**, then run this from the repository directory:

```bash
git pull --ff-only && bash scripts/install.sh
```

The installer does not force-quit a running NARC instance or delete personal records. It reconciles the installed app, fingerprint marker, and keychain identity before reusing a signer. It can safely inherit an eligible legacy signer when no marker exists, but stops when two stable identities conflict; it never silently rotates or falls back to ad-hoc signing. Only one install command per user can proceed at a time, even across separate clones. If switching is interrupted or final verification fails, the previous app and fingerprint marker are restored together.

## Uninstall

1. Choose **Quit NARC**.
2. Delete `~/Applications/NARC.app`.

Personal records remain. Only if you are sure you no longer need them, delete the data file:

`~/Library/Application Support/NARC/assistant-v1.json`

A normal uninstall leaves the locked local signing identity and its public fingerprint marker in place, so a later reinstall can reuse it. That identity may be a new Local v1 or an inherited legacy `NARC Dev`; the installer stops on a fingerprint mismatch instead of replacing it silently.

## Troubleshooting

### NARC is not visible

NARC does not appear in the Dock by default. Look for the `N` in the menu bar, or run:

```bash
open ~/Applications/NARC.app
```

If NARC is running, use your configured summon shortcut (default `⌃⌥N`) or click the menu bar `N`.

### A shortcut does nothing

- Summon Widget and Quick Capture use saved bindings at startup (defaults `⌃⌥N` / `⌃⌥Q`) without Accessibility permission.
- Selected-text Todo defaults to `⌃⌥T`; like window pinning and arrangement, it explains and requests Accessibility permission on first use.
- Check the actual status under **Preferences → Shortcuts**, and ensure a layout's Windows checkbox is enabled. Failed replacements preserve the old binding. If a saved shortcut cannot register on startup, choose another combination or resolve its conflict and retry.

### The WeCom or WeChat number does not match

NARC reads the Dock badge that macOS LaunchServices exposes. The value may lag while an app is signed out, does not expose a badge, has multiple instances, or has not refreshed its state. Unknown state appears as `?`, or as a last trusted value such as `14?`.

### Update says NARC is running

Choose **Quit NARC**, then run:

```bash
bash scripts/install.sh
```

### Selected-text or window tools still ask after Accessibility is enabled

Check the running path shown in the message first. Regular use should open `~/Applications/NARC.app` unless you chose a different install directory. A manually built ad-hoc development app under the repository's `build/` directory cannot inherit the stable installation's signing authorization. Quit that temporary app and reopen the installed app; do not delete the existing grant or rebuild the identity just because the temporary app is rejected. For no-permission UI development, use `bash scripts/dev-run-no-ax.sh debug`; for real window tools, use the normal installer to preserve the existing identity.

An early v2 preview installer replaced legacy `NARC Dev` with Local v1, which can leave the System Settings switch on while macOS rejects the current app. If the unique legacy private key is still available, quit NARC and run this from the repository:

```bash
bash scripts/install.sh --restore-legacy-signer
```

The installer shows the full old fingerprint and changes both the app and local marker only after you enter that exact value in Terminal. It deletes no identity and never resets TCC. If no legacy signer can be recovered, or macOS still retains a stale row afterward, remove the old NARC row under **System Settings → Privacy & Security → Accessibility** and add the current path shown by NARC once.

### Setup reports an unavailable login keychain or `errSecInternalComponent`

The installer stops before replacing the app, so the existing NARC and permission remain unchanged. Open Keychain Access, unlock the **login** keychain in the sidebar, and rerun `bash scripts/install.sh`. Do not delete certificates or reset Accessibility.

### Rebuild the local signing identity

An installer-created Local v1 identity is valid for ten years. Rebuild it only if you deliberately deleted it, it became damaged, or it expired: quit NARC, remove any remaining `NARC Local Code Signing Identity v1` item in Keychain Access, delete the public marker at `~/Library/Application Support/NARC/signing-identity.sha1`, then run `bash scripts/install.sh` again. A new identity requires enabling Accessibility once more for selected-text and window tools; the installer never resets TCC automatically. If NARC currently inherits legacy `NARC Dev`, do not delete it through this procedure—preserving it is what preserves the existing grant.

## Development and verification

```bash
# Build a runnable Debug app
NARC_SIGNING_MODE=adhoc bash scripts/build-app.sh debug
open build/NARC.app

# Full test suite
swift test

# Guard against installers, distributable certificate chains, and automatic updaters
bash scripts/verify-source-only-distribution.sh

# Build the Swift package only
swift build
```

Stack: Swift 5.9 Package, SwiftUI + AppKit, and macOS 14+. See [Project Profile](docs/PROJECT.md) for product goals and boundaries.
