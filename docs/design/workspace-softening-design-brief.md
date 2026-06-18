# Dashboard 软化 设计简报
- 对应 PRD: docs/PRD-workspace-ux-polish.md（#1）
- 交付对象: NARC Design AI（产出 SwiftUI 到 `design-handoff/`，接线遵循 DESIGN-COLLABORATION.md）
- 版本: v1 / 2026-06-10

## 📌 一句话需求
把 NARC Workspace Dashboard 从"简单直角圆角"的廉价观感，软化成**圆润、优雅、有分层呼吸感**的视觉——**不动布局骨架与交互逻辑**。

## 🎯 业务背景
- 用户是 Dashboard 的高频使用者（多终端并行跑 Claude），长时间盯着它。
- 现状视觉是生硬的等半径圆角 + 单层/无阴影 + 偏紧的间距，"能用但不耐看"。
- 不解决：用户明确表达"风格上我不喜欢"，影响长期使用愉悦度。

## 👤 用户旅程（设计师必读，逐屏感受）
当前 Dashboard 结构（**保持不变**，只软化每块的视觉）：
1. **顶部 toolbar**：`terminal.fill` 图标 + "NARC Workspace · N 个终端" + 右侧"新建终端"胶囊按钮。（注意：右上角原"智能粘贴"提示条会在 #2 里移除，简报不必为它设计。）
2. **左列 tab 列表**（`TerminalTabRow`）：每行 = 状态点 + 标题 + cwd/时间 meta + claude 状态徽标；选中态有背景高亮；needs-attention 有左侧竖红条 + 红底；hover 出铅笔/✕。
3. **中间分隔**：`HSplitView` 的拖拽分隔线。
4. **右列**：当前选中终端的实时画面（终端内容本身不改）。
5. **空状态**：居中 `terminal.fill` 大图标 + "还没有终端" + 新建按钮。

## 🎨 设计需要回答的问题（请设计师拍板）
1. **圆角**：是否统一改为**连续曲率（squircle / continuous corner）**？各层级半径阶梯怎么定（toolbar 按钮 / tab 行 / 卡片 / 分隔区）？
2. **阴影/分层**：选中 tab、hover、卡片用几层柔和阴影表达深度？还是用材质（`.regularMaterial`/`.thinMaterial`）+ 细描边表达，避免重阴影？
3. **留白**：行高、行内间距、列内边距怎么放大才"舒展但不松散"？（现用 `NarcSpacing` 4/8 阶）
4. **分隔线**：tab 间 `Divider` 是否换成更精细的 hairline / 渐隐分隔 / 干脆用间距替代？
5. **选中态**：当前是 `narcAccent.opacity(0.18)` 纯色块。是否改为更柔和的圆角胶囊高亮 + 左侧 accent 指示？
6. **needs-attention 红态**与软化风格如何协调（既要醒目又不破坏整体优雅）？

## 📐 已知约束
- **技术约束**：SwiftUI + AppKit；Token 以 `Sources/Design/DesignTokens.swift` 为准，**Design 拥有 Token 定义权**（可新增/调整 `NarcRadius`/`NarcSpacing`/阴影/材质 token，但要在产出里同步改 token 定义）。
- **不动**：布局骨架（toolbar / HSplitView / 左 tab 右 pane）、所有交互逻辑、claude 状态徽标的语义与配色分级（蓝=工作/绿=待输入/红=审批/灰=结束，上一轮刚定，不要改语义）。
- **必须覆盖的状态**：tab 默认 / hover / 选中 / needs-attention 红态 / claude 各状态徽标 / 空状态。缺一不可。
- **可复用资产**：现有 `DesignTokens.swift`、`FloatingWidgetView`（spec-D，已是软化风格，可作整体调性参照）。
- **产出后**：必须 `swift build` 通过，保持上述功能无回归。

## 🔗 参考案例
- 项目内 `FloatingWidgetView`（halo/材质/柔和阴影）——已落地的"优雅"基准，Dashboard 向它的调性靠拢。
- macOS 系统 App 侧边栏（Finder / 邮件）的选中胶囊 + hairline 分隔，可作连续曲率 + 材质参照。

## ⏰ 时间预期
- 期望初稿：尽快（与 #2/#3 并行）
- 评审：产出 `design-handoff/` SwiftUI 后，由强模型先编译验证 → 再接线 → 功能回归。
