# Review: claude-tab-monitor · 2026-06-10

## 📊 结论
- 审查范围：
  - `NARC/Sources/Services/ClaudeSessionService.swift`
  - `NARC/Sources/Services/TerminalSessionManager.swift`
  - `NARC/Sources/App/AppDelegate.swift`
  - `NARC/Sources/Views/DashboardView.swift`
- 蓝图判定项：**9 / 9 通过**
- PRD 验收标准：**8 / 8 覆盖**
- 编译：`swift build` ✅ Build complete (4.33s)，无残留引用
- 结论：**✅ 可合并**

## ✅ 蓝图判定项逐条对照
| 判定项 | 状态 | 证据 |
|--------|------|------|
| Tab 增删改/切换/cwd 无回归 | ✅ | 这些路径未被 diff 触及 |
| 审批：内部 Tab popover Allow/Deny，无需切 Tab，无声 | ✅ | `AppDelegate` `.permissionRequest` → `break`（无声）；popover 逻辑未动 |
| 回答：触发一次轻音效，同会话 5s 去重 | ✅ | `playAnswerSound(for:)` + `lastAnswerSoundAt` 节流；`.interactiveQuestion` 调用 |
| 等待输入：内部侧边栏静默点；外部不弹 toast/不响/不通知 | ✅ | `.stopped` → `break`；`syncToasts` 通知循环加 `&& notification.type == .error` 过滤掉 stopped |
| 运行中：蓝色柔和脉冲，无红点 | ✅ | `DashboardView` `isWorking` + `workingPulse` 0.45↔1.0 呼吸，复用蓝色 `statusDotColor`，未碰红色 attentionBar |
| 已结束：service 5s 删除后 Tab 仍灰显"已结束" | ✅ | `TerminalSessionManager` `freezeEnded` 冻结快照 |
| 降噪硬指标：3 内部+2 外部全等待 → badge=2，无等待 toast | ✅ | `computedState` 未改仍统计全部外部事件（badge=2）；`syncToasts` 过滤后无 stopped toast |
| 外部审批/出错仍弹 toast，未误杀 | ✅ | approval 循环保持 `narcSessionId == nil`；error 经 `type == .error` 保留 |
| 编译通过 | ✅ | Build complete |

## 🚨 必须修复(Must Fix)
无。

## ⚠️ 建议优化(Should Fix)
无。实现与蓝图逐字对齐，被删的 `postPermissionRequestNotification/postStoppedNotification/postStaleNotification` 三方法已确认无残留引用。

## 🚫 禁止项违反检查
- 未改 `PendingApproval.isPermissionRequest` 工具列表 ✅
- 未改 `FloatingWidgetContainer.computedState` ✅
- 无视觉重写（仅加一个透明度动效）✅
- 运行态未加红点/红色 attentionBar（蓝色脉冲）✅
- 声音只绑 `.interactiveQuestion`，未绑 stopped/stale/permissionRequest ✅
- 无第三方库（仅系统 `NSSound`）✅
- 未触碰排除项（拖拽排序/跨重启持久化/Dock 弹跳/审批自动呼出）✅
- 未删除已结束的 `OwnedSession` ✅

## 💡 可选改进(Nice to Have，非本期，记入 backlog)
1. **外部"回答"态 toast 仍显示 Allow/Deny**：外部 `AskUserQuestion/Elicitation` 走 `syncToasts` 的 approval 分支，`presentToast` 因 `approval != nil` 渲染 Allow/Deny 按钮——但对话型工具 Allow/Deny 无语义（侧边栏 popover 已用 `isPermissionRequest` 收敛为"去终端回答"，toast 没有）。属**既有问题**，非本次引入，外部对话型会话也罕见。后续可让 `presentToast` 同样按 `isPermissionRequest` 切换按钮。
2. **手测验证未跑**：本审查为静态对照 + 编译验证。建议运行 app 实测一次"3 内部 + 2 外部全等待 → badge=2 且无 toast"与"回答态响一声"，确认运行时行为与静态判定一致。
