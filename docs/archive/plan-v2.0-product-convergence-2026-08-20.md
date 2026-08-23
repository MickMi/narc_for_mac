> 🧭 状态：已归档 | 进度 20/20 | 当前归属：已完成 | 最近卡点：无

# Plan: NARC v2.0 产品收敛与可靠性修复

## 目标
让 NARC 的主产品入口聚焦个人助手，可靠读取企微多实例 Dock Badge，并让 Dock 与悬浮标记获得一致、视觉居中的品牌表现；Workspace 本版本从所有用户入口软下线但保留底层代码以便回滚。

## v2.0.0 · 2026-08-20 · 产品收敛与可靠性修复

## 约束
- 继续使用 Swift 5.9、SwiftUI + AppKit、macOS 14 和现有 SPM 结构，不新增第三方依赖。
- Workspace 只做软下线：移除入口、快捷键、默认模块登记和可见设置，不删除 `DashboardView`、`DashboardWindow`、`TerminalSessionManager`、`TerminalPaneView`、`ClaudeSessionService` 或 SwiftTerm 依赖。
- 企微 Badge 仍以 macOS LaunchServices `StatusLabel` 为真实状态源；禁止 OCR、读取企微私有数据库或注入企微进程。
- 同一 Bundle ID 的多个 LaunchServices 实例表示同一个应用，Badge 不累加；多个有效数字取最大值，查询失败不得覆盖最后一次有效读数。
- Dock 图标与悬浮标记统一使用大写 `N`，以字形可见边界而不是字体排版框做视觉居中。
- 不清理、覆盖或回滚当前工作树中的既有修改；每一步只触碰计划列出的单个文件。
- 不删除用户数据，不修改 Todo/Note 存储格式，不接入外部模型、连接器或动态插件。

## Preflight
- 当前 macOS 26.5.2、企微 5.0.9；企微存在 3 个 `com.tencent.WeWorkMac` LaunchServices 实例。
- Bundle ID 直查未返回 Badge；逐实例查询中 `ASN:0x0-0x12012` 返回 `"label"="14"`，另外两个实例返回 NULL。
- 当前 NARC 进程来自 `build/NARC.app`；旧计划自动验证为 13/13 tests、Debug build 和签名 app build 通过，真实 UI 验收未完成。
- 当前工作树已有大量未提交改动；所有验证使用独立 scratch path，并以修改前输出为 baseline。
- 回滚：Workspace 底层仍保留，可恢复入口；Badge 读取回退到旧的 Bundle ID 直查；图标由生成脚本可重复重建。

## 文件级 API 契约
- `DockBadgeReader`：允许注入 `lsappinfo` runner；`badgeCount(for:) -> Int?` 先尝试 Bundle ID 直查，失败时枚举同 Bundle ID 的全部 ASN，并返回有效实例 Badge 的最大值；完全不可读返回 `nil`。
- `AppMonitorService`：只在 `DockBadgeReader` 返回有效数字时更新状态；读取失败记录诊断但保留最后一次有效 Badge。
- `ModuleRegistry`：默认只登记 Assistant、Notifications、Windows；Workspace 类型与底层实现继续保留。
- `AppDelegate`：Dock 重开与悬浮窗右键主入口改为 Assistant；Dashboard 生命周期代码保留但不再有用户入口。

## 步骤

- [x] 1. [创建] `NARC/Tests/AppMonitorServiceTests.swift` — 用注入 runner 覆盖 Bundle ID 直查、多 ASN 回退、NULL、多个有效值不累加和完全不可读五条路径，先记录修复前失败基线。
  - 已建立五条纯逻辑回归路径；修复前因 `DockBadgeReader` 尚不存在而按预期编译失败，红灯基线成立。
- [x] 2. [修改] `NARC/Sources/Services/AppMonitorService.swift` — 实现 `DockBadgeReader` 与多实例回退，并在读取失败时保留最后一次有效 Badge。
  - 已实现直查、多 ASN 枚举、有效值取最大及不可读返回 nil；轮询只在有可信值时覆盖现有 Badge。
- [x] 3. [运行] `Package.swift` — 运行 AppMonitor 定向测试，确认步骤 1 从红转绿并记录测试数、警告与 exit code。
  - 正确过滤器实际执行 5/5 测试并全部通过；第一次大写类型名过滤执行 0 条，未被误报为通过。
- [x] 4. [修改] `scripts/generate-icon.swift` — 用 CoreText 字形轮廓的可见边界居中大写 `N`，保持现有尺寸、颜色和 `.icns` 生成流程。
  - 已移除 `0.38` 排版框偏移，按 CoreText 字形轮廓在蓝色背景可见区中精确居中，并成功重建全套图标。
- [x] 5. [修改] `NARC/Sources/Views/FloatingWidgetView.swift` — 将 7.5pt `NARC` 字标替换为与 Dock 一致的大写 `N` 标记，并做可见重心校正。
  - 已改为随 Small/Medium/Large 直径缩放的 Heavy `N`，保留呼吸动画并上移 0.5pt 校正大写字形的可见重心。
- [x] 6. [修改] `NARC/Sources/Modules/ModuleRegistry.swift` — 从默认模块列表移除 Workspace，但保留模块契约能力。
  - 默认 Registry 现只包含 Assistant、Notifications、Windows；`NARCModuleCapability.workspace` 与底层实现未删除。
- [x] 7. [修改] `NARC/Tests/ModuleRegistryTests.swift` — 将默认模块预期更新为 Assistant、Notifications、Windows，并继续覆盖重复 ID。
  - 已锁定三模块顺序、Workspace 查询为空、Standalone 只含 Assistant，并保留重复 ID 失败测试。
- [x] 8. [修改] `NARC/Sources/Services/HotkeyService.swift` — 停止注册 `⌃⌥W` 及 Workspace 回调，保留其他快捷键映射不变。
  - 正常与 no-AX 两条注册路径均已移除 Workspace handler、ID 102 分支和 keyCode 13 注册；其余映射未改。
- [x] 9. [修改] `NARC/Sources/Views/PanelView.swift` — 移除 Workspace 回调参数和标题栏入口，保留 Quick Capture、Assistant、Preferences 与关闭入口。
  - Panel 的公开 API 与标题栏均不再包含 Workspace；Quick Capture、Assistant、Preferences、关闭及原两标签保持不变。
- [x] 10. [修改] `NARC/Sources/Views/PreferencesView.swift` — 隐藏 Workspace 设置页和 `⌃⌥W` 展示，保留底层 `WorkspaceTab` 实现以便回滚。
  - TabView 不再呈现 Workspace，快捷键页不再展示 `⌃⌥W`；原 `WorkspaceTab` 及其配置字段完整保留。
- [x] 11. [修改] `NARC/Sources/App/AppDelegate.swift` — 移除 Workspace 热键/Panel 接线，把 Dock 重开与悬浮窗右键主入口改为 Assistant，并保留 Dashboard 私有生命周期代码。
  - 已切断四类公开入口并统一导向 Assistant；Dashboard 创建、终端会话和关闭策略仍保留且完整构建通过。
- [x] 12. [修改] `docs/design/personal-assistant-design-brief.md` — 记录统一 `N` 标记、Assistant 主入口和 Workspace 软下线后的可见界面边界。
  - 已新增可追踪的 v2.0 入口修订阶段，明确两类 `N`、三档尺寸、右键/Dock/Panel/Preferences 边界与视觉验收。
- [x] 13. [修改] `docs/PROJECT.md` — 更新稳定产品边界：Workspace 从主产品软下线一版，底层保留仅用于回滚。
  - 稳定边界已改为 Assistant 唯一主线，并以可追踪阶段记录 Workspace 软下线、Badge 真实状态和统一 `N` 决策。
- [x] 14. [修改] `docs/VERSIONS.md` — 修订 v2.0 Goal、Requirements 与排除项，加入 Badge 可靠性、统一标记和 Workspace 软下线的稳定需求 ID。
  - v2.0 Goal 已聚焦 Assistant 与真实未读，新增 `assistant-009..011` 并保持版本 `in_progress`，真实交互 `assistant-008` 继续待验收。
- [x] 15. [修改] `docs/FEATURES.md` — 按用户可见状态移除 Workspace 入口并更新应用监控与图标状态，不记录内部删除细节。
  - 当前清单只保留用户可见的 Assistant 主线；Workspace 表格项已移除，Badge、统一 `N` 和新右键入口诚实标为待真实验收。
- [x] 16. [运行] `Package.swift` — 运行完整 test、Debug build、签名 app build、`git diff --check` 与 `harness check .`，对比旧计划基线。
  - 新鲜 scratch 下 18/18 tests、独立 Debug build、签名 App build 和全部计划文件 diff check 通过；Harness 17 pass / 2 warning / 0 failure。
- [x] 17. [修改] `NARC/Sources/Services/AppMonitorService.swift` — 修正系统 runner 的管道读取顺序，避免 `lsappinfo list` 大输出在 `waitUntilExit` 前填满管道而死锁。
  - 进程采样确认轮询线程持续卡在 `waitUntilExit`；现改为运行期排空 stdout，再等待退出，原有 5 条 Badge 逻辑测试保持通过。
- [x] 18. [修改] `NARC/Tests/AppMonitorServiceTests.swift` — 增加真实 Process 大输出回归覆盖，证明 runner 能完整排空管道并退出。
  - 新用例输出 256 KiB，实际执行 1/1 通过且在 0.084 秒退出。
- [x] 19. [运行] `build/NARC.app` — 重建并重启真实 App，验证企微 14 条 Badge、悬浮 `N` 标记、右键 Assistant、Panel 无 Workspace、`⌃⌥W` 不再注册及重启往返。
  - 签名 App 重启后真实显示企微 14，Small/Medium/Large 三档 `N` 均无裁切并已恢复 Medium；右键 Assistant/偏好设置和 Workspace 隐藏已走通。浮窗左键因自动化按下时长未触发 `<0.3s` 的 AppKit 阈值，Panel 本轮只做静态边界验证，未冒充端到端通过。
- [x] 20. [修改] `docs/FEATURES.md` — 回写真实 App 已验证的企微 14、右键入口和三档悬浮 `N`，保留未验证交互为待办。
  - 功能清单已区分真实通过项与剩余风险：企微 14 与重启往返、右键 Assistant/偏好设置、三档悬浮 `N` 已验证；14→0→恢复、Dock 缓存与其他 Assistant 入口仍保留待验收。

## Interaction QA
- 企微 Badge：当前 14 → NARC 14；企微清零后 NARC 0；再次产生未读后 NARC 恢复真实数字。
- 图标：Dock 大写 `N` 与蓝色圆角矩形视觉居中；悬浮圆点使用同一 `N`，在 Small/Medium/Large 三档均不偏移、不裁切。
- Assistant 主入口：Dock 重开、悬浮窗右键、Panel 星光按钮均能打开同一个 Assistant Hub。
- Workspace 软下线：Panel、右键菜单、偏好设置、模块列表均不可见；`⌃⌥W` 不再注册；已有底层代码仍能编译。
- 往返：退出并重启 NARC 后，上述入口与 Badge 状态仍一致；Todo/Note 数据不变。

## 禁止项
- 禁止删除 Workspace 核心文件、终止现有终端会话或移除 SwiftTerm 依赖。
- 禁止把多个企微实例的 Badge 求和，避免同一未读数重复计数。
- 禁止把截图、Toast 或按钮存在当成端到端成功；必须同时核对 LaunchServices、进程和真实 UI。
- 禁止借机重构 `AppDelegate.swift`、通知引擎或模块系统。
- 禁止把用户 Todo/Note 正文写入测试、日志、Harness 或 Brain。

## 验收标准
- AppMonitor 新增测试全部通过，完整测试不低于旧基线 13/13，且无新增警告。
- 当前企微实例真实返回 14 时，运行中的 NARC 悬浮 Badge 显示 14，而不是 0 或重复累加。
- Dock 与悬浮圆点的 `N` 经截图核对视觉居中，三种悬浮尺寸均不裁切。
- Workspace 的四类公开入口消失，`⌃⌥W` 不注册；底层 Workspace 与 SwiftTerm 仍编译通过。
- 文档与实现一致，`harness check .` 关键检查 0 failure。

## 停止条件
- 同一 Bundle ID 出现多个不相等的有效 Badge 且无法确定语义时，停止并回 Planner，不擅自求和。
- Workspace 软下线需要删除底层文件或破坏 Claude 外部状态监控时，停止并缩回入口层。
- 图标生成无法用现有系统框架完成时，停止，不新增图形依赖。
- 同一错误指纹重复 2 次或任一步骤连续 3 次验证失败时，触发 Anti-Wall Debug Card。

## 阻塞
（当前为空。）

## 建议
（当前为空。）

## 自检日志

### Step 1 — 2026-08-20 02:43
- files: NARC/Tests/AppMonitorServiceTests.swift, plan.md
- verify: `swift test --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-badge-red.1TVO1U --disable-sandbox --filter DockBadgeReader` failed as expected; compiler reported `cannot find 'DockBadgeReader' in scope`
- notes: 红灯只来自计划中尚未实现的类型；既有 `NotificationListView.swift:106` 弃用警告仍与上一计划基线一致。

### Step 2 — 2026-08-20 02:48
- files: NARC/Sources/Services/AppMonitorService.swift, plan.md
- verify: `git diff --check -- NARC/Sources/Services/AppMonitorService.swift NARC/Tests/AppMonitorServiceTests.swift` exit 0; targeted package build completed successfully
- notes: 读取失败不再静默写入 0；应用停止时仍按原行为清零，未改变轮询频率或过滤器语义。

### Step 3 — 2026-08-20 02:48
- files: Package.swift（仅运行验证）, plan.md
- verify: `swift test --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-badge-green.pJbttX --disable-sandbox --filter dockBadgeReader` exit 0; Swift Testing 5/5 passed
- notes: 首次用 `--filter DockBadgeReader` 仅完成编译但执行 0 tests，已明确拒绝该证据并用测试函数前缀重跑；唯一警告族仍为既有 `NotificationListView.swift:106`。

### Step 4 — 2026-08-20 02:49
- files: scripts/generate-icon.swift, build/NARC.icns, build/NARC.iconset/*, plan.md
- verify: `swift scripts/generate-icon.swift` exit 0; `sips -g pixelWidth -g pixelHeight build/NARC.iconset/icon_512x512@2x.png` reported 1024×1024; `git diff --check -- scripts/generate-icon.swift` exit 0; generated PNG visually inspected
- notes: 保留系统 Accent 蓝色、圆角和原有 iconset/icns 流程；只替换字形定位算法。

### Step 5 — 2026-08-20 02:52
- files: NARC/Sources/Views/FloatingWidgetView.swift, plan.md
- verify: `swift build --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-badge-green.pJbttX --disable-sandbox` exit 0; `git diff --check -- NARC/Sources/Views/FloatingWidgetView.swift` exit 0
- notes: 初次局部 `swiftc` 因命令未包含既有 AX/窗口服务依赖而失败，完整 Package build 已直接验证组件可编译；真实三尺寸视觉验收留在 Step 17。

### Step 6 — 2026-08-20 02:54
- files: NARC/Sources/Modules/ModuleRegistry.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-module-registry-cache -typecheck NARC/Sources/Modules/NARCModule.swift NARC/Sources/Modules/ModuleRegistry.swift` exit 0; `git diff --check -- NARC/Sources/Modules/ModuleRegistry.swift` exit 0
- notes: 仅移除默认实例，Workspace capability 枚举及所有 Dashboard/terminal 源码保持不变。

### Step 7 — 2026-08-20 02:54
- files: NARC/Tests/ModuleRegistryTests.swift, plan.md
- verify: `swift test --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-badge-green.pJbttX --disable-sandbox --filter moduleRegistry` exit 0; Swift Testing 3/3 passed; `git diff --check -- NARC/Tests/ModuleRegistryTests.swift` exit 0
- notes: 测试按函数名前缀实际执行 3 条，未把 XCTest 的 0 条兼容输出误当结果。

### Step 8 — 2026-08-20 02:56
- files: NARC/Sources/Services/HotkeyService.swift, plan.md
- verify: `swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path /tmp/narc-hotkey-soft-retire-cache -typecheck NARC/Sources/Models/Models.swift NARC/Sources/Services/HotkeyService.swift` exit 0; Workspace mapping scan returned no matches; `git diff --check` exit 0
- notes: 暂未运行完整 build，因为 AppDelegate 的旧回调接线按计划在 Step 11 移除；HotkeyService 自身已独立验证。

### Step 9 — 2026-08-20 02:57
- files: NARC/Sources/Views/PanelView.swift, plan.md
- verify: Workspace entry scan over `NARC/Sources/Views/PanelView.swift` returned no matches; `git diff --check -- NARC/Sources/Views/PanelView.swift` exit 0
- notes: AppDelegate 调用方将在 Step 11 同步移除参数，完整编译留到接线完成后执行。

### Step 10 — 2026-08-20 02:59
- files: NARC/Sources/Views/PreferencesView.swift, plan.md
- verify: visible tab/hotkey scan for `Workspace` and `⌃⌥W` returned no matches; `git diff --check -- NARC/Sources/Views/PreferencesView.swift` exit 0
- notes: `WorkspaceTab` 结构体仍编译进应用但不在 TabView 中实例化，符合一版本软下线回滚约束。

### Step 11 — 2026-08-20 03:00
- files: NARC/Sources/App/AppDelegate.swift, plan.md
- verify: public Workspace wiring scan returned no matches; `git diff --check -- NARC/Sources/App/AppDelegate.swift` exit 0; `swift build --package-path /Users/mickmi/narc_for_mac --scratch-path /tmp/narc-badge-green.pJbttX --disable-sandbox` exit 0
- notes: Dock reopen and widget context menu now front Assistant; private Dashboard lifecycle, Workspace close behavior, Claude services and SwiftTerm remain compiled for rollback.

### Step 12 — 2026-08-20 03:02
- files: docs/design/personal-assistant-design-brief.md, plan.md
- verify: required stage/entry/visual-boundary scan passed; `git diff --check -- docs/design/personal-assistant-design-brief.md` exit 0
- notes: 文档只记录已实现的入口与标记方向；真实截图验收仍明确留在 Step 17。

### Step 13 — 2026-08-20 03:03
- files: docs/PROJECT.md, plan.md
- verify: product-boundary/stage/Assistant-entry scan passed; `git diff --check -- docs/PROJECT.md` exit 0
- notes: 保留原阶段的历史假设并明确标注已被下方阶段修订，没有回写成伪造的原始决策。

### Step 14 — 2026-08-20 03:05
- files: docs/VERSIONS.md, plan.md
- verify: requirement/status/Goal scan passed; stable requirement ID uniqueness check passed; `git diff --check -- docs/VERSIONS.md` exit 0
- notes: 自动测试与静态边界已完成的需求标记为完成；真实 App 路径 `assistant-008` 未提前勾选，版本仍为 in_progress。

### Step 15 — 2026-08-20 03:05
- files: docs/FEATURES.md, plan.md
- verify: required current-state scan passed; stale visible Workspace row scan returned no matches; `git diff --check -- docs/FEATURES.md` exit 0
- notes: 第一次扫描命令因双引号内含 Markdown 反引号触发 shell command substitution，已拒绝该证据并用单引号安全重跑；功能清单未提前把待真实 QA 项标成成熟。

### Step 16 — 2026-08-20 03:08
- files: Package.swift（仅运行验证）, build/NARC.app（构建产物）, plan.md
- verify: fresh `swift test --scratch-path /tmp/narc-product-convergence.Ep9JbQ` exit 0 with Swift Testing 18/18; independent `swift build` exit 0; `bash scripts/build-app.sh debug` exit 0 with valid signature; planned-file `git diff --check` exit 0; `harness check .` exit 0 with 17 pass / 2 warning / 0 failure
- notes: 测试数由旧基线 13 增至 18；唯一编译警告族仍为既有 `NotificationListView.swift:106`，Harness 两条警告仍是 `.prompts` 非 symlink 与未安装 pre-commit。

### Step 17 — 2026-08-20 03:14
- files: NARC/Sources/Services/AppMonitorService.swift, plan.md
- verify: `/usr/bin/sample 520 1 1` captured the monitor thread blocked repeatedly in `DockBadgeReader.runSystemLSAppInfo -> waitUntilExit`; after the local change, targeted Swift Testing completed 5/5 with exit 0
- notes: 真实失败不是企微数值解析，而是 `lsappinfo list` 大输出填满 pipe；修复只调整 stdout 排空与进程等待的先后顺序。

### Step 18 — 2026-08-20 03:15
- files: NARC/Tests/AppMonitorServiceTests.swift, plan.md
- verify: `swift test --filter processRunnerDrainsOutputLargerThanThePipeBuffer` exit 0; Swift Testing executed 1/1 and finished in 0.084 seconds
- notes: 子进程真实输出 262,144 bytes，将此次现场死锁转为可重复的自动检查。

### Step 19 — 2026-08-20 03:26
- files: build/NARC.app（构建产物与真实交互）, plan.md
- verify: signed Debug app build and codesign exit 0; LaunchServices `ASN:0x0-0x12012 => label 14`, second ASN NULL; NARC UI displayed `14 N` after two restarts; right-click Assistant/Preferences opened; Small/Medium/Large screenshots captured and Medium restored; fresh process had 0 child processes; full Swift Testing 19/19, planned-file diff check exit 0, Harness 17 pass / 2 warning / 0 failure
- notes: 旧进程的 63 个子进程全部是死锁留下的 `lsappinfo`，退出旧 App 后已全部消失；浮窗左键 Panel 因自动化点击时长未满足 App 内 `<0.3s` 阈值，本轮未记为端到端通过。

### Step 20 — 2026-08-20 03:27
- files: docs/FEATURES.md, plan.md
- verify: evidence-state scan found the expected 14 / 14→0 / Small-Medium-Large / Dock-cache wording; `git diff --check -- docs/FEATURES.md plan.md` exit 0
- notes: 只回写真实完成的路径；Quick Capture、Todo、Notes、Panel 左键、Dock 缓存和企微清零往返没有提前标成成熟。

## Executor 指导
- 当前工作树包含大量用户既有修改；修改现有文件前必须读完整文件和当前 diff，只做可定位的局部改动。
- 企微问题已经由真实系统状态证明是多 ASN 查找失败；不要改成 AX/OCR 或读取企微私有数据。
- Workspace 采用可回滚软下线；公开入口必须全部消失，但底层实现和依赖本轮不得删除。
