# PRD: Workspace 多终端 Claude 状态监控 + 悬浮窗降噪

## 📌 需求摘要
- 一句话描述：把"左侧 Tab 管理多个 Claude 终端 + 分级状态提示 + 悬浮窗降噪"三件事收敛到明确、不打扰的产品行为。
- 类型：重构 / 增量打磨（**非推倒重来**，地基沿用 v1.3 的 `OwnedSession` / `TerminalSessionManager` / `ClaudeSessionService` / `FloatingWidgetContainer`）
- 优先级：P0

## 🎯 目标与边界

### 核心目标
让用户能在左侧 Tab 里像管理普通标签页一样管理多个 Claude 终端，并在 Tab 上**按状态分级**实时感知每个会话，**绝不被等待类通知刷屏**。降噪的核心抓手：把"需要我介入"和"它自己在跑"严格分层，把"内部 Tab 会话"和"外部终端会话"分流。

### 核心场景（User Story）
1. **多窗口并行**：我在 4 个 Tab 里各跑一个 Claude。我在 Tab A 工作时，Tab C 触发审批——我**不切走**，直接在侧边栏 Tab C 处弹出的 toast 里 Allow，继续手上的事。
2. **降噪**：我同时还在 iTerm 里跑着 2 个外部 Claude。悬浮窗**只显示一个聚合计数**提醒我"外部有 2 个待处理"，而不是被 6 个会话的等待通知填满。

### 明确排除（不做什么）
- ❌ 不做 Tab 拖拽排序（本期不碰，留给后续）
- ❌ 不做跨**应用重启**的 Tab/会话持久化（现有"关窗保留"够用）
- ❌ 不改外部 Claude 的提示分级——外部一律走"悬浮窗聚合安静入口"，**不**逐条弹 toast / 不响声
- ❌ 不实现 Dock 角标弹跳、不实现"审批时自动呼出窗口"（用户明确未选）
- ❌ 不重写 Design AI 已交付的 View 视觉（保持视觉意图）

### 验收标准（可量化）
1. 左侧 Tab 支持：新建 / 关闭 / 重命名 / 切换 / cwd 自动显示（沿用现有，回归不退化）。
2. **五态分级提示**严格按下表生效，逐条可手测复现：

| Claude 状态 | 触发事件 | 提示形态 | 进悬浮窗? | 声音? |
|---|---|---|---|---|
| 运行中/思考中 | PreToolUse / processing / running_tool | 侧边栏**非红点**柔和指示（脉冲或转圈），常驻该 Tab | 否 | 否 |
| **审批**（高风险工具） | PermissionRequest，tool ∈ {Bash, Edit, Write, …} | 该 Tab 处弹**轻量 toast + 内联展开审批内容**，原地 Allow/Deny，无需切 Tab | 否（内部） | 否 |
| **回答**（阻塞型提问） | PermissionRequest，tool ∈ {AskUserQuestion, Elicitation, SendUserMessage} | **中等强度**：侧边栏 Tab 高亮 + **轻音效**；点击跳到该 Tab 回答 | 否（内部） | ✅ |
| **等待输入** | Stop / SubagentStop | **弱提示**：侧边栏静默标记（小圆点/色块），无声无弹窗 | 否（内部） | 否 |
| **已结束** | SessionEnd / ended | Tab **灰显"已结束"**，保留待手动关闭；shell 若仍活可继续输命令 | 否 | 否 |

3. **悬浮窗降噪**：内部 Tab 会话（`narcSessionId != nil`）**完全不**进入悬浮窗 badge / 不弹悬浮 toast。外部会话（`narcSessionId == nil`）聚合成**单一计数入口**；点击进入外部会话列表。复现实验：开 3 个内部 + 2 个外部并全部进入等待，悬浮窗 badge 应显示 **2**（仅外部），而非 5。
4. 已结束的 Tab 不因 `ClaudeSessionService` 5s 后清除 session 而丢失"已结束"标记。

## 👤 用户旅程
1. 用户在 Dashboard 点"+"或按 `⌃⌥W` 新建 Tab → 默认起 `zsh`，用户敲 `claude` 启动会话。
2. 会话运行 → 该 Tab 显示柔和"运行中"指示（非红点）。
3. 会话触发 PreToolUse 高风险审批 → 侧边栏该 Tab 处弹轻量 toast，内联展开命令/diff，用户原地 Allow/Deny，hook 收到决策继续。
4. 会话抛出 AskUserQuestion → 侧边栏 Tab 高亮 + 响一声轻音效；用户点 Tab 跳过去回答。
5. 会话 Stop 进入纯等待 → 侧边栏静默标记一个点，不打扰。
6. 会话结束 → Tab 灰显"已结束"，用户有空时手动 ✕ 关闭。
7. 同时外部 iTerm 的会话进入等待 → 只反映在悬浮窗聚合计数里。

## ⚙️ 技术约束（用户提到的硬约束）
- 必须复用现有：`OwnedSession.claude` 投影机制、`ClaudeSessionService` 的 `isPermissionRequest` 区分、`FloatingWidgetContainer.computedState` 已有的 internal/external 过滤、`ClaudeToastView` / 内联审批 popover（commit 045e1bc）。
- 视觉以 `Sources/Design/DesignTokens.swift` 为准；不重写 Design AI 产出的 View。
- macOS 原生：声音用系统 `NSSound`（轻音效），不引第三方依赖。

## ⚠️ 风险与依赖
- **已知风险**：
  - 声音提示若绑错状态（给"等待输入"也响）会重新变成噪音源——必须严格只绑"回答"态。
  - "运行中"高频事件若驱动任何会变化的 UI（红点/计数）会回闪——非红点指示也要做节流/稳定态，避免抖动。
  - 已结束 Tab 标记与 `ClaudeSessionService` 5s 清除逻辑存在竞态，需在 Tab 侧固化"已结束"快照，不依赖 service 里还存不存在该 session。
- **依赖项**：narc-hook 正确注入并回传 `narc_session_id`（commit bdad418 已修，需回归验证）；AskUserQuestion/Elicitation 事件确实以 PermissionRequest + 对应 tool 名上报（需在蓝图阶段核对 hook 上报字段）。
- **影响现有功能范围**：`FloatingWidgetContainer`、`TerminalSessionManager.applyClaudeUpdates`、`DashboardView` 侧边栏行、`ClaudeToastView`、`ClaudeSessionService.onAttentionNeeded` 路由。

## 📋 任务粗拆
| # | 任务 | 复杂度 | 归属阶段 |
|---|------|--------|---------|
| 1 | 校准状态机：把 hook 事件 → 五态（运行/审批/回答/等待/结束）的映射在一处定义，区分审批 vs 回答 | 中 | 蓝图→实现 |
| 2 | 侧边栏分级视觉：运行=柔和脉冲(非红点)、审批=toast+内联展开、回答=高亮、等待=静默点、结束=灰显 | 中 | 设计简报→实现 |
| 3 | 声音提示：仅"回答"态触发一次 `NSSound`，做去重(同会话不连响) | 低 | 实现 |
| 4 | 悬浮窗降噪复核：确认内部完全剥离、外部聚合单入口，移除任何内部 toast 泄漏 | 中 | 实现 |
| 5 | Tab 生命周期：会话结束后固化"已结束"快照，不被 service 清除影响；保留 Tab 手动关闭 | 中 | 实现 |
| 6 | 回归：多 Tab 增删改 + 5 内外混合会话降噪场景手测 | 低 | QA |

## 📝 攻防记录
- 挑战 1：诉求 2（监控）与诉求 3（弱化悬浮窗）是否冲突？→ 回应：不冲突，靠"内部走侧边栏、外部走悬浮窗聚合"分流解决，用户确认"内外都常见"故两条路由都保留。
- 挑战 2："提示"是否一刀切？→ 回应：用户明确分三级（审批=内联 toast / 回答=中等+声音 / 等待=弱提示），不一刀切。
- 挑战 3：运行态要不要上侧边栏？→ 回应：要，但用非红点弱指示，避免高频回闪。
- 挑战 4：是否推倒重来？→ 回应：否。v1.3 地基方向正确，本期为边界收敛 + 分级落地的增量。
