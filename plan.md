> 🧭 状态：执行中 | 进度 8/9 | 当前归属：Executor | 最近卡点：菜单栏、Carbon 快捷键与双屏/全屏路径需真实 `.app` 验收

# Plan: NARC 双入口个人助手

## 目标

把 NARC 收束为“顶部状态栏 + 桌面悬浮球”的双入口个人助手：状态栏持续提供状态与找回入口，悬浮 `N` 作为注意力锚点常驻桌面；用户随时按 `⌃⌥N`，即可把悬浮球召回当前鼠标所在屏幕并展开轻量面板。随手记录继续采用先进入 Inbox、稍后转 Todo 或 Note 的低摩擦路径。

## v2.0.0 · 2026-09-07 · 双入口与注意力召回

## 产品决定

- NARC 默认是 accessory App，不显示 Dock 图标；顶部状态栏和桌面悬浮 `N` 同时保留并默认启用。
- 状态栏承担“持续状态与稳定找回”，悬浮 `N` 承担“当前屏幕上的注意力锚点”，二者不是替代关系。
- `⌃⌥N` 是召回动作而不是开关：悬浮球已在鼠标所在屏幕时保留用户位置；不在时移动到该屏幕的安全默认位置；无论面板此前是否可见，都把悬浮球置前并展开其相邻面板。
- 悬浮球继续支持拖动、尺寸调整、位置重置、点击开关面板和右键工具菜单；不得以菜单栏改造为由删除这些能力。
- 菜单栏首要动作是召回悬浮球，另提供使用指南、偏好设置、关于与退出；后续可在状态项上承载可信的应用未读。
- 首屏输入不要求选择 Todo/Note；Return 立即保存为 Inbox，之后可显式转成 Todo 或 Note，不引入外部 AI 或自动分类。
- 菜单栏数字只表示应用级未读，不混入 Inbox、Todo、AI 或错误数量；读取失败不伪装为零。
- 完整 Assistant 继续使用独立窗口承担 Todo、Notes 与后续管理，不把完整应用塞进窄面板。
- 首次使用引导改为菜单栏内的就地步骤；只有用户完成第一条记录才算掌握核心路径，“稍后”不再等于永久完成。
- 辅助功能与通知不在启动时主动索取；用户首次执行窗口动作或通知能力时再解释并请求。
- 不恢复 Workspace，不引入新依赖，不改变 source-only 分发边界，不制作 DMG/PKG 或预编译发布物。

## Preflight

- 基线 `swift test` 已在正常本机写入环境通过：25/25，0 failure。
- 当前 `Info.plist` 已有 `LSUIElement=true`，但 `AppDelegate` 在正常启动时改回 `.regular` 并无条件创建底部悬浮窗。
- 当前状态项绑定静态 `NSMenu`，左键不承担主面板；Badge 也没有订阅 `appMonitor.totalBadgeCount`。
- 当前 Quick Capture 是预选 Todo 的 440×310 表单，不能满足“先记下、后整理”。
- 现有 `AssistantSnapshot` schema v1 只有 Todo/Note；新增 Inbox 必须兼容读取 v1，并在首次成功写入时落为 v2。
- 当前 onboarding 用永久布尔值，且“稍后/关闭”都会写完成；已安装 App 因旧状态值而跳过引导并先展示权限 Alert。

## 步骤

- [x] 1. [计划] 归档已完成的 source-only 计划，锁定 B 方案的产品边界、风险和验收路径。
- [x] 2. [数据] 新增 Inbox 模型与 schema v1→v2 兼容迁移，支持保存、最近排序、转 Todo/Note、删除，并补齐持久化测试。
- [x] 3. [入口] 把 App 切为无 Dock 的 accessory 形态，同时保留状态栏与默认悬浮球；把 `⌃⌥N` 和状态栏首要动作统一为“召回悬浮球到鼠标所在屏幕并展开面板”，恢复悬浮球尺寸与位置设置。
- [x] 4. [随手箱] 实现菜单栏锚定面板：自动聚焦、Return 保存、最近三条、Todo/Note 转换、错误保留、成功反馈和完整 Assistant 入口。
- [x] 5. [路由] 让全局 Quick Capture、Assistant 内新增入口和重复唤起复用同一套随手箱语义，避免草稿被重建或入口类型错配。
- [x] 6. [引导与权限] 建立版本化就地引导状态，首次展开并完成真实记录；移除启动期权限请求，把辅助功能请求延迟到窗口动作。
- [x] 7. [文档] 更新 README、PROJECT、FEATURES、VERSIONS 与设计说明，标记旧 Dock/悬浮/显式分类决策被本阶段取代。
- [x] 8. [自动验证] 运行 Swift 测试、构建、分发边界检查、Harness 检查与静态残留扫描，记录 exit code 和关键结果。
- [ ] 9. [真实交互] 用真实 `.app` 验证无 Dock、状态栏、悬浮球拖动、双屏召回、重复快捷键不关闭面板、首次引导、连续记录、转换、Badge 与按需权限路径，并完成 Reviewer 对照。

## 验收标准

- 正常 `.app` 启动后 Dock 中没有 NARC；顶部状态栏与桌面悬浮 `N` 同时存在，悬浮球可拖动、可调整尺寸、可重置位置。
- 在任意屏幕按 `⌃⌥N`，悬浮球都会出现在当前鼠标所在屏幕并置前，面板在悬浮球旁展开；连续按快捷键不会把已经打开的面板关闭。
- 悬浮球已位于目标屏幕时保留用户拖动位置；跨屏召回时使用目标屏幕安全默认位置，悬浮球可见区域不得越出 `visibleFrame`。
- 状态栏可一键执行同一召回动作，并继续提供使用指南、偏好设置、关于与退出。
- 随手箱输入框立即可写；空白不可保存，Return 成功保存一条 Inbox，失败时原文不丢。
- 面板显示最近三条 Inbox，并能把每条显式转为 Todo 或 Note；转换后数据重启可恢复且不会重复保留 Inbox 原件。
- v1 数据无需手工处理即可读取；首次成功写入后生成 schema v2，既有 Todo/Note 不丢失。
- 菜单栏 Badge 与应用级未读保持一致，14 显示为 14，超过 99 显示 `99+`，零值不展示数字。
- 首次用户在菜单栏内完成第一条记录后才记为核心引导完成；旧布尔值不会屏蔽新版引导。
- 启动和首次记录不弹辅助功能/通知授权；首次使用窗口动作时才出现解释或系统请求。
- `⌃⌥Q`、菜单栏和 Assistant 内入口不会建立不同的捕获心智模型，也不会因重复唤起清空草稿。
- Source-only checker 继续通过，仓库不新增安装包、证书链或自动更新路径。

## 风险与停止条件

- 如果 `NSPopover` 无法同时满足文本输入、右键菜单和跨 Space 激活，优先复用现有 `PanelWindow` 做状态项锚定，不引入第三方 UI 框架。
- 如果多屏坐标（包括负坐标、不同缩放和显示器热插拔）导致悬浮球越界，先把定位逻辑抽成纯函数并用矩形边界测试证明，再进行真实双屏验收。
- 如果面板已打开时跨屏召回仍携带旧屏幕上下文，销毁并按目标屏幕重建轻量面板，不保留错误的窗口动作目标。
- 如果 schema v1 不能无损解码，停止写入并保留原文件，不以空 snapshot 覆盖用户数据。
- 如果 accessory 模式下完整 Assistant 无法稳定激活，先修复窗口 activation，不恢复 Dock 作为默认入口。
- 如果应用级 Badge 无可信值，保留最后可信状态并显示不可确认，不把 Inbox 数量混进去凑数。
- 同一错误指纹出现两次，输出 Debug Card 并停止碰运气式重试。

## 自检日志

### Step 1 — 2026-09-03
- files: `docs/archive/plan-v2.0-source-only-distribution-2026-08-23.md`、`plan.md`
- verify: 旧计划状态为 8/8 已完成；新计划仅覆盖用户确认的 B 方案，未恢复 Workspace、AI 自动分类或安装包路线。
- notes: 本轮按 `standard` 执行；数据迁移、UI 状态源和真实 `.app` 交互均列为独立 Gate。

### v2.0.0 · 2026-09-07 · 双入口方向修订
- files: `plan.md`
- verify: 产品边界明确保留顶部状态栏与桌面悬浮球；`⌃⌥N` 定义为幂等的跨屏召回，而不是删除悬浮球或切换关闭面板。
- notes: 2026-09-03 的 Inbox 数据与分阶段引导工作继续有效；仅改写入口架构及其验收，不恢复 Dock 或 Workspace。

### Step 2 — 2026-09-07
- files: `NARC/Sources/Models/AssistantModels.swift`、`NARC/Sources/Services/AssistantStore.swift`、`NARC/Tests/AssistantStoreTests.swift`
- verify: 完整 `swift test --scratch-path /private/tmp/narc-widget-tests-20260907 --disable-sandbox` exit 0，Swift Testing 47/47；覆盖 Inbox 保存/排序/删除、原子转换、v1→v2 兼容、损坏与未来 schema 保护。
- notes: Inbox 只做本地、显式转换，不引入 AI 自动分类或外部数据源。

### Step 3 — 2026-09-07
- files: `NARC/Sources/App/AppDelegate.swift`、`NARC/Sources/Services/HotkeyService.swift`、`NARC/Sources/Views/FloatingWidgetWindow.swift`、`NARC/Sources/Views/PanelView.swift`、`NARC/Sources/Views/NotificationListView.swift`、`NARC/Sources/Views/PreferencesView.swift`、`NARC/Tests/FloatingWidgetInteractionTests.swift`、`README.md`、`README.en.md`、`scripts/install.sh`、`plan.md`
- verify: 完整 Swift Testing 47/47；`bash scripts/build-app.sh debug` exit 0；Bundle `LSUIElement=true`、`Identifier=com.mickmi.narc`、`Signature=adhoc`、`codesign --verify --deep --strict` exit 0；无权限调试启动日志确认 accessory 模式、悬浮球初始化及 `Summon Widget ⌃⌥N` 注册；真实截图确认悬浮 `N` 可见；source-only checker、Shell 语法、Harness 与 `git diff --check` 均 exit 0。
- notes: 状态栏左键直接召回、右键打开工具菜单；同屏保留拖动位置，跨屏落到安全右下角，重复召回保持面板打开；尺寸变更与面板位置均做可见区夹紧，窗口动作在触发时动态读取悬浮球所在屏幕。Computer Use 无法触发 Carbon 全局快捷键或非激活悬浮窗点击，因此真实双屏、全屏 Space 与状态栏鼠标分流仍归 Step 9，不冒充已验收。

### Step 9.install — 2026-09-07 01:14
- files: `plan.md`、`build/NARC.app`、`/Users/mickmi/Applications/NARC.app`
- verify: 先精确移除旧安装、`build/`、`.build/`、空 `~/.narc/` 与 17 个无人占用的 NARC 临时项，再从当前工作区执行 `bash scripts/install.sh`，exit 0；安装 Bundle 为 `com.mickmi.narc`、`LSUIElement=true`、`Signature=adhoc`，严格签名校验与构建/安装二进制逐字节比对均 exit 0；仅 1 个 NARC 进程且路径指向 `~/Applications/NARC.app/Contents/MacOS/NARC`，无 staging/backup 残留；真实 UI 确认悬浮 `N` 可见、右键菜单可打开 Assistant、3 条既有 Todo 可见且关闭 Assistant 后悬浮球仍常驻；完整 Swift Testing 47/47、source-only checker、Harness 与 plan audit 当时均全部通过。
- notes: 本轮保留 `assistant-v1.json`、两份偏好域、当前有效的 Claude hook 与系统权限；App 首次启动仅把悬浮球位置从旧坐标夹回当前屏幕安全区域。Step 9 仍未勾选，因为真实双屏召回、全屏 Space、状态栏左右键分流和首次权限路径尚未完成手工验收。

### Step 4 — 2026-09-07
- files: `QuickCaptureView.swift`、`QuickCaptureWindow.swift`、`PanelView.swift`、`AssistantHubView.swift`、`AssistantHubWindow.swift`、`AppDelegate.swift`、`AssistantStoreTests.swift`
- verify: 完整 `swift test --scratch-path /private/tmp/narc-v2-release-tests --disable-sandbox` exit 0，62 tests；共享 `InboxCaptureState` 覆盖成功清空、写盘异常时保留内容和完成事件，既有 Store 测试覆盖最近排序、原子转换与重启恢复。
- notes: Panel 的真实点击、输入与 Return 保存已通过；双屏与全屏路径仍归 Step 9。

### Step 5 — 2026-09-07
- files: `QuickCaptureView.swift`、`QuickCaptureWindow.swift`、`PanelView.swift`、`AssistantHubView.swift`、`AssistantHubWindow.swift`、`AppDelegate.swift`、`AssistantStoreTests.swift`
- verify: 完整 Swift 测试 exit 0，62 tests；共享状态测试证明写盘异常时保留草稿、成功后清空，所有生产入口均由同一 `InboxCaptureState` 提供。
- notes: Panel、`⌃⌥Q` 与 Assistant 使用同一草稿和同一 Inbox 语义；跨窗口真实往返继续归 Step 9。

### Step 6 — 2026-09-07
- files: `OnboardingView.swift`、`QuickCaptureView.swift`、`AppDelegate.swift`、`HotkeyService.swift`、`OnboardingTests.swift`
- verify: 完整 Swift 测试 exit 0；旧 v2 布尔值不屏蔽当前引导，entrySeen 不算完成，第一条成功记录才推进；启动路径不再调用 AX/通知请求，全部 Carbon 快捷键在无 AX 时仍注册。
- notes: 首次窗口动作通过说明弹窗再请求辅助功能；系统通知仅在真实投递时请求。干净偏好与拒绝路径仍归 Step 9 手工验收。

### Step 7 — 2026-09-07
- files: `README.md`、`README.en.md`、`docs/STATE.md`、`docs/PROJECT.md`、`docs/FEATURES.md`、`docs/VERSIONS.md`、`DESIGN.md`、`DESIGN-COLLABORATION.md`
- verify: 中英文 README 均明确 v2 开发预览、双入口、Inbox、按需权限和 source-only 边界；删除无 `LICENSE` 支撑的 MIT 声明；活文档显式标记旧 Dock/Workspace/显式分类描述被 2026-09-07 阶段取代。
- notes: 正式 `v2.0.0` Tag 仍由 Step 9 真实验收决定；本轮只准备源码 PR，不创建二进制 Release。

### Step 8 — 2026-09-07
- files: .gitignore, .github, Package.resolved, NARC, README.md, README.en.md, docs, DESIGN.md, DESIGN-COLLABORATION.md, scripts
- verify: `swift package resolve` exit 0；完整 `swift test --scratch-path /private/tmp/narc-v2-release-tests --disable-sandbox` exit 0，62/62；Release `.app` 构建、Info.plist lint、`LSUIElement=true` 与严格 codesign 校验均 exit 0；source-only、Shell 语法、CI YAML、`git diff --check` 均 exit 0；`harness check .` 为 15 pass / 2 optional warnings / 无阻断；提交后按 `origin/main` 基线执行 plan audit 为 8 pass / 0 warning / 0 fail。
- notes: CI 已覆盖 Swift 测试、Release `.app` 构建、Info.plist、ad-hoc 签名、Shell 语法与 source-only；Harness 的两项 warning 是既有 `.prompts` 目录形态和可选 pre-commit hook，未修改项目边界。

### Step 9.partial — 2026-09-07
- files: `build/NARC.app`、`/Users/mickmi/Applications/NARC.app`、`~/Library/Application Support/NARC/assistant-v1.json`
- verify: `bash scripts/install.sh` exit 0；安装包体为 `2.0.0 (2)`、`LSUIElement=true`，严格签名与构建/安装二进制比对均 exit 0；真实 App 显示悬浮 `N` 与应用级 Badge 29（WeChat 3 + WeCom 26），点击后默认 Inbox 自动聚焦，Return 保存成功，重开后草稿仍在；测试记录已精确清理，Inbox 回到 0，既有 Todo/Notes 比对不变。
- notes: 当前环境只具备单显示器，Computer Use 也不能证明 Carbon 全局快捷键或 SystemUIServer 状态项分流；菜单栏左右键、真实双屏/全屏、转换和干净权限路径继续保留在 Step 9，不冒充完整验收。
