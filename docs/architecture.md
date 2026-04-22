# 系统架构与业务上下文 — NARC for Mac

## 🎯 业务最终目标
**NARC (Notification & Application Resource Center)** 是一个原生 macOS 桌面悬浮窗应用，充当统一的"通知中心 + 状态面板 + 窗口管理"入口。

**核心价值**：用户无需在多个应用间切换，即可通过一个常驻桌面的悬浮窗感知所有关键工作状态变化（IM 新消息、IDE 任务完成等），点击后展开面板查看详情并快速跳转到对应应用处理。同时集成窗口管理能力（类似 Magnet），提供分屏与拖拽吸附。

**产品形态**：桌面悬浮窗（小圆点/图标） + 点击展开的详情面板 + 菜单栏备用入口。

## 🧩 核心模块划分
| 模块名 | 职责描述 | 对外暴露接口 | 依赖的其他模块 |
|--------|---------|-------------|---------------|
| **FloatingWidget** | 桌面悬浮窗 UI，常驻显示，支持拖拽移动，展示聚合状态（红点/badge） | `show()`, `hide()`, `updateBadge()` | AppMonitor |
| **PanelView** | 展开面板 UI，展示 Monitoring 区（IM App 状态）和 Pinned 区（固定窗口），支持键盘导航和点击跳转 | `expand()`, `collapse()`, keyboard nav | FloatingWidget, AppMonitor, PinnedWindowService |
| **AppMonitorService** | 应用监控引擎，监控目标 App 的 Dock badge 变化（lsappinfo），检测新消息，支持过滤规则 | `startMonitoring()`, `stopMonitoring()`, `activateApp()` | WindowManagerService |
| **PinnedWindowService** | 窗口固定服务，管理用户 Pin 的窗口，支持跨桌面呼出、存活状态轮询、持久化存储 | `pinCurrentWindow()`, `unpin()`, `activatePinnedWindow()` | WindowManagerService |
| **WindowManagerService** | 窗口管理核心，意图式布局（Magnet 风格），支持 10 种布局 + 多显示器跨屏切换 + 窗口召唤 | `moveActiveWindow()`, `summonAppWindow()`, `findAppWindow()` | AXWindowHelper, ScreenNavigator |
| **ScreenNavigator** | 多显示器导航，检测窗口所在屏幕、判断窗口是否已在目标布局（硬/软维度策略）、计算跨屏入口布局 | `isWindowAtLayout()`, `adjacentScreen()`, `crossScreenEntryLayout()` | AXWindowHelper |
| **HotkeyService** | 全局快捷键注册（Carbon Event API），管理布局快捷键 + Pin 快捷键 + 面板呼出快捷键 | `registerGlobalHotkeys()`, `onLayoutHotkeyPressed` | — |
| **AXWindowHelper** | Accessibility API 底层工具，窗口属性读写、坐标转换（NS↔AX）、布局帧计算、原生全屏检测 | `setFrame()`, `calculateLayoutFrame()`, `screenForWindow()` | — |
| **PreferenceStore** | 用户偏好管理，存储/读取监控配置、过滤规则、Pin 窗口持久化 | `get()`, `set()`, `reset()` | — |
| **MenuBarAgent** | 菜单栏常驻图标，作为悬浮窗的备用入口（全屏模式下可用） | `showMenu()`, `updateIcon()` | AppMonitorService |

## 🗄️ 核心数据模型

```mermaid
erDiagram
    MonitoredApp ||--o{ NotificationState : "has current"
    MonitoredApp ||--o{ NotificationFilter : "filtered by"
    WindowLayout ||--o{ HotkeyBinding : "bound to"
    PinnedWindow ||--o{ PinnedWindowRuntimeState : "has runtime"

    MonitoredApp {
        string bundleID PK "e.g. com.tencent.xinWeChat"
        string displayName "e.g. WeChat"
        string category "im / ide / other"
        bool isEnabled "user toggle"
    }
    NotificationState {
        string bundleID FK
        int badgeCount "0 = no new message"
        bool isRunning
        datetime lastUpdated
    }
    NotificationFilter {
        uuid id PK
        string appBundleID FK "* = all apps"
        string filterType "badgeThreshold / keyword / alwaysNotify / mute"
        string pattern
        string action "highlight / normal / silent / hide"
        bool isEnabled
    }
    WindowLayout {
        string rawValue PK "e.g. Left Half"
        CGRect fractionalFrame "(x, y, w, h) as fraction of screen"
        string hotkeyLabel "e.g. ctrl+opt+left"
    }
    HotkeyBinding {
        string layoutID FK
        uint32 keyCode
        uint32 modifiers
    }
    PinnedWindow {
        uuid id PK
        string bundleID "app bundle ID"
        string windowTitle "title at pin time"
        string appDisplayName
        bool isPersistent "false=temporary, true=fixed"
        datetime pinnedAt
    }
    PinnedWindowRuntimeState {
        uuid pinnedWindowID FK
        bool isAlive "app/window still running"
        string currentTitle "real-time title"
    }
```

## 🔀 核心数据流 / 状态管理

```mermaid
flowchart TB
    subgraph Monitoring ["Monitoring Layer"]
        AM[AppMonitorService<br/>Dock Badge Polling<br/>lsappinfo]
        PWS[PinnedWindowService<br/>Window Alive Polling<br/>AX API]
        NL[Notification Listener<br/>Future: UNNotification]
    end

    subgraph UI ["UI Layer"]
        FW[FloatingWidget<br/>Badge / Red Dot]
        PV[PanelView<br/>Two-Zone: Monitoring + Pinned]
        KB[Keyboard Navigation<br/>↑↓ / Tab / Enter / 1-0]
        MB[MenuBarAgent<br/>Fallback Entry]
    end

    subgraph WindowMgmt ["Window Management"]
        WM[WindowManagerService<br/>Intent-based Layout]
        SN[ScreenNavigator<br/>Hard/Soft Dimension Strategy]
        HK[HotkeyService<br/>Carbon Event API]
        AX[AXWindowHelper<br/>AX API + Retry]
    end

    AM -->|badge change| FW
    PWS -->|alive status| PV
    NL -.->|future| FW
    FW -->|click / ⌃⌥N| PV
    PV -->|click IM app| AM
    AM -->|activateApp| WM
    PV -->|click pinned| PWS
    PWS -->|activatePinnedWindow| WM
    KB -->|select + enter| PV
    MB -->|click| PV
    HK -->|layout hotkey| WM
    HK -->|⌃⌥P| PWS
    WM --> SN
    WM --> AX
    SN --> AX
```

## ⚡ 非功能性需求 (NFR)
| 指标 | 目标值 | 备注 |
|------|--------|------|
| **CPU 空闲占用** | < 1% | Polling interval ≥ 2s |
| **内存占用** | < 50 MB | 常驻运行，轻量级 |
| **Badge 检测延迟** | < 3s | 从 App 收到消息到悬浮窗显示红点 |
| **窗口操作响应** | < 100ms | 快捷键触发到窗口移动完成 |
| **启动时间** | < 1s | 冷启动到悬浮窗可见 |

## 🚀 部署拓扑

- **平台**: macOS 14 Sonoma+ (原生 Swift/SwiftUI)
- **分发方式**: Developer ID 签名 + Apple Notarization + GitHub Releases
- **不上架 Mac App Store**（避免沙盒限制，保留 Accessibility API 完整能力）
- **CI/CD**: GitHub Actions (build → sign → notarize → release)
- **自动更新**: Sparkle framework (未来考虑)

## 📐 架构决策记录 (ADR) 索引
| # | 日期 | 决策 | 原因 | 状态 |
|---|------|------|------|------|
| 1 | 2026-03-30 | 确立 Vibe Coding 护栏机制 | 为 AI 辅助编码建立工程规范约束 | ✅ 生效 |
| 2 | 2026-04-09 | 引入三层记忆模型 (Session/Project/Global) | 参考 three-layer-memory-skill，解决记忆扁平化问题 | ✅ 生效 |
| 3 | 2026-04-09 | ~~确立"个人基础设施层"双仓库模型~~ → 已被 ADR-007 取代 | — | ❌ 废弃 |
| 4 | 2026-04-09 | `brain init` 一键加载 + 验证闭环 | 防止"加载了脚手架但没真正起作用" | ✅ 生效 |
| 5 | 2026-04-09 | 全局记忆只放采控记录 | 项目特有技术选型不放全局，只放跨项目通用偏好 | ✅ 生效 |
| 6 | 2026-04-09 | 检索优先原则 (Search-First) | 避免全量读取浪费 context window | ✅ 生效 |
| 7 | 2026-04-14 | 确立"单仓库双职能"模型 (Harness + Brain 合并)（取代 ADR-003） | 避免双仓库同步复杂度，统一管理 | ✅ 生效 |
| 8 | 2026-04-14 | 多平台写入策略 (IDE/CLI/Webhook) | 支持从 Cursor/Trae/Claude Web/ChatGPT 等多源写入 | ✅ 生效 |
| 9 | 2026-04-15 | 采用原生 macOS (Swift/SwiftUI) 技术栈 | 系统集成最深，Accessibility API 完整支持，性能最优 | ✅ 生效 |
| 10 | 2026-04-15 | 不上架 Mac App Store，GitHub Releases 分发 | 避免沙盒限制，保留窗口管理和进程监控的完整能力 | ✅ 生效 |
| 11 | 2026-04-15 | MVP 阶段 IM 监控采用 Dock Badge 方案 | 最轻量，无需 hack IM App 内部；架构预留通知中心拦截扩展点 | ✅ 生效 |
| 12 | 2026-04-15 | IDE 任务状态监控延后至 P2 | MVP 聚焦核心三大功能，IDE 桥接方案待 MVP 验证后再定 | ✅ 生效 |
| 13 | 2026-04-15 | 插件/扩展机制延后，但架构预留扩展点 | MVP 先跑通核心功能，避免过早抽象 | ✅ 生效 |
| 14 | 2026-04-22 | 窗口布局采用「意图形态」策略（Magnet 风格） | 布局快捷键表达空间意图而非精确像素；硬维度（布局控制的轴）严格匹配，软维度（应用可能约束的轴）宽容匹配 | ✅ 生效 |
| 15 | 2026-04-22 | macOS 原生全屏（绿色按钮）自动退出后再应用布局 | 原生全屏窗口在独立 Space 中，AX API 无法直接操控；先退出全屏等动画完成再 apply | ✅ 生效 |
| 16 | 2026-04-22 | AXWindowHelper.setFrame 采用验证+重试+波动检测机制 | Electron 等应用异步处理 resize，需要多次重试并检测尺寸稳定/波动状态 | ✅ 生效 |
| 17 | 2026-04-22 | 面板呼出跟随鼠标所在屏幕（右下角） | 用户按 ⌃⌥N 时面板出现在当前工作屏幕的右下角，而非浮窗所在屏幕 | ✅ 生效 |
