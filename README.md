<div align="center">

[English](#english) &nbsp;&nbsp;|&nbsp;&nbsp; [中文](#中文)

</div>

---

<a id="english"></a>

# NARC for Mac

**Notification & Application Resource Center**

You're a developer who spends most of the day inside a terminal, but your attention is constantly pulled away — by WeChat messages, by Claude Code waiting for approval in some buried iTerm tab, by the friction of arranging windows and hunting for the right session. Each of these distractions seems small on its own. Add them up across a workday, and they're not small anymore.

NARC is a single desktop entry point that eliminates three recurring taxes on your attention.

---

## The Three Attention Taxes

Every developer working across IM tools, terminals, and Claude Code sessions pays three invisible taxes. You feel them as fatigue, but you don't usually name them:

| Tax | What it costs you | How NARC eliminates it |
|-----|-------------------|------------------------|
| **Attention Tax**<br><sub>注意力税</sub> | Checking WeChat, WeCom, and Lark separately for new messages. Each unread badge is a micro-interrupt. Each "just checking" is a context loss. | **[Unified Notification Center](#unified-notification-center)** — one red badge aggregates all IM sources. One click reveals who needs you, no app-switching. Filter rules let you mute noise before it reaches your eyes. |
| **Context Tax**<br><sub>上下文税</sub> | You have 4 Claude Code sessions running across iTerm tabs, Tmux panes, and VS Code terminals. Which one is waiting for permission? Which project is in tab 3? Finding the right terminal and re-establishing mental context takes 30 seconds each time — 10+ times a day. | **[NARC Workspace](#narc-workspace)** — all Claude sessions live in one window with live status badges per tab. `⏳ Thinking` / `⚠️ Approval` / `■ Ended`. Tabs flash red when Claude needs you. One click, no hunting. |
| **Friction Tax**<br><sub>摩擦税</sub> | Dragging windows to screen edges. Switching Spaces to find that pinned IDE window. Cmd+Tab through 20 apps to reach the one you need. These micro-operations feel trivial but compound into hundreds of wasted gestures per day. | **[Window Management + Pinning](#window-management-and-pinning)** — keyboard-driven window snapping with 10 layout presets. Pin any window for instant cross-Space access via `⌃⌥P`. Two keystrokes, zero drags. |

---

## How It Works

A 48pt floating circle sits at the edge of your screen — always on top, never in the way.

- **Left-click** → notification panel slides out. See IM unreads, Claude pending approvals, and pinned windows — all in one list.
- **Right-click** → the Workspace Dashboard opens. Every Claude Code session, every shell, every project — tabs on the left, live terminal on the right. Close the window and your sessions keep running.
- **`⌃⌥` + arrow** → snap any window to a screen half, corner, or center. No drag, no delay.
- **`⌃⌥P`** → pin the current window. Access it from the panel from any Space.

<img src="Resources/demo-screenshot.png" alt="NARC floating widget, panel, and dashboard" width="800">

---

## What NARC Replaces

| You used to… | Now you… |
|--------------|----------|
| ⌘Tab through 3 IM apps to check badges | Glance at one red dot |
| Dig through iTerm tabs to find the Claude session that needs approval | See a flashing red tab badge, click once |
| Drag every window to position it | `⌃⌥→` — done |
| Swipe between Spaces to reach pinned reference windows | `⌃⌥P` to pin, panel click to jump — cross-Space in one gesture |
| Run `claude` in scattered terminal tabs, forget which is which | NARC Workspace: labeled tabs, live Claude state badges, cwd tracking |

---

<a id="unified-notification-center"></a>

## Unified Notification Center

Real-time Dock badge monitoring for WeChat, WeCom, and Lark. One aggregated badge on the floating widget replaces three separate notification sources.

- Click any IM row → the app window summons to your current screen (even if minimized or on another display)
- **Claude section** — pending approvals and Stop/Error events have their own list with one-click dismiss
- **Filter rules** — mute specific apps, set badge thresholds, match keywords (WIP)

---

<a id="narc-workspace"></a>

## NARC Workspace

An embedded multi-terminal dashboard powered by [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm). Think of it as "iTerm, but purpose-built for Claude Code workflows."

- **Real PTY terminals** — full ANSI, kitty keyboard protocol, OSC 7 cwd tracking
- **Tab persistence** — close the Dashboard window, your sessions keep running. Reopen and pick up exactly where you left off.
- **Live state badges per tab** — `⏳ Thinking` → `→ ToolName` → `⚠️ Approval` → `💬 Waiting` → `🗜 Compressing` → `■ Ended`
- **`NARC_SESSION_ID` env var** — hook events from Claude Code route back to the exact tab that spawned them
- **Custom tab titles** — double-click to rename
- **`⌘1`–`⌘9` tab switching** (v1.4), drag-reorder tabs (v1.4)

---

<a id="window-management-and-pinning"></a>

## Window Management & Pinning

Magnet-equivalent window snapping plus cross-Space window pinning — keyboard-driven, no mouse needed.

### Window Snapping

| Hotkey | Layout |
|--------|--------|
| `⌃⌥←` `⌃⌥→` | Left / Right Half |
| `⌃⌥↑` `⌃⌥↓` | Top / Bottom Half |
| `⌃⌥U` `⌃⌥I` `⌃⌥J` `⌃⌥K` | Four Corners |
| `⌃⌥↩` | Full Screen |
| `⌃⌥C` | Center |

- Zero-delay, single `setFrame` call — no flicker, no correction passes
- **Cross-screen state machine** — press the same direction again within 5s to move the window to the adjacent display
- Properly handles `AXEnhancedUserInterface` (WeChat, Electron apps)

### Window Pinning

- `⌃⌥P` to pin the current window → appears in the NARC panel
- **Cross-Space activation** — clicking a pinned window switches to its Space via AppleScript (smooth, no animation flicker)
- Two modes: **Temporary (📌)** — cleared on restart; **Persistent (🔒)** — saved to disk
- Uses `CGWindowID` for unambiguous window identification — works with multi-window apps

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌃⌥N` | Toggle NARC panel |
| `↑` / `↓` | Navigate panel items |
| `↩` | Activate selected item |
| `1`–`0` | Quick access by index |
| `Esc` | Close panel |
| `⌃⌥P` | Pin current window |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | Window snapping |

---

## Installation

### Requirements

- macOS 14 Sonoma or later
- **Accessibility permission** (System Settings → Privacy & Security → Accessibility)
- Screen Recording permission (optional, for cross-Space window detection)

### Build from Source

```bash
git clone https://github.com/MickMi/narc_for_mac.git
cd narc_for_mac
./scripts/build-app.sh          # builds NARC.app with stable self-signed identity
open build/NARC.app
```

The build script signs with a stable `NARC Dev` identity, so Accessibility permission survives across rebuilds.

### Run in Development

```bash
swift run -c release NARC
```

> SwiftTerm is fetched on first build (~30s). Subsequent builds are incremental.

### Claude Code Hook Setup

NARC monitors Claude Code sessions via a Python hook. To enable it:

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

Sessions spawned inside the NARC Workspace automatically receive `NARC_SESSION_ID`, so events route back to the correct tab. External terminals (iTerm, Terminal.app) are matched via TTY device path + CWD.

---

## Architecture

```
Sources/
├── App/           NARCApp.swift, AppDelegate.swift       — entry, lifecycle, hotkeys
├── Models/        Models.swift, KeyboardSelection.swift  — data types
├── Services/      AppMonitorService, ClaudeSessionService, HotkeyService,
│                  PinnedWindowService, ScreenNavigator, TerminalSessionManager,
│                  WindowLayoutState, WindowManagerService
├── Utils/         AXWindowHelper.swift                   — low-level AX API
└── Views/         Dashboard, Panel, FloatingWidget, TerminalPane,
                   NotificationList, Preferences, ClaudeToast/Approval
```

| Layer | Technology |
|-------|-----------|
| Language | Swift 5.9 |
| UI | SwiftUI + AppKit (NSPanel, NSStatusBar) |
| Embedded Terminal | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.2.x |
| Window Control | Accessibility API (AXUIElement) |
| Cross-Space | AppleScript |
| Badge Reading | `lsappinfo` CLI |
| Hotkeys | Carbon Event API |
| Claude IPC | Unix socket + Python hook + `NARC_SESSION_ID` |

---

## Roadmap

| Version | Focus |
|---------|-------|
| **v1.3** ← current | NARC Workspace, spec-D floating widget, Claude panel exit |
| v1.4 | Tab font size (`⌘+`/`⌘-`), `⌘1`–`⌘9` tab switching, drag-reorder, scrollback search |
| v1.5 | Developer ID signing + Notarization + GitHub Release CI |
| v2.0 | IDE task monitoring (VS Code extension bridge) |
| v2.1 | Message content preview |
| v3.0 | Plugin system for third-party integrations |

### Known Limitations

- WeCom (企业微信) badge detection relies on `lsappinfo`; WeCom's custom Dock badge rendering may not always register.
- Claude Code hook requires manual setup (copy script + edit settings.json).
- Cross-Space window activation depends on AppleScript title matching; nearly identical window titles may cause ambiguity.

---

## License

MIT — built with Swift, SwiftUI, [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), and a lot of `⌃⌥` key combos.

---

<a id="中文"></a>

# NARC for Mac

**Notification & Application Resource Center（通知与应用资源中心）**

你是一个大部分时间待在终端里的开发者，但注意力被不断扯开——微信消息、埋在某 iTerm 标签页里等待审批的 Claude Code、拖窗口找会话的摩擦。每一次打断单看都不大，但叠加在一个工作日里就不再是小问题。

NARC 是一个桌面统一入口，专门消除反复吞噬你注意力的三类隐性成本。

---

## 三种注意力的税

每个在 IM、终端和 Claude Code 会话间穿梭的开发者，都在缴纳三种看不见的税。你感受到的是疲劳，但很少为它们命名：

| 税种 | 你在付出什么 | NARC 如何消灭它 |
|------|------------|----------------|
| **注意力税**<br><sub>Attention Tax</sub> | 分别检查微信、企业微信、飞书有没有新消息。每个未读角标都是一次微打断。每次"就看一眼"都是一次上下文丢失。 | **[统一通知中心](#统一通知中心)** — 一个红色角标聚合所有 IM 来源。一次点击就知道谁找你，无需切换应用。过滤规则在噪音抵达你眼睛之前就把它静音。 |
| **上下文税**<br><sub>Context Tax</sub> | 4 个 Claude Code 会话散落在 iTerm 标签页、Tmux 窗格、VS Code 终端里。哪个在等审批？标签页 3 里是哪个项目？每次找到对应终端并重建心智上下文要花 30 秒——一天十几次。 | **[NARC 工作区](#narc-工作区)** — 所有 Claude 会话在一个窗口里，每个标签页实时状态徽章：`⏳ 思考中` / `⚠️ 待审批` / `■ 已结束`。需要你时标签页闪烁红色。一键直达，无需翻找。 |
| **摩擦税**<br><sub>Friction Tax</sub> | 拖窗口到屏幕边缘、在 Space 之间滑来滑去找那个钉住的 IDE、Cmd+Tab 翻 20 个应用找需要的那一个。每次操作微不足道，但一天累积成百上千次无意义手势。 | **[窗口管理 + 钉选](#窗口管理与钉选)** — 纯键盘驱动窗口贴靠，10 种布局预设。`⌃⌥P` 钉选任意窗口，跨 Space 即时跳转。两次按键，零次拖拽。 |

---

## 使用方式

一个 48pt 的浮动圆圈常驻屏幕边缘——始终置顶，从不碍事。

- **左键** → 通知面板滑出。IM 未读、Claude 待审批、钉选窗口，一览无余。
- **右键** → 工作区仪表盘打开。每个 Claude Code 会话、每个 Shell、每个项目——左侧标签页，右侧实时终端。关闭窗口，会话继续运行。
- **`⌃⌥` + 方向键** → 将任意窗口贴靠至半屏、角落或居中。不拖拽，零延迟。
- **`⌃⌥P`** → 钉选当前窗口。从任意 Space 通过面板直达。

<img src="Resources/demo-screenshot.png" alt="NARC 浮动组件、面板和仪表盘" width="800">

---

## NARC 替代了什么

| 以前你要… | 现在你… |
|----------|--------|
| ⌘Tab 切 3 个 IM 应用检查角标 | 看一眼红色角标 |
| 翻 iTerm 标签页找等审批的 Claude 会话 | 看到闪烁红色标签徽章，点一下 |
| 拖每个窗口调整位置 | `⌃⌥→` — 完成 |
| 在 Space 之间划触摸板找钉住的参考窗口 | `⌃⌥P` 钉选，面板点击跳转——一个手势跨 Space |
| 在散落终端标签页里跑 `claude`，分不清哪个是哪个 | NARC 工作区：命名标签页、实时 Claude 状态、工作目录追踪 |

---

<a id="统一通知中心"></a>

## 统一通知中心

实时 Dock 角标监控：微信、企业微信、飞书。一个聚合角标替代三个分散的通知源。

- 点击任意 IM 行 → 应用窗口召唤至当前屏幕（即使已最小化或在其他显示器上）
- **Claude 专区** — 待审批和停止/错误通知独立列表，一键关闭
- **过滤规则** — 静音特定应用、设置角标阈值、关键词匹配（开发中）

---

<a id="narc-工作区"></a>

## NARC 工作区

基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 的嵌入式多终端仪表盘。可以理解为"专为 Claude Code 工作流打造的 iTerm"。

- **真实 PTY 终端** — 完整 ANSI、kitty 键盘协议、OSC 7 工作目录追踪
- **标签页持久化** — 关闭仪表盘窗口，会话继续运行。重新打开从上次离开的位置继续
- **实时状态徽章** — `⏳ 思考中` → `→ 工具名` → `⚠️ 待审批` → `💬 等待输入` → `🗜 压缩上下文` → `■ 已结束`
- **`NARC_SESSION_ID` 环境变量** — Claude Code 的 Hook 事件精准路由回发起会话的标签页
- **自定义标签标题** — 双击重命名
- **`⌘1`–`⌘9` 标签页切换**（v1.4）、拖拽排序（v1.4）

---

<a id="窗口管理与钉选"></a>

## 窗口管理与钉选

媲美 Magnet 的键盘贴靠 + 跨 Space 窗口钉选——纯键盘驱动，无需鼠标。

### 窗口贴靠

| 快捷键 | 布局 |
|--------|------|
| `⌃⌥←` `⌃⌥→` | 左/右半屏 |
| `⌃⌥↑` `⌃⌥↓` | 上/下半屏 |
| `⌃⌥U` `⌃⌥I` `⌃⌥J` `⌃⌥K` | 四角 |
| `⌃⌥↩` | 全屏 |
| `⌃⌥C` | 居中 |

- 零延迟，单次 `setFrame` 调用——无闪烁、无校正回弹
- **跨屏状态机** — 5 秒内再次按同方向键，窗口移至相邻显示器
- 正确处理 `AXEnhancedUserInterface`（微信、Electron 应用）

### 窗口钉选

- `⌃⌥P` 钉选当前窗口 → 出现在 NARC 面板中
- **跨 Space 激活** — 点击钉选窗口通过 AppleScript 切换至其所在 Space（平滑无动画闪烁）
- 两种模式：**临时 (📌)** — 重启清除；**持久 (🔒)** — 存盘保留
- 使用 `CGWindowID` 精准识别窗口——多窗口应用无歧义

---

## 快捷键一览

| 快捷键 | 操作 |
|--------|------|
| `⌃⌥N` | 切换 NARC 面板 |
| `↑` / `↓` | 导航面板项目 |
| `↩` | 激活选中项 |
| `1`–`0` | 按索引快速访问 |
| `Esc` | 关闭面板 |
| `⌃⌥P` | 钉选当前窗口 |
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | 窗口贴靠 |

---

## 安装

### 系统要求

- macOS 14 Sonoma 或更高版本
- **辅助功能权限**（系统设置 → 隐私与安全性 → 辅助功能）
- 屏幕录制权限（可选，用于跨 Space 窗口检测）

### 从源码构建

```bash
git clone https://github.com/MickMi/narc_for_mac.git
cd narc_for_mac
./scripts/build-app.sh          # 构建 NARC.app，含稳定自签名身份
open build/NARC.app
```

构建脚本使用固定的 `NARC Dev` 身份签名，因此重新构建后辅助功能权限不会丢失。

### 开发环境运行

```bash
swift run -c release NARC
```

> SwiftTerm 首次构建时获取（约 30 秒），后续为增量编译。

### Claude Code Hook 配置

NARC 通过 Python Hook 监控 Claude Code 会话。启用方式：

```bash
cp scripts/narc-hook.py ~/.claude/hooks/narc-hook.py
chmod +x ~/.claude/hooks/narc-hook.py
```

然后在 `~/.claude/settings.json` 中添加：

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

NARC 工作区内生成的会话会自动注入 `NARC_SESSION_ID`，事件精准路由回对应标签页。外部终端（iTerm、Terminal.app）通过 TTY 设备路径 + 工作目录匹配。

---

## 架构

```
Sources/
├── App/           NARCApp.swift, AppDelegate.swift       — 入口、生命周期、快捷键
├── Models/        Models.swift, KeyboardSelection.swift  — 数据类型
├── Services/      AppMonitorService, ClaudeSessionService, HotkeyService,
│                  PinnedWindowService, ScreenNavigator, TerminalSessionManager,
│                  WindowLayoutState, WindowManagerService
├── Utils/         AXWindowHelper.swift                   — 底层 AX API
└── Views/         Dashboard, Panel, FloatingWidget, TerminalPane,
                   NotificationList, Preferences, ClaudeToast/Approval
```

| 层级 | 技术 |
|------|------|
| 语言 | Swift 5.9 |
| UI | SwiftUI + AppKit (NSPanel, NSStatusBar) |
| 嵌入式终端 | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.2.x |
| 窗口控制 | Accessibility API (AXUIElement) |
| 跨 Space | AppleScript |
| 角标读取 | `lsappinfo` CLI |
| 快捷键 | Carbon Event API |
| Claude 通信 | Unix Socket + Python Hook + `NARC_SESSION_ID` |

---

## 路线图

| 版本 | 重点 |
|------|------|
| **v1.3** ← 当前 | NARC 工作区、D 规范浮动组件、面板 Claude 出口 |
| v1.4 | 标签页字号调节、`⌘1`–`⌘9` 切换、拖拽排序、回滚搜索 |
| v1.5 | Developer ID 签名 + 公证 + GitHub Release CI |
| v2.0 | IDE 任务监控（VS Code 扩展桥接） |
| v2.1 | 消息内容预览 |
| v3.0 | 第三方集成插件系统 |

### 已知限制

- 企业微信角标检测依赖 `lsappinfo`；企业微信的自定义 Dock 角标渲染可能无法始终检测到。
- Claude Code Hook 需要手动安装（复制脚本 + 编辑 settings.json）。
- 跨 Space 窗口激活依赖 AppleScript 标题匹配；高度相似的窗口标题可能产生歧义。

---

## 许可证

MIT — 基于 Swift、SwiftUI、[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 及大量 `⌃⌥` 组合键构建。

---

<div align="center">

[↑ Back to top / 回到顶部](#)

</div>
