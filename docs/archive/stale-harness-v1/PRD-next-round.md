# PRD: 下一轮（Tab Chrome 拖拽 + TUI 内容区滚轮 + 通知引擎收尾）

> 范围严格收敛到 3 项。**不要**实现 backlog 里其他条目（包括拖拽吸附深层修复）。

---

## ① Tab Chrome-like 拖拽
**现状痛点（用户原话）**："拖拽识别区域有点小；拖拽预览变成一个小胶囊；我希望整个 Tab 跟随鼠标，原位变透明留间隙——参考 Chrome。"

**目标**：把 Tab 拖拽改造成 Chrome 风格——整行可拖、原 Tab 在原位变透明留间隙、被拖那个 Tab **同尺寸跟随鼠标**、放下时其他 Tab 让位插入。

**验收**：
1. **整行**任意位置（除内嵌按钮 ✕ / ⚠️ / 铅笔）按住即可拖，识别区域 ≥ 整行 90%。
2. 拖拽中，被拖 Tab **在列表里变透明（opacity≈0.25）保留占位**，不直接抽掉造成跳跃。
3. 拖拽预览 = **同宽同高的 Tab 行副本**（不是小胶囊），跟随鼠标移动。
4. 鼠标拖过别的 Tab 时，其他 Tab 平滑让位，**实时显示插入位置**（光标处空出一行高度的间隙）。
5. 松手到任意位置完成重排；松手到列表外取消（恢复原位）。
6. 重排过程**不重建任何 PTY**（claude 状态、选中态保持）。

**排除**：跨窗口拖出（Chrome 是分离成新窗口，本期不做）；多选拖拽。

---

## ② alternate-screen TUI 内容区滚轮（让 claude 里能滚）
**现状**：claude/vim/less 等 TUI 在 alternate screen 模式下，输出不进 scrollback——滚轮无效（这是标准行为）。

**目标**：在 alternate screen 状态下，把滚轮事件作为终端鼠标滚轮事件发给 TUI，让 claude 自己滚动内容展示区。禁止把滚轮转译成 ↑/↓ 键，因为 ↑/↓ 属于输入区历史回溯，会复现“想滚内容却切换输入历史”的旧 bug。

**验收**：
1. 在 claude TUI 里滚轮 → claude 的内容展示区能上下滚动（由 claude 内部处理鼠标滚轮）。
2. 普通 shell（非 alternate screen）滚轮行为**完全不变**（仍滚 NARC scrollback）。
3. 滚动速度合理：滚轮 deltaY 映射为有限次数的 mouse wheel 事件。
4. **可在偏好里开关**，默认 ON（与 iTerm 默认一致）。

**排除**：横向滚动转译；键盘 ↑/↓ 转译；任何会影响输入区历史的方案。

---

## ③ 通知引擎死代码处理
**现状**：`NotificationEngine.shared` 被 `AppMonitorService` / `ClaudeSessionService` publish 但**无消费者**（`computedState` 用 `appMonitor.totalBadgeCount` 直读，未读引擎）。属死代码。两份 merge 逻辑也漂移。

**目标**：二选一——**接通**或**移除**。本 PRD 选择**移除**（更简单、零回归风险；未来真需要时再设计）。

**验收**：
1. 删除 `NotificationEngine.swift`。
2. 移除 `AppMonitorService` / `ClaudeSessionService` 中对 `NotificationEngine.shared.publishXXX` 的调用。
3. `swift build` 通过；badge 计数与现状完全一致（仍由 `computedState` 主导）；外部 IM/Claude 通知行为无变化。

**排除**：替换设计、加新订阅者、改 badge 数据源。

---

# Blueprint

## ① Tab Chrome 拖拽 — `DashboardView.swift` + `TerminalSessionManager.swift`

**核心思路**：弃用 SwiftUI 4 `.draggable/.dropDestination`（不够灵活，无法做"原位透明 + 同尺寸预览"），改用 **DragGesture + Manager 持有 `draggingId` / `draggingOffset` / `dropTargetIndex` 状态**，纯 SwiftUI 自渲染。

### `TerminalSessionManager.swift`（修改）
新增 `@Published` 状态：
```swift
@Published var draggingSessionId: UUID? = nil
@Published var draggingTranslation: CGSize = .zero
@Published var dropTargetIndex: Int? = nil       // 插入到哪个 index 之前

func beginDrag(_ id: UUID) { draggingSessionId = id; draggingTranslation = .zero }
func updateDrag(translation: CGSize, targetIndex: Int?) {
    draggingTranslation = translation
    dropTargetIndex = targetIndex
}
func endDrag(commit: Bool) {
    if commit, let id = draggingSessionId, let target = dropTargetIndex,
       let from = sessions.firstIndex(where: { $0.id == id }) {
        let adjusted = from < target ? target - 1 : target
        if adjusted != from {
            let s = sessions.remove(at: from)
            sessions.insert(s, at: adjusted)
        }
    }
    draggingSessionId = nil; draggingTranslation = .zero; dropTargetIndex = nil
}
```

### `DashboardView.swift` 左栏（修改 `leftColumn`）
- 用 `ScrollView` + `VStack(spacing:0)` + `ForEach`。每个 row 计算自己的几何（用 `GeometryReader` 在外层量一个固定 rowHeight，比如 56pt；不要每行 GeometryReader）。
- 每个 row 加 `.gesture(DragGesture(minimumDistance: 4).onChanged/.onEnded)`：
  - `.onChanged`：① 首次进入调 `beginDrag(session.id)` ② 算 `targetIndex = clamp(round((rowIndex * rowHeight + value.translation.height) / rowHeight))` ③ `updateDrag(...)`。
  - `.onEnded`：调 `endDrag(commit: true)`；若 translation 极小（< 4pt）按点击处理（保持 onTap 行为）。
- 每个 row 的渲染：
  - 若 `session.id == draggingSessionId`：**opacity=0.25**，**位置不动**（原位透明占位）。
  - 同时在 `ZStack` 顶层渲染一个"漂浮副本"（同 row 视图），偏移 `draggingTranslation`，opacity=0.92，加 `softShadow("lg")`。漂浮副本只在 `draggingSessionId != nil` 时存在。
- 让位动画：用 `.offset` 给非拖拽 row 一个 y 偏移：当 `dropTargetIndex` 在该 row 上方时不偏移，在下方时偏移 0；插入点处的 row 整体下移 `rowHeight` 形成空隙。配 `.animation(.narcSnap, value: dropTargetIndex)`。

**关键约束**：
- `DragGesture` 的 `minimumDistance: 4`——低于此走 `.onTapGesture`（确保点击切换 Tab 仍工作）。
- ✕ / ⚠️ / 铅笔 按钮：用 `.highPriorityGesture` 或在 Button 上加 `.simultaneousGesture(DragGesture().onChanged{ _ in })` 阻断父手势，避免按按钮触发拖拽。
- rowHeight 必须**固定**（不要随 claude 状态变化），否则插入位置算错。
- 拖到 ScrollView 外 → `endDrag(commit: false)` 取消。
- PTY 不重建：`OwnedSession.id` 不变，ZStack 里 pane 永远存在。

### 文件清单
| 文件 | 改动 |
|------|------|
| `TerminalSessionManager.swift` | 新增 3 个 `@Published` 拖拽状态 + 3 个方法 |
| `DashboardView.swift` | `leftColumn` 重写 + 新增 `floatingDragPreview` view |

---

## ② TUI 内容区滚轮 — `TerminalPaneView.swift`

**SwiftTerm API**（已验证 public）：
- `terminal.isCurrentBufferAlternate: Bool`（`MacTerminalView.terminal` → `Terminal` 实例的属性）
- `terminal.mouseMode: MouseMode`（判断 TUI 是否启用鼠标上报）
- `terminal.sendEvent(buttonFlags:x:y:pixelX:pixelY:)`（发送鼠标滚轮事件）

### `NarcTerminalView`（修改）
在 scroll-wheel monitor 里分流：
```swift
if terminal.isCurrentBufferAlternate, terminal.mouseMode != .off {
    let button = event.deltaY > 0 ? 64 : 65   // xterm wheel up/down
    terminal.sendEvent(buttonFlags: button, x: col, y: row, pixelX: px, pixelY: py)
} else {
    scrollWheel(with: event)                  // 普通 shell → SwiftTerm scrollback
}
```

实现备注：
- 坐标可用 view bounds + `terminal.getDims()` 近似换算到 grid/pixel 坐标；不要碰 SwiftTerm `internal` 的 `cellDimension`。
- 如果 `mouseMode == .off`，不要退化为 ↑/↓。alternate buffer 本身无 scrollback，这是上游终端行为，需要另起 transcript 设计才能彻底解决。

### `PreferencesView.swift`（可选）
如果加开关，文案必须明确是“内容区鼠标滚轮”，不是“上下键翻页”：
```swift
@AppStorage("tuiContentWheelForwarding") private var tuiContentWheelForwarding: Bool = true
Toggle("Claude/TUI 内容区接收鼠标滚轮", isOn: $tuiContentWheelForwarding)
```

### 文件清单
| 文件 | 改动 |
|------|------|
| `TerminalPaneView.swift` | `NarcTerminalView` scroll monitor 分流 alternate-screen mouse wheel |
| `PreferencesView.swift` | 可选：加一个 `@AppStorage` + Toggle |

**禁止**：
- 不要把滚轮转译成 ANSI `\x1B[A` / `\x1B[B` 或 keyCode ↑/↓。
- 不要在普通 shell（非 alternate screen）下改变 scrollback 行为。
- 不要在 `mouseMode == .off` 时伪造键盘事件。

---

## ③ 通知引擎移除

### 删除
- `NARC/Sources/Services/NotificationEngine.swift`（整个文件）

### 修改调用点
- `NARC/Sources/Services/AppMonitorService.swift` 第 233 行附近：删 `NotificationEngine.shared.publishIMEvents(...)` 调用。
- `NARC/Sources/Services/ClaudeSessionService.swift` 第 57 行附近：删 `NotificationEngine.shared.publishClaudeEvents(...)` 调用。

### 验证
- `grep -rn "NotificationEngine" NARC/` 应零命中。
- `swift build` 通过。
- 跑一次 app：badge / IM 监控 / Claude 事件**完全无变化**。

---

# 🚫 全局禁止项（DeepSeek 必读）
- **本轮只做上面 3 项**。不许把 backlog 其他项（拖拽吸附深层修复、Developer ID 签名、Sparkle 自动更新等）一并实现——上一轮你过度设计被审查记录在案。
- 不引入第三方库；不触发 Apple Developer 账号需求。
- 不改：claude 状态分级、降噪规则、智能复制、diff-drawer、悬浮窗拖拽修复、设计 token。
- 不改 `FloatingWidgetContainer.computedState` 的 badge 计算口径。
- Tab 拖拽**不能重建 PTY**（重排只动 `sessions` 数组顺序，不调 `remove` + `newSession`）。

# ✅ 完成判定
- [ ] Tab 拖拽：整行可拖，原位透明留间隙，同尺寸预览跟随鼠标，其他 Tab 让位实时预览，松手完成重排，PTY 不重建。点击 Tab 切换仍正常；点 ✕/⚠️/铅笔 不触发拖拽。
- [ ] TUI 内容区滚轮：claude 里滚轮能让 claude 内容展示区滚动；普通 shell 滚轮行为不变；偏好里有开关，默认 ON。
- [ ] 通知引擎：源文件已删，调用点已清，grep 零命中，编译通过，行为无变化。
- [ ] `swift build` 通过。
- [ ] 无回归：智能复制、diff-drawer、降噪规则、状态分级、悬浮窗拖拽。

# 🧠 来自 config 约束（再次提醒 DeepSeek）
- SwiftTerm `internal` API 不可碰（`cellDimension`、`selection.start/end`）；本轮用到的 `isCurrentBufferAlternate` / `send(_:)` 都是 public，已验证。
- 弱模型常见坑：retain cycle、过度设计、`.onMove` 误用（已知不工作）。
