# STATE - trusted handoff

> 任何 AI 打开本项目，先读这里。这里不记录强/弱模型身份，只记录可信事实、当前边界、待验证项和下一步。

## ENTRY POINT
- 当前阶段: Evidence Reset 后的重建期。
- `plan.md`: 当前不存在；不进入 Executor plan 模式。
- Harness 定位: 开发规范、证据纪律、边界控制、验证闭环和交接格式。模型强弱切换只是可选调度策略，不是项目状态。
- 工作树状态: 当前有大量既有未提交改动。不要回滚用户或历史改动；只改当前任务明确范围。

## 当前可信事实
- 已归档一批不可信中间产物到 `docs/archive/stale-harness-v1/`，仅隔离，不删除。
- 当前业务视角功能清单记录在 `docs/FEATURES.md`；它只描述用户可见能力状态，不作为 bug backlog 或实现计划。
- 高频 UI / Workspace / terminal 验证可使用 `NARC_DEV_NO_AX=1` 开发模式，跳过权限弹窗、Accessibility 检查、AX pin/布局热键、窗口吸附、AX 窗口控制和系统通知授权；常驻监控与 `⌃⌥N` / `⌃⌥W` 保持可用。
- 需要验证标记窗口 / AX 热键 / 窗口管理时，优先使用 `bash scripts/dev-run-terminal-host.sh debug`。该模式通过 `swift run` 以终端托管 raw executable 运行，隐藏 Dock 图标，不使用 `.app` bundle 身份，保留 `⌃⌥P`、`⌃⌥N`、`⌃⌥W` 和布局热键。
- 以下历史文档仍可作为背景参考，但不是当前 bug 修复的自动指令:
  - `docs/PRD-claude-tab-monitor.md`
  - `docs/blueprint-claude-tab-monitor.md`
  - `docs/reviews/claude-tab-monitor-2026-06-10.md`
  - `docs/PRD-workspace-ux-polish.md`
  - `docs/blueprint-smart-copy.md`
  - `docs/blueprint-widget-drag-fix.md`
  - `docs/reviews/smart-copy-drag-fix-2026-06-18.md`
- `docs/archive/stale-harness-v1/` 内文档来自旧 Harness 中间状态，后续不得直接当作执行蓝图。

## 已修改但待真实手测
- Workspace / Claude Code 内容区滚轮: `TerminalPaneView.swift` 已改为 normal shell 走 SwiftTerm scrollback，alternate-screen TUI 在启用 mouse reporting 时接收 mouse wheel 事件；禁止转译为上/下箭头。
- Panel 快捷键: `AppDelegate.swift` 已去掉启动时无条件打开 Workspace，避免唤起 quick panel 时顺手弹出 Workspace。
- Workspace Tab 拖拽预览: `DashboardView.swift` 已限制拖拽浮层宽度，避免撑满整个列表。
- 以上三项已通过 `swift build --disable-sandbox` 编译验证，但仍需要在真实 app 中手测。

## 当前已知产品问题
- diff / 文件改动体验还没有重新定义清楚，暂不继续按旧蓝图实现。
- app 内“回合卡片”目前没有数据模型和 UI。现有链路是 `ClaudeSessionService.fileHistory -> OwnedSession.touchedFiles -> FileChangePopover`，属于会话累计文件列表，不是按 Claude 每轮分组。
- “回合”边界需要先定义: 例如从用户发送输入开始，到 Claude Stop / 等待输入 / 需要审批 / 出错为止，还是以工具调用批次为边界。
- 默认入口需要更清楚地暴露“打开文件”和“对比 diff”，并考虑左右分屏 diff，而不是当前右侧抽屉。

## 已隔离的旧中间产物
- `docs/archive/stale-harness-v1/PRD-backlog-v14-v15.md`
- `docs/archive/stale-harness-v1/PRD-diff-drawer.md`
- `docs/archive/stale-harness-v1/PRD-next-round.md`
- `docs/archive/stale-harness-v1/blueprint-backlog-v14-v15.md`
- `docs/archive/stale-harness-v1/blueprint-diff-drawer.md`
- `docs/archive/stale-harness-v1/reviews/backlog-v14-v15-2026-06-23.md`

## 下一步建议
1. 用 `bash scripts/dev-run-no-ax.sh debug` 做高频 UI / Workspace / terminal 手测；需要验证全局热键/窗口管理/标记窗口时，用 `bash scripts/dev-run-terminal-host.sh debug`。
2. 重新写一个很小的 PRD: `diff / 文件改动 / app 内回合卡片`。
3. PRD 里必须先确认“每一轮”的产品边界，再实现数据模型和 UI。

## 回合卡片要求
- 只要本回合有交付物、状态变化、归档、文件改动、卡点或阶段推进，最终回复必须输出回合卡片。
- 如果没有回合卡片，应视为没有完整遵守 Harness 交接约束。
