# Blueprint: Workspace 多终端 Claude 状态监控 + 悬浮窗降噪
- 对应 PRD: docs/PRD-claude-tab-monitor.md
- 蓝图状态: Confirmed（2026-06-10 用户确认，含降噪按"是否需动手"分流的决策）
- 目标执行方: 🔵 弱模型
- 技术栈: Swift 5 / SwiftUI + AppKit / SPM（无 DB）

---

## 🗄️ 表结构与侵入评估

### 新增表 / 字段
无数据库。本特性不涉及 DDL。所有状态都是内存态（`@Published`）。

### 🩻 侵入评估（强模型独有职责）

本期是**纯增量改造**，不重写任何 View。四处改动点 + 各自的回滚边界：

1. **`AttentionReason` 枚举扩参**（ClaudeSessionService）——把"审批"和"回答"在路由层分开。
   - 受影响：唯一消费者是 `AppDelegate.onAttentionNeeded`。改枚举必须同步改该 switch，否则编译不过（这是好事，编译器兜底）。
   - 向后兼容：无外部调用方，安全。

2. **悬浮窗降噪策略的关键决策（请用户在 Gate 处确认）**：
   - 现状：`syncToasts()` 给**所有外部事件**（审批/等待输入/出错/卡住）各弹一个常驻 toast，且每个新 toast `NSSound.beep()`。这就是你说的"悬浮窗被等待输入通知填满"的元凶。
   - 面板现状：`PanelView` 只有 `NotificationListView`（IM + pinned），**没有**外部 Claude 列表（`ClaudeSessionListView` 写了但未接线）。所以"外部 Claude"目前唯一可见出口 = toast 栈 + 悬浮窗 badge 数字。
   - **决策**：若简单"全部停弹 toast"，外部等待中的会话会只剩一个数字、点开无列表 → 变成看不见。代价过大。
   - **采用方案**：按"是否需要你动手"分流——
     - 外部 **等待输入(Stop) / 卡住(stale)** → **不再弹 toast、不响声、不发系统通知**，仅计入悬浮窗 badge 数字。**（正好消灭你抱怨的填满源）**
     - 外部 **审批 / 回答 / 出错** → 仍弹 toast（这些需要你动手，是有效信息），但**去掉 beep**（声音只留给"回答"态，见下）。
   - 这样"逐条弹"被收敛到**仅操作性事件**，非操作性的等待/卡住彻底安静。既降噪又不孤立外部会话。
   - 回滚：纯逻辑过滤，去掉 `where` 子句即恢复原状。

3. **结束态固化**（TerminalSessionManager）——`ClaudeSessionService` 在会话 `ended` 后 5s 删除该 session，导致 Tab 的 `claude` 被 `applyClaudeUpdates` 抹成 `nil`，"已结束"徽标消失。改为：service 删除后**冻结**最后的 ended 快照。
   - 受影响：仅 `applyClaudeUpdates` 内部。
   - 回滚：去掉冻结分支即恢复。

4. **声音分级**（AppDelegate）——声音从"每个外部 toast 都 beep"改为"**仅`回答`态(interactive)响一次，按会话 5s 去重**"。
   - 受影响：`syncToasts` 去 beep + `onAttentionNeeded` 加 `playAnswerSound`。

---

## 🗂️ 文件级实现规划

### `NARC/Sources/Services/ClaudeSessionService.swift`（修改）
- 职责：在路由层区分"审批(高风险工具)"与"回答(阻塞型提问)"。

**改动 1 — `AttentionReason` 枚举加 payload**（当前在 41–46 行）：
```swift
enum AttentionReason {
    case permissionRequest(narcSessionId: String?)      // 审批：Bash/Edit/Write 等
    case interactiveQuestion(sessionId: String, narcSessionId: String?)  // 回答：AskUserQuestion/Elicitation
    case stopped(sessionId: String)
    case error(sessionId: String, message: String?)
    case stale(sessionId: String)
}
```

**改动 2 — `handleClient` 的 `PermissionRequest` case**（当前 199–216 行）：用 `approval.isPermissionRequest` 分流（该计算属性已存在，interactive 工具列表 = `["AskUserQuestion","Elicitation","SendUserMessage"]`）：
```swift
case "PermissionRequest":
    let context = json["context"] as? String
    let approval = PendingApproval(/* 字段不变 */)
    DispatchQueue.main.async { [weak self] in
        self?.pendingApprovals.append(approval)
        if approval.isPermissionRequest {
            self?.onAttentionNeeded?(.permissionRequest(narcSessionId: narcSessionId))
        } else {
            self?.onAttentionNeeded?(.interactiveQuestion(sessionId: sessionId, narcSessionId: narcSessionId))
        }
    }
    return
```

| 函数 | 入参 | 出参 | 边界 |
|------|------|------|------|
| `handleClient(_:)` | `clientSocket: Int32` | `Void` | 仅改 PermissionRequest 分支；其余 case 不动 |

- 依赖：`PendingApproval.isPermissionRequest`（已存在，**不要改它的工具列表**）。

---

### `NARC/Sources/App/AppDelegate.swift`（修改）
- 职责：按状态分级落地"提示强度"，并执行悬浮窗降噪。

**改动 1 — `onAttentionNeeded` switch**（当前 69–89 行）整体替换为：
```swift
claudeService.onAttentionNeeded = { [weak self] reason in
    guard let self = self else { return }
    switch reason {
    case .permissionRequest:
        // 审批：内部→侧边栏 ⚠️ popover 处理；外部→syncToasts 弹 toast。
        // 两者都不发系统通知、不响声（降噪）。此处无需额外动作。
        break
    case .interactiveQuestion(let sessionId, _):
        // 回答：中等强度 = 响一声（按会话去重）。内外一致。
        self.playAnswerSound(for: sessionId)
    case .stopped:
        // 等待输入：弱提示。内部→侧边栏静默点；外部→仅 badge 计数。
        // 不发系统通知、不弹 toast、不响声。
        break
    case .error(let sessionId, _):
        self.postErrorNotification(sessionId: sessionId)   // 出错仍发系统通知
    case .stale:
        break   // 卡住：仅侧边栏体现，不打扰
    }
}
```
> ⚠️ 删除原先对 `postPermissionRequestNotification` / `postStoppedNotification` / `postStaleNotification` 的调用。这三个私有方法若已无其它调用方，一并删除其定义（grep 确认无引用后再删；有引用就只摘调用）。`postErrorNotification` 的签名按现有实际为准，若原来无参就保持无参调用。

**改动 2 — 新增声音方法**（放在 Toast 区附近）：
```swift
/// 仅"回答"态(阻塞型提问)触发的轻音效，按会话 5s 去重，避免连响成噪音。
private var lastAnswerSoundAt: [String: Date] = [:]
private func playAnswerSound(for sessionId: String) {
    let now = Date()
    if let last = lastAnswerSoundAt[sessionId], now.timeIntervalSince(last) < 5 { return }
    lastAnswerSoundAt[sessionId] = now
    (NSSound(named: "Glass") ?? nil)?.play() ?? NSSound.beep()
}
```

**改动 3 — `syncToasts()` 降噪**（当前 493–555 行）：
- 审批循环（499 行）保持 `where approval.narcSessionId == nil`（外部审批/回答仍弹）。
- 通知循环（516 行）改为**只保留外部 error，过滤掉 stopped/stale**：
```swift
for notification in claudeService.notifications.reversed()
    where notification.narcSessionId == nil && notification.type == .error {
    // ……（原 ClaudeToastEvent 构造不变，但 type 必为 .error）
}
```
- **删除 552 行的 `NSSound.beep()`**（声音改由 `playAnswerSound` 统一管理）。

| 函数 | 入参 | 出参 | 边界 |
|------|------|------|------|
| `playAnswerSound(for:)` | `sessionId: String` | `Void` | 同会话 5s 内最多响 1 次 |
| `syncToasts()` | 无 | `Void` | 仅外部 approval + 外部 error 进 toast；stopped/stale 不进 |

- 依赖：`FloatingWidgetContainer.computedState` 仍统计**所有**外部 notifications+approvals → badge 数字不受 toast 过滤影响（**不要改 computedState**）。

---

### `NARC/Sources/Services/TerminalSessionManager.swift`（修改）
- 职责：会话结束后在 Tab 侧冻结"已结束"快照，不被 service 的 5s 清除抹掉。

**改动 — `applyClaudeUpdates(_:)`**（当前 67–92 行）把 `sessions[idx].claude = newClaude` 一行（79 行）替换为冻结逻辑：
```swift
let oldStatus = sessions[idx].claude?.status
let newClaude = byNarcId[key]
// 冻结：service 删除已结束会话后 newClaude 变 nil，但 Tab 要保留"已结束"徽标。
let freezeEnded = (newClaude == nil && oldStatus == .ended)
if !freezeEnded {
    sessions[idx].claude = newClaude
}
let newStatus = sessions[idx].claude?.status
// 未读红点逻辑保持原样（审批/等待输入/结束触发），用 newStatus 比较
if let new = newStatus, new != oldStatus,
   sessions[idx].id != selectedId,
   new == .waitingForApproval || new == .waitingForInput || new == .ended {
    sessions[idx].hasUnseenChange = true
}
```

| 函数 | 入参 | 出参 | 边界 |
|------|------|------|------|
| `applyClaudeUpdates(_:)` | `claudeMap: [String: ClaudeSession]` | `Void` | ended 快照冻结；其余状态正常覆盖 |

- 依赖：`ClaudeStatus.ended`（已存在）。`OwnedSession` 不删除（Tab 保留，用户手动关——已是现状）。

---

### `NARC/Sources/Views/DashboardView.swift`（修改，`TerminalTabRow`）
- 职责：给"运行中/思考中"加**非红点的柔和脉冲**（PRD 验收表第 1 行）。当前运行态已是蓝色徽标+蓝点，仅缺"柔和"动效。

**改动 — 状态点加工作态脉冲**（当前 256–259 行的 status dot）：
```swift
Circle()
    .fill(statusDotColor)
    .frame(width: 8, height: 8)
    .opacity(isWorking ? (workingPulse ? 1.0 : 0.45) : 1.0)
    .animation(isWorking ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : nil,
               value: workingPulse)
    .padding(.top, 5)
    .onAppear { if isWorking { workingPulse = true } }
    .onChange(of: isWorking) { _, w in workingPulse = w }
```
新增两个成员：
```swift
@State private var workingPulse = false
private var isWorking: Bool {
    guard let s = session.claude?.status else { return false }
    return s == .processing || s == .runningTool || s == .compacting
}
```

| piece | 行为 | 边界 |
|-------|------|------|
| status dot | 工作态 0.45↔1.0 呼吸；非工作态恒定 | 不影响 `needsAttention` 的红色 attentionBar（那是审批专用，保持） |

- 依赖：`statusDotColor`（已存在，工作态返回 `.narcAccent` 蓝）。**不改红色 attentionBar / 不给红点加到运行态**。

---

## 🔁 数据流（从 hook 事件到 UI）
1. hook → Unix socket → `ClaudeSessionService.handleClient`。
2. `PermissionRequest` → 看 `approval.isPermissionRequest`：
   - true(审批) → `pendingApprovals` + `.permissionRequest` → 内部走侧边栏 ⚠️ popover / 外部走 toast，**无声**。
   - false(回答) → `pendingApprovals` + `.interactiveQuestion` → `playAnswerSound`（响一声）+ 侧边栏高亮 / 外部 toast。
3. `Stop` → `notifications`(.stopped) + `.stopped` → 内部仅侧边栏静默点；外部仅 badge 计数（**不弹 toast、不响**）。
4. `StopFailure` → `.error` → 系统通知 + 外部 toast。
5. `SessionEnd`(status=ended) → `sessions[id].status=.ended` → 5s 后 service 删除 → `TerminalSessionManager` 冻结快照 → Tab 灰显"已结束"保留。
6. `PreToolUse/processing` → Tab status dot 蓝色柔和脉冲。

## 🚫 禁止项清单
- ❌ 不改 `PendingApproval.isPermissionRequest` 的工具列表（审批/回答的判定源）。
- ❌ 不改 `FloatingWidgetContainer.computedState`（badge 仍要统计全部外部事件）。
- ❌ 不重写任何 View 的视觉（颜色/圆角/字体走 DesignTokens，保持现状）。
- ❌ 不给"运行中/思考中"加红点或红色 attentionBar（只能蓝色柔和脉冲）。
- ❌ 不把声音绑到 `.stopped`/`.stale`/`.permissionRequest`——声音**只**给 `.interactiveQuestion`。
- ❌ 不新增第三方库；声音只用系统 `NSSound`。
- ❌ 不做 Tab 拖拽排序、跨重启持久化、Dock 弹跳、审批自动呼出窗口（PRD 明确排除）。
- ❌ 不删除已结束的 `OwnedSession`（Tab 保留待用户手动关）。

## ✅ 实现完成的判定（对照 PRD 验收）
- [ ] 左侧 Tab 新建/关闭/重命名/切换/cwd 显示无回归。
- [ ] 审批(Bash/Edit/Write)：内部在 Tab ⚠️ popover 内联 Allow/Deny，无需切 Tab，**无声**。
- [ ] 回答(AskUserQuestion/Elicitation)：触发**一次**轻音效（同会话 5s 不重复），侧边栏高亮。
- [ ] 等待输入(Stop)：内部仅侧边栏静默点；外部**不弹 toast、不响、不发系统通知**。
- [ ] 运行中：Tab 状态点蓝色**柔和脉冲**，无红点。
- [ ] 已结束：service 5s 删除后 Tab 仍灰显"已结束"，未消失。
- [ ] 降噪硬指标：3 内部 + 2 外部全部进入等待时，悬浮窗 badge = **2**，且屏幕上**无任何**等待输入 toast。
- [ ] 外部审批/出错仍弹 toast（可 Allow/Deny/Jump），未被误杀。
- [ ] 全程编译通过（`swift build` 或 `make build`）。

## 🧠 来自 Brain 的相关约束
- `brain-search.sh "通知 降噪 NSSound 状态机"` 无命中；本次无 Brain 相关硬约束。
