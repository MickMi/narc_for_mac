# Blueprint: v1.4 + v1.5 Backlog（9 功能）
- 对应 PRD: docs/PRD-backlog-v14-v15.md
- 蓝图状态: Draft（待确认）
- 目标执行方: 🔵 弱模型（或强模型 audit 现有实现）
- 说明：这 9 项**已有弱模型实现**在工作树里（能编译）。本蓝图既是"重跑契约"，也是"audit 基准"。每项注明：现有文件、目标、判定、禁止/风险。

---

## A. 智能复制气泡失焦消失 — `TerminalPaneView.swift`
- 现状：`NarcTerminalView` 选区气泡，仅在选区清空时消失。
- 实现：监听窗口失活与本 pane 取消选中：
  - `NotificationCenter` 订阅 `NSWindow.didResignKeyNotification`（限定 `self.window`）→ `dismissBubble()`。
  - 或在 `TerminalPaneView.updateNSView` 里：当 `isSelected` 由 true→false 时调用 `nsView.dismissBubble()`（需把 dismiss 暴露为 internal 方法）。
- 判定：切 Tab/切 App 气泡消失；点气泡仍能复制（不得用 `resignFirstResponder` dismiss）。
- 禁止：碰 `dedent`/⌘⇧C/复制逻辑。

## B. Tab 字体大小可调 — `TerminalPaneView.swift` + `PreferencesView.swift` + `DashboardView.swift`
- 存储：`@AppStorage("terminalFontSize") var terminalFontSize: Double = 13`（已有引用，核对 key 名统一）。
- 实现：
  - `NarcTerminalView`/`TerminalPaneView`：`term.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)`；在 `updateNSView` 里当字号变化时更新所有 pane 的 `term.font`。
  - 偏好 UI：Stepper/Slider 绑定该 key（范围 11–18）。
- 判定：改字号 → 所有已开终端立即变；重启保持。
- 禁止：影响侧栏/UI 字号。

## C. ⌘1~⌘9 切 Tab — `DashboardView.swift`
- 实现：在 Dashboard body 放 9 个隐藏按钮，各 `.keyboardShortcut(KeyEquivalent(Character("\(i)")), modifiers: .command)`，action = 若 `terminals.sessions.indices.contains(i-1)` 则 `terminals.selectedId = sessions[i-1].id`。（现实现"hidden buttons"思路正确，核对越界保护。）
- 判定：⌘N 切到第 N 个（存在才切）；不撞现有 ⌃⌥ 全局键（不同修饰键，安全）；焦点落到终端。
- 禁止：注册 Carbon 全局键（这是窗口内 SwiftUI 快捷键，不该全局）。

## D. 拖拽重排 Tab — `DashboardView.swift` + `TerminalSessionManager.swift`
- 模型：`TerminalSessionManager` 加 `func move(from: IndexSet, to: Int)` 直接对 `sessions` 重排（`sessions.move(fromOffsets:toOffset:)`）。
- 视图：左栏 `ForEach` 用 `.onMove` 或 `onDrag/onDrop` 重排，回调 `manager.move`。
- 判定：拖动改顺序；**PTY 不重建**（`OwnedSession.id` 不变，ZStack 里 pane 不被销毁）；claude 状态/选中保持。
- 禁止：因重排 `remove`+`newSession`（会杀进程）。

## E. Scrollback 搜索 — `TerminalPaneView.swift`
- 用 SwiftTerm 内置：`TerminalView` 暴露的搜索/`SearchService`（核对 1.2.x 实际 API：`func search(...)` 或 `TerminalSearch`）。
- 实现：⌘F 弹一个轻量搜索条（覆盖在 pane 顶部），输入 → 调内置搜索高亮 → ↑↓ 跳转 → Esc 关闭。
- 判定：命中高亮 + 可跳转 + 关闭恢复。
- 禁止：自造缓冲扫描；若 1.2.x 无可用搜索 API → 写 `docs/blueprint-gaps-backlog.md` 回流，不要硬造。

## F. diff 列表 +/− 徽标 — `DashboardView.swift`
- 现状：已有 `loadNumstat`（`git diff --numstat HEAD`，line ~117-128）。核对：
  - 单次调用映射 `path → (added, removed)`，存 `@State diffStats: [String:(Int,Int)]`。
  - `FileChangeRow` 右侧渲染 `+X −Y` 胶囊（绿/红，等宽）；无数据降级"新文件"/留空。
- 判定：每行显示增删；单次 git；异步不阻塞。
- 禁止：每文件单独 git 调用。

## G. 用户偏好持久化（悬浮窗位置）— `AppDelegate.swift`
- 存：悬浮窗 `windowDidMove` 时把 `window.frame.origin` 存进 `UserDefaults`（key `widgetOriginX`/`widgetOriginY`）。
- 取：`setupFloatingWidget` 时若有存值且**落在某个屏幕可见区内**则用之，否则默认右下角。
- 判定：拖动→重启→位置恢复；越界钳回可见区；首启默认。
- 禁止：存到屏幕外导致悬浮窗不可见（必须做可见区校验）。

## H. 通知聚合引擎 — `NotificationEngine.swift`（已存在）+ 接线
- 现状：`NotificationEngine.shared` 有 `publishIMEvents`/`publishClaudeEvents`/`@Published events/totalBadge`，但 **publish 合并逻辑不一致**（`publish(events:)` 与 `publishClaudeEvents` 各写一套 merge），且需确认**是否真被 UI 消费**。
- 决策（蓝图定）：本期引擎**仅作旁路聚合，不接管 badge**。即：
  - 保留 `FloatingWidgetContainer.computedState` 为 badge 唯一数据源（不改）。
  - 引擎由 `AppMonitorService` / `ClaudeSessionService` 在状态变化时 feed（publish），供面板"统一事件列表"等未来 UI 用；本期可不接 UI，或只接一个只读列表。
  - **统一两处 merge 逻辑**：`publishClaudeEvents` 复用 `publish(events:)`，避免两份实现漂移。
- 判定：**badge 计数不变**（不双算）；引擎事件流口径与现有一致（IM + 外部 approval + 外部 error）；无回归。
- 禁止：让引擎与 `computedState` 同时驱动 badge（双算根源）；改降噪/分流/声音语义。
- 若发现引擎当前**根本没接线**（dead code）→ 标注，二选一：本期接成旁路只读，或移除留待专门特性。

## I. 窗口拖拽吸附 — `WindowSnapService.swift`（已存在）+ `PreferencesView.swift` + `AppDelegate.swift`
- 现状重大风险：`addGlobalMonitorForEvents(.leftMouseDragged)` 对**任何**左拖都触发吸附前台窗口（选字/拖文件/拖滑块都会误吸）。
- 实现要求：
  - **加开关**：`@AppStorage("windowSnapEnabled") = false`（**默认关**）；AppDelegate 据此 `start()`/`stop()`；偏好里可开。
  - **降低误吸**：仅当拖拽确实在移动窗口时吸附——可行近似：吸附前校验"前台窗口在过去 ~100ms 内 frame 有位移"（用 AX/CGWindow 读窗口 frame 变化），或至少要求鼠标在边缘区**持续**而非瞬时；并保留 1s 冷却（已有）。
  - 吸附后给轻反馈（可选）。
- 判定：默认关闭无副作用；开启后拖窗到边缘吸附、冷却生效；**非窗口拖拽不误吸**（或在 UI 明确标注该限制为已知边界）。
- 禁止：默认开启全局拖拽吸附（太打扰 + 误吸）。

---

## 🚫 全局禁止项
- 不引第三方库；不触发 Apple Developer 账号（不加 Developer ID/公证）。
- 不回归：claude-tab-monitor、workspace-ux-polish、diff-drawer。
- 不改"内部/外部分流 + 声音分级 + badge 降噪"既定语义。

## ✅ 完成判定（总）
- [ ] 9 项各自验收点达成（见上）。
- [ ] `swift build` 通过。
- [ ] badge 计数未被通知引擎双算（H 的关键回归点）。
- [ ] 窗口吸附默认关闭，且开启后不误吸非窗口拖拽（I 的关键风险点）。
- [ ] 智能复制气泡：失焦消失 ✓ 且点击仍可复制 ✓（A 的关键约束）。

## 🧠 来自 config 约束
- SwiftTerm：internal API（cellDimension/selection）不可碰；坐标系 flipped 需实测。
- 弱模型易引入 retain cycle / 过度设计 → 严格限定本蓝图文件范围，逐项判定。
