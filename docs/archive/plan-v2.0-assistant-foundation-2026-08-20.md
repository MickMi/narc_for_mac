> 🧭 状态：已归档 | 进度 19/20 | 当前归属：已完成 | 最近卡点：第 20 步真实 UI 验收由 2026-08-20 的产品转向计划接管

# Plan: NARC v2.0 个人 AI 助手基础

## 目标
让用户通过 NARC 快速捕获 Todo 与 Note，并以可扩展的内置模块契约承载个人助手能力，同时保持现有 Workspace、通知与窗口工具的行为不变。

## 约束
- 保留现有 Workspace 的整体设计、入口和终端能力；本计划不删除、不降级、不重构 Workspace。
- 继续使用 Swift 5.9、SwiftUI + AppKit、macOS 14 和现有 SPM 结构，不新增第三方依赖。
- 第一阶段采用编译期内置模块，不加载外部 Swift Bundle、不开放第三方动态代码执行。
- 第一阶段不接入 OpenAI、Claude 或其他外部模型；捕获类型由用户明确选择，AI 分类与自然语言编排进入后续版本。
- Todo 与 Note 数据使用版本化 Codable JSON，写入 Application Support；不得用 UserDefaults 保存正文或待办集合。
- 所有持久化写入必须原子化；损坏或不可解码的数据不得被空数据静默覆盖，错误必须进入可观察状态。
- Quick Capture 与 Assistant Hub 复用现有 `DesignTokens.swift` 和窗口样式，不引入新的视觉语言。
- 不清理、覆盖或回滚当前工作树中的既有修改；每一步只触碰计划列出的单个文件。
- 新增全局快捷键不得改变现有 `⌃⌥N`、`⌃⌥W`、`⌃⌥P` 和窗口布局快捷键。

## Preflight
- 当前分支：`main`，与 `origin/main` 同步；工作树已有 21 个已跟踪改动和 12 个未跟踪入口。
- 工具链：项目声明 Swift 5.9 / macOS 14；本机实测 Swift 6.3.3 / Xcode 26.6，必须保持 Swift 5 语言兼容。
- 测试基线：`swift test --package-path /Users/mickmi/narc_for_mac --scratch-path <tmp> --disable-sandbox` exit 0，5/5 通过；既有 `NotificationListView.swift:106` 弃用警告不属于本计划。
- 真实状态源：Todo/Note 以 `AssistantStore` 发布状态及 Application Support JSON 为准，Toast 或按钮文案不作为保存成功证据。
- 回滚：新增文件可按本计划文件清单移除；现有文件只回滚本计划的局部接线，不碰用户既有 diff；已创建的用户数据不自动删除。

## 文件级 API 契约
- `AssistantModels.swift`：定义 `CaptureKind`、`TodoItem`、`NoteItem`、`AssistantSnapshot`；模型均为 `Codable`、`Identifiable`、`Equatable`，Snapshot 含 `schemaVersion`。
- `AssistantStore.swift`：`@MainActor final class AssistantStore: ObservableObject`；支持注入存储 URL，提供创建/完成 Todo、创建/删除 Note、查询与显式 `lastError`；保存采用原子写入。
- `NARCModule.swift`：定义稳定的内置模块元数据与能力声明，不包含动态加载和文件系统扫描。
- `ModuleRegistry.swift`：持有有序模块列表，拒绝重复 ID，并允许按 ID 查询；默认注册 Assistant、Notifications、Windows、Workspace。
- `QuickCaptureView.swift`：用户显式选择 Todo/Note，空白内容不可提交，保存成功后清空并关闭，失败时保留输入并显示错误。
- `AssistantHubView.swift`：提供 Todo/Notes 两个内置页面和快速新建入口，不复制 Workspace 功能。

## 步骤

- [x] 1. [创建] `docs/PROJECT.md` — 写入稳定项目目标、目标用户、产品边界，以及“Workspace 保留、个人助手成为新增主线”的已确认决策。
  - 已建立 Capture / Recall / Monitor / Act 四层目标，并锁定 Workspace 保留、内置模块优先和外部 AI 延后。
- [x] 2. [创建] `docs/VERSIONS.md` — 记录版本范围规则、v2.0 Goal、带稳定 ID 的 Requirements，以及 v2.1 AI 编排、v2.2 连接器、v3.0 动态插件 Backlog。
  - 已建立 `assistant-001` 至 `assistant-008` 当前需求和后续 AI、连接器、外部插件进入门槛。
- [x] 3. [创建] `docs/design/personal-assistant-design-brief.md` — 约束 Quick Capture、Assistant Hub、Todo/Notes 的状态、入口、反馈和现有设计 Token 复用方式。
  - 已锁定 Quick Capture 六态、Todo/Notes 空态与失败态、键盘路径及现有 Token 复用边界。
- [x] 4. [创建] `NARC/Sources/Models/AssistantModels.swift` — 按 API 契约建立版本化 Todo、Note 与 Snapshot 数据模型。
  - 已建立显式捕获类型、Todo/Note 时间与完成字段，以及 schema version 1 的 Snapshot。
- [x] 5. [创建] `NARC/Sources/Services/AssistantStore.swift` — 实现可注入 URL 的加载、查询和原子持久化，损坏数据进入错误态且不覆盖原文件。
  - 已实现先持久化后发布、原子写入、可注入 URL、显式错误态和加载失败后的写保护。
- [x] 6. [创建] `NARC/Tests/AssistantStoreTests.swift` — 覆盖 Todo/Note 创建、完成、重载持久化、空白拒绝和损坏文件保护。
  - 已覆盖 5 条 Store 路径；损坏文件保持原始字节且后续写入被显式阻止。
- [x] 7. [创建] `NARC/Sources/Modules/NARCModule.swift` — 定义编译期模块描述、展示位置和能力集合。
  - 已建立稳定 ID、显示元数据、展示位置、声明式能力和排序字段；不包含运行时加载能力。
- [x] 8. [创建] `NARC/Sources/Modules/ModuleRegistry.swift` — 实现默认模块注册、稳定排序、按 ID 查询和重复 ID 拒绝。
  - 已默认登记四个内置模块，按 sortOrder/ID 稳定排序，并提供 ID 与展示位置查询。
- [x] 9. [创建] `NARC/Tests/ModuleRegistryTests.swift` — 覆盖默认模块顺序、查找和重复 ID 失败路径。
  - 已覆盖默认顺序、ID/展示位置查询及重复 ID 的显式错误路径。
- [x] 10. [创建] `NARC/Sources/Views/QuickCaptureView.swift` — 实现 Todo/Note 显式选择、输入校验、保存反馈和失败保留。
  - 已实现双态选择、Todo 单行/Note 多行输入、空白防护、错误保留、成功清空和键盘提交/取消。
- [x] 11. [创建] `NARC/Sources/Views/QuickCaptureWindow.swift` — 实现可重复唤起、聚焦输入、保存成功自动隐藏的轻量 AppKit 窗口。
  - 已实现每次唤起重建干净输入态、鼠标屏幕优先定位、可获取键盘焦点及成功/取消/关闭后隐藏。
- [x] 12. [创建] `NARC/Sources/Views/TodoListView.swift` — 实现未完成/已完成展示、完成切换和空状态。
  - 已实现待完成列表、可折叠已完成列表、真实 Store 完成切换、空状态入口和持久化错误反馈。
- [x] 13. [创建] `NARC/Sources/Views/NotesListView.swift` — 实现便签列表、搜索、删除和空状态。
  - 已实现本地搜索、正文截断预览、删除确认、空记录与搜索无结果分态，以及持久化错误反馈。
- [x] 14. [创建] `NARC/Sources/Views/AssistantHubView.swift` — 组合 Todo、Notes 与快速新建入口，复用现有 Token。
  - 已组合 Todo/Notes 双页、实时数量与固定 Quick Capture 入口，未引入 Workspace 或聊天区副本。
- [x] 15. [创建] `NARC/Sources/Views/AssistantHubWindow.swift` — 实现独立 Assistant Hub 窗口及重复唤起行为。
  - 已实现标准可调整窗口、最小尺寸、当前屏幕居中和重复前置，同一 Hub 视图状态可持续使用。
- [x] 16. [修改] `NARC/Sources/Services/HotkeyService.swift` — 在不改变既有映射的前提下注册 Quick Capture 回调和新快捷键。
  - 已新增 `⌃⌥Q` Quick Capture 回调与 ID 103，并同时覆盖正常/无 AX 开发模式；既有映射未改。
- [x] 17. [修改] `NARC/Sources/Views/PanelView.swift` — 在标题区增加 Assistant Hub 与 Quick Capture 入口，保留 Workspace 入口。
  - 已在标题区加入 Quick Capture 与 Assistant 图标按钮，Workspace、偏好设置、关闭按钮和原有两标签均保留。
- [x] 18. [修改] `NARC/Sources/App/AppDelegate.swift` — 组合 Store、Registry 与两个新窗口，接通热键和 Panel 回调，不改变 Workspace 生命周期。
  - 已按需创建共享 Store、内置 Registry、Quick Capture/Assistant Hub 窗口，并接通热键与 Panel；Workspace 回调保持原路径。
- [x] 19. [修改] `docs/FEATURES.md` — 仅按用户可见口径加入 Quick Capture、Todo、Notes 和内置模块状态。
  - 已把四项助手入口列为“需调整/待真实 App 验收”，并明确内置模块与未包含的 AI、连接器、动态插件边界。
- [ ] 20. [运行] `Package.swift` — 运行完整 `swift test` 与 debug build，记录测试数、警告数和 exit code；随后按 Interaction QA 执行真实 App 路径。
  - 自动验证已完成：全量 13/13 测试、独立 Debug build、签名 `.app` 构建与 Harness critical checks 均通过；Interaction QA 因界面工具边界未完成，步骤保持未勾选。

## Interaction QA
- Quick Capture：快捷键打开 → 输入自动聚焦 → Todo/Note 切换 → 空白拒绝 → 保存成功关闭 → 再开状态干净。
- Todo：创建 → 列表出现 → 标记完成 → 重启 App → 完成状态仍在。
- Note：创建 → 搜索命中 → 删除 → 重启 App → 删除结果仍在。
- 保存失败：错误可见、输入保留、原始数据文件不被覆盖。
- 往返兼容：Quick Capture、Assistant Hub、Panel、Workspace 依次开关，现有 `⌃⌥N` 与 `⌃⌥W` 行为不变。

## 禁止项
- 禁止把 Todo/Note 正文写入日志、Harness 事件或 Brain。
- 禁止在本计划中接入模型 API、系统提醒、Apple Notes/Reminders 或云同步。
- 禁止实现第三方动态插件加载、脚本执行、网络插件市场或插件权限系统。
- 禁止借机拆分 `AppDelegate.swift`、`DashboardView.swift` 或清理现有弃用警告。
- 禁止把 UI 已显示或 Toast 已出现当作持久化成功证据。

## 验收标准
- 新增 Store 与 Registry 测试全部通过，原有 5 个测试保持通过。
- Debug build exit 0，未新增编译警告。
- Todo 与 Note 经过 App 重启后仍可读取，损坏数据文件不会被空 Snapshot 覆盖。
- Quick Capture、Assistant Hub 与现有 Panel/Workspace 完成 Interaction QA 五条用户路径。
- `docs/PROJECT.md`、`docs/VERSIONS.md`、`docs/FEATURES.md` 与实现状态一致。
- `harness check .` 关键检查 0 failure；存在的既有警告单独列出，不冒充本计划完成项。

## 停止条件
- 新快捷键与系统或现有快捷键发生实际冲突时，停止步骤 16 并回 Planner 选择映射。
- JSON 存储需要迁移或覆盖已有同名文件时，停止步骤 5 并先给出迁移与备份方案。
- UI 实现需要改变 Workspace 或 Panel 的既有核心行为时，停止相关步骤并回 Planner 裁决。
- 同一错误指纹重复 2 次或任一步骤连续 3 次验证失败时，触发 Anti-Wall Debug Card。

## 阻塞
- Step 20 Interaction QA：Computer Use 不能触发 Carbon 全局快捷键，且 `FloatingWidgetWindow` 是非激活、无可点击 AX 动作的悬浮窗；因此无法从真实入口打开 Quick Capture/Assistant Hub。需用户手动走一次五条路径，或后续增加计划内的可测试入口后再由 Executor 验收。

## 建议
（初始为空。）

## 自检日志

### Step 1 — 2026-08-20 01:16
- files: docs/PROJECT.md, plan.md
- verify: `test -s docs/PROJECT.md && rg -n '<required headings and decisions>' docs/PROJECT.md && git diff --check -- docs/PROJECT.md` passed
- notes: 文档使用 v2.0.0 实际决策日期标题；未修改任何 Swift 文件。

### Step 2 — 2026-08-20 01:18
- files: docs/VERSIONS.md, plan.md
- verify: `test -s docs/VERSIONS.md && rg -n '<version headings and assistant-001..008>' docs/VERSIONS.md && <unique requirement id check> && git diff --check -- docs/VERSIONS.md` passed
- notes: 历史 v1.x 发布证据差异被显式记录；没有修改 README、TODO、Tag 或 App Bundle 版本。

### Step 3 — 2026-08-20 01:19
- files: docs/design/personal-assistant-design-brief.md, plan.md
- verify: `test -s docs/design/personal-assistant-design-brief.md && rg -n '<required interaction sections and states>' docs/design/personal-assistant-design-brief.md && git diff --check -- docs/design/personal-assistant-design-brief.md` passed
- notes: 复用现有 DesignTokens；没有创建外部设计产物，也没有改变 Panel 或 Workspace 布局。

### Step 4 — 2026-08-20 01:20
- files: NARC/Sources/Models/AssistantModels.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Models/AssistantModels.swift` passed
- notes: 模型仅依赖 Foundation；未引入 SwiftData、外部依赖或 UI 字段。

### Step 5 — 2026-08-20 01:21
- files: NARC/Sources/Services/AssistantStore.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Models/AssistantModels.swift NARC/Sources/Services/AssistantStore.swift` passed
- notes: Store 在文件写入成功前不发布新状态；损坏或不支持版本会锁定写入，避免覆盖原数据。

### Step 6 — 2026-08-20 01:24
- files: NARC/Tests/AssistantStoreTests.swift, plan.md
- verify: `swift test --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-assistant-baseline.5Tj2gl --disable-sandbox --filter AssistantStore` exit 0; Swift Testing 5/5 passed; `git diff --check -- NARC/Tests/AssistantStoreTests.swift` exit 0
- notes: 测试只使用唯一的 `/tmp` 目录；未读取或修改真实用户数据。

### Step 7 — 2026-08-20 01:25
- files: NARC/Sources/Modules/NARCModule.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Modules/NARCModule.swift && git diff --check -- NARC/Sources/Modules/NARCModule.swift` exit 0
- notes: 契约只描述编译期内置模块，不扫描文件系统、不加载 Bundle、不执行脚本。

### Step 8 — 2026-08-20 01:26
- files: NARC/Sources/Modules/ModuleRegistry.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Modules/NARCModule.swift NARC/Sources/Modules/ModuleRegistry.swift && git diff --check -- NARC/Sources/Modules/ModuleRegistry.swift` exit 0
- notes: 默认注册 Assistant、Notifications、Windows、Workspace；重复 ID 抛错，不会静默替换模块。

### Step 9 — 2026-08-20 01:27
- files: NARC/Tests/ModuleRegistryTests.swift, plan.md
- verify: `swift test --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-assistant-baseline.5Tj2gl --disable-sandbox --filter ModuleRegistry` exit 0; Swift Testing 3/3 passed; `git diff --check -- NARC/Tests/ModuleRegistryTests.swift` exit 0
- notes: Registry 的排序、查找和重复 ID 失败路径均由可重复测试锁定。

### Step 10 — 2026-08-20 01:28
- files: NARC/Sources/Views/QuickCaptureView.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Design/DesignTokens.swift NARC/Sources/Models/AssistantModels.swift NARC/Sources/Services/AssistantStore.swift NARC/Sources/Views/QuickCaptureView.swift` exit 0; `git diff --check -- NARC/Sources/Views/QuickCaptureView.swift` exit 0
- notes: 视图只使用现有 DesignTokens；保存失败保留输入，成功回调只发生在 Store 原子写入成功之后。

### Step 11 — 2026-08-20 01:29
- files: NARC/Sources/Views/QuickCaptureWindow.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Design/DesignTokens.swift NARC/Sources/Models/AssistantModels.swift NARC/Sources/Services/AssistantStore.swift NARC/Sources/Views/QuickCaptureView.swift NARC/Sources/Views/QuickCaptureWindow.swift` exit 0; `git diff --check -- NARC/Sources/Views/QuickCaptureWindow.swift` exit 0
- notes: 每次 present 重建 SwiftUI 内容以丢弃已取消草稿；本步骤未注册快捷键或修改 AppDelegate。

### Step 12 — 2026-08-20 01:31
- files: NARC/Sources/Views/TodoListView.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Design/DesignTokens.swift NARC/Sources/Models/AssistantModels.swift NARC/Sources/Services/AssistantStore.swift NARC/Sources/Views/TodoListView.swift` exit 0; `git diff --check -- NARC/Sources/Views/TodoListView.swift` exit 0
- notes: 完成按钮不做乐观更新，Store 原子写入失败时原列表状态保持不变并显示错误。

### Step 13 — 2026-08-20 01:32
- files: NARC/Sources/Views/NotesListView.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Design/DesignTokens.swift NARC/Sources/Models/AssistantModels.swift NARC/Sources/Services/AssistantStore.swift NARC/Sources/Views/NotesListView.swift` exit 0; `git diff --check -- NARC/Sources/Views/NotesListView.swift` exit 0
- notes: 删除需二次确认且仅在 Store 保存成功后从列表消失；空数据与搜索无结果使用不同状态。

### Step 14 — 2026-08-20 01:33
- files: NARC/Sources/Views/AssistantHubView.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Design/DesignTokens.swift NARC/Sources/Models/AssistantModels.swift NARC/Sources/Services/AssistantStore.swift NARC/Sources/Views/TodoListView.swift NARC/Sources/Views/NotesListView.swift NARC/Sources/Views/AssistantHubView.swift` exit 0; `git diff --check -- NARC/Sources/Views/AssistantHubView.swift` exit 0
- notes: Hub 只组合 Todo、Notes 与 Quick Capture，不复制 Workspace、通知、窗口管理或未实现的 AI 对话。

### Step 15 — 2026-08-20 01:34
- files: NARC/Sources/Views/AssistantHubWindow.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Design/DesignTokens.swift NARC/Sources/Models/AssistantModels.swift NARC/Sources/Services/AssistantStore.swift NARC/Sources/Views/TodoListView.swift NARC/Sources/Views/NotesListView.swift NARC/Sources/Views/AssistantHubView.swift NARC/Sources/Views/AssistantHubWindow.swift` exit 0; `git diff --check -- NARC/Sources/Views/AssistantHubWindow.swift` exit 0
- notes: Hub 使用独立标准 NSWindow；没有复用或改变 DashboardWindow 的 Workspace 生命周期。

### Step 16 — 2026-08-20 01:35
- files: NARC/Sources/Services/HotkeyService.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-assistant-module-cache -typecheck NARC/Sources/Models/Models.swift NARC/Sources/Services/HotkeyService.swift` exit 0; `git diff --check -- NARC/Sources/Services/HotkeyService.swift` exit 0; internal mapping scan found keyCode 12 / ID 103 only for Quick Capture
- notes: 选择 `⌃⌥Q`，未改 `⌃⌥N/W/P` 或布局键；真实 Carbon 注册状态仍在 Step 20 App 运行时验证。

### Step 17 — 2026-08-20 01:36
- files: NARC/Sources/Views/PanelView.swift, plan.md
- verify: `swift build --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-assistant-baseline.5Tj2gl --disable-sandbox` exit 0; `git diff --check -- NARC/Sources/Views/PanelView.swift` exit 0
- notes: 新按钮使用默认空闭包保持逐步接线可编译；用户既有的 Workspace 按钮与 Panel 两标签改动均被保留。

### Step 18 — 2026-08-20 01:39
- files: NARC/Sources/App/AppDelegate.swift, plan.md
- verify: first build exposed only main-actor isolation errors; after locally isolating new assistant properties/entry methods, `swift build --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-assistant-baseline.5Tj2gl --disable-sandbox` exit 0; `git diff --check -- NARC/Sources/App/AppDelegate.swift` exit 0
- notes: 只给助手对象加局部 `@MainActor`，没有扩大到整个 AppDelegate；既有 `toggleDashboard/showDashboard` 与 Workspace 关闭策略未改。

### Step 19 — 2026-08-20 01:40
- files: docs/FEATURES.md, plan.md
- verify: `test -s docs/FEATURES.md && rg -n '<v2.0 heading, Quick Capture, Assistant Hub, built-in modules, ⌃⌥Q, plugin boundary>' docs/FEATURES.md && git diff --check -- docs/FEATURES.md` exit 0
- notes: 未把待 Interaction QA 的功能提前标成“成熟”，也未把 AI 自动分类、外部连接器或动态插件写成当前能力。

### Step 20（部分）— 2026-08-20 01:58
- files: Package.swift（仅运行验证）, build/NARC.app（构建产物）, plan.md
- verify: fresh `swift test --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-assistant-final.YdLhb6 --disable-sandbox` exit 0, 13/13 passed; independent `swift build` exit 0; `bash scripts/build-app.sh debug` exit 0 and codesign verification passed; `harness check .` exit 0 with 17 pass / 2 warning / 0 failure; all planned-file `git diff --check` exit 0
- notes: 新 `.app` 启动日志确认 `⌃⌥N/W/Q` 三项 Carbon 注册成功；唯一编译警告族仍是基线中的 `NotificationListView.swift:106`。Computer Use 无法触发全局快捷键或点击非激活悬浮窗，未把 Interaction QA 冒充为通过；真实用户数据文件未创建。

## Executor 指导
- 当前工作树包含大量用户既有修改；修改现有文件前必须先读完整文件和当前 diff，只做可定位的局部接线。
- 当前测试基线为 5/5 通过并含一个既有弃用警告族；后续验证必须对比基线，不能把既有警告算作新增问题。
- Workspace 已由用户确认整体设计无问题；本计划只增加 Assistant 能力，不重新讨论或改造 Workspace。
