# STATE — 接力棒

> 任何 AI 打开本项目，先读这里的 ENTRY POINT 块，再按角色契约行动。

## 🎯 ENTRY POINT
- **当前阶段** → workspace-ux-polish 三轨已完成、审查通过、已合并到 main
- **执行方** → —（等待下一轮 PM）
- **本侧模型** → strong（见 `.harness-model.local`）
- **PRD** → `docs/PRD-workspace-ux-polish.md`（✅ 已锁定）

### 三轨结果（互不依赖）
| 轨 | 交付物（入口文件） | 状态 |
|----|------|------|
| #1 Dashboard 软化 | `docs/design/workspace-softening-design-brief.md` | ✅ Design AI 产出 + 接线（DesignTokens v5.5 + DESIGN.md + DashboardView） |
| #2 智能复制气泡 | `docs/blueprint-smart-copy.md` | ✅ 实现 + 审查（修复 weak→strong 引用 bug + monitor 去重） |
| #3 拖拽灰底修复 | `docs/blueprint-widget-drag-fix.md` | ✅ 实现 + 审查通过（compositingGroup） |
- 审查报告：`docs/reviews/smart-copy-drag-fix-2026-06-18.md`

## 📌 下一轮待办（backlog — 用户指定）
1. **悬浮窗外部通知降噪（用户 2026-06-18 指定）**：`Claude External` 列表 + 悬浮窗 badge **不要**把"等待输入"(Stop) 计入/展示，**只保留需要用户操作的动作**（审批 / 出错）。
   - 落点：`FloatingWidgetContainer.computedState`（badge 计数）+ 面板 `Claude External` 列表（`PanelView`/`NotificationListView`）都要过滤掉 `.stopped` 类型，只留 approval + `.error`。
   - 现状：上一轮只在 `syncToasts` 过滤了外部 toast，badge 与面板列表仍统计 `.stopped` → 截图里外部两条"会话等待输入"仍占了 badge(6) 和列表。
2. **智能复制气泡失焦消失**：本轮故意未加 `resignFirstResponder` dismiss（怕在点气泡触发 onTap 前就移除气泡）。下一轮用更安全的钩子（如 windowDidResignKey / pane isSelected 变化）实现切 Tab/失焦消气泡。

## 📋 流程状态（当前特性：workspace-ux-polish）
| # | 阶段 | 状态 |
|---|------|------|
| 1 | PM — PRD | ✅ 已锁定 |
| 2 | Designer — 软化简报（#1） | ✅ 简报已出，待 Design AI 实现 |
| 3 | Blueprint — #2 / #3 | ✅ 两份蓝图已出（Confirmed） |
| 4 | Executor — 实现 | ⏳ 三轨并行中 |
| 5 | Reviewer — 审查 | ⬜ |
| 6 | QA — 验收 | ⬜ |

---
## 📦 已完成特性归档
### claude-tab-monitor（2026-06-10 ✅ 审查通过）
多终端 Claude 状态监控 + 悬浮窗降噪。报告：`docs/reviews/claude-tab-monitor-2026-06-10.md`。代码改动未提交。

## 📝 流程日志
- 2026-06-10 引入 harness 脚手架；标记本侧为强模型；补 `.harness-config.yaml`。
- 2026-06-10 完成 v1.3 进度 review，结论：不推倒重来，做增量。
- 2026-06-10 PM 与用户对齐五态分级 + 内外分流；`docs/PRD-claude-tab-monitor.md` 已锁定。
- 2026-06-10 产出 `docs/blueprint-claude-tab-monitor.md`（4 文件改动 + 侵入评估）。
- 2026-06-10 蓝图已确认（含降噪分流决策），交接弱模型实现。
- 2026-06-10 弱模型完成 4 文件实现；强模型审查通过（9/9 判定项，编译过），见 `docs/reviews/claude-tab-monitor-2026-06-10.md`。
- 2026-06-10 新特性 workspace-ux-polish：PRD 锁定；核实 SwiftTerm 选区接口（getSelection/selectionActive public、cellDimension internal）；同时产出 #1 设计简报 + #2/#3 两份蓝图，三轨并行分发。
- 2026-06-10 #3 拖拽灰底修复：`FloatingWidgetView.swift` 加 `.compositingGroup()`，编译过。
- 2026-06-10 #2 智能复制气泡：`NarcTerminalView` 翻转为 ⌘⇧C 智能复制 + 选区气泡；新建 `SmartCopyBubble.swift`；移除 `DashboardView` 智能粘贴提示条。`mouseUp`/`resignFirstResponder` 不能重写（SwiftTerm 未标记 open），改用 `NSEvent.addLocalMonitorForEvents` 捕获鼠标位置。编译过。

## 🎯 当前特性
`workspace-ux-polish` — Dashboard 软化 + 智能复制气泡 + 拖拽灰底修复
