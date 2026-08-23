> 🗄️ 归档状态：已完成 | 进度 20/20 | 原当前归属：Reviewer | 最近卡点：无

# Plan: NARC v2.0 GitHub 本地运行与微信重点会话研究

## 目标
让用户从 GitHub 获取源码后，只需一条安装命令和两个高频动作就能启动、呼出并理解 NARC；同时用真实 macOS/WeChat 证据界定“标记并监听重点微信会话”的可行实现边界。

## v2.0.0 · 2026-08-20 · GitHub 本地运行与首次使用

## 约束
- 主分发方式是 GitHub 源码，不依赖 App Store、Developer ID、公证、Sparkle 或包管理器。
- 仍在本地生成 `.app`，因为 macOS 的 Bundle ID、图标、重开行为和权限归属需要 App Bundle；但该过程对用户隐藏在安装脚本内。
- 默认安装到 `~/Applications/NARC.app`，不要求 `sudo`，不写 `/Applications`，不自动移除 quarantine 属性。
- 最低 macOS 14；用户需要 Xcode Command Line Tools 提供 `swift`，首次构建需要网络下载 SwiftTerm。
- 首次使用只教两个高频动作：点击悬浮 `N` 看状态，`⌃⌥Q` 快记 Todo/Note；Assistant 和偏好设置作为次级入口。
- 辅助功能权限只用于窗口操作、钉选与相关快捷键；不得在文案中误导为 Assistant、Todo/Note 或 Dock Badge 的必要条件。
- 微信研究只做只读探针和方案界定；不读微信私有数据库，不注入进程，不使用非公开 Hook，不替用户点击、发送或标记任何真实消息。
- 微信会话名、联系人、群名和消息正文不得写入代码、测试、日志、Harness 或研究文档。
- 不恢复 Workspace 入口，不扩展 Claude 内嵌终端，不引入新第三方依赖，不清理用户已有工作树。

## Preflight
- 仓库真实远端为 `https://github.com/MickMi/narc_for_mac`；当前包要求 Swift tools 5.9 / macOS 14，本机为 macOS 26.5.2 / Swift 6.3.3。
- `NARC/Resources/Info.plist` 的 Bundle ID 为 `com.mickmi.narc`；当前 `scripts/build-app.sh` 会生成 `build/NARC.app`，但在没有本机 `NARC Dev` 证书时只打印“回退 ad-hoc”而没有真正签名。
- 当前 README 仍把已软下线的 Workspace/嵌入终端写成右键主入口，并要求手工安装 Claude Hook，与当前 Assistant 主线不符。
- 当前启动时权限 Alert 与 `HotkeyService` 可以同时触发系统设置，没有面向首次用户的简单入口说明。
- 上一计划已验证完整 Swift Testing 19/19、签名 Debug App 和 Harness 17 pass / 2 warning / 0 failure；本计划以此为回归基线。
- 微信当前在本机运行，但其会话列表、未读标记和独立窗口的 Accessibility 暴露程度尚未验证，不先假定 AX 可用。

## 文件级 API 契约
- `scripts/install.sh`：默认 release 构建并原子安装到 `${NARC_INSTALL_DIR:-$HOME/Applications}/NARC.app`；`NARC_SKIP_LAUNCH=1` 只安装不启动且允许用临时目录与当前 NARC 并存；缺少 macOS/`swift` 或准备启动新副本时检测到运行中 NARC，必须给出可直接执行的下一步并非零退出。
- `scripts/build-app.sh`：有 `NARC Dev` 时使用稳定证书；没有时必须真实执行 `codesign --sign -`，然后用 `codesign --verify --deep --strict` 验证。
- `OnboardingPresentationPolicy.shouldPresent(hasCompleted:force:) -> Bool`：首次运行未完成时返回 true，右键“使用指南”传入 force 时始终返回 true。
- `OnboardingView`：只展示两个核心动作、当前辅助功能状态和三个明确操作（打开 Assistant、打开辅助功能设置、稍后），不展示内部架构和版本术语。
- `HotkeyService.checkAccessibilityPermission(prompt:) -> Bool` 与 `registerGlobalHotkeys(promptForAccessibility:)`：首次引导期允许只检查而不弹系统设置；既有调用默认行为保持兼容。
- `AppDelegate`：用 `narc.onboarding.completed.v2` 持久化首次引导；首次先显示引导而不叠加旧权限 Alert；悬浮窗右键可重新打开“使用指南”。

## 步骤

- [x] 1. [创建] `scripts/install.sh` — 实现 macOS/Swift 前置检查、release 构建、`~/Applications` 可恢复替换、可选跳过启动；只在准备启动新副本时阻止运行中 NARC，成功时只打印“点 N / `⌃⌥Q` / 首次权限”三条用户指令。
  - 已新增安全的临时目录/备份替换流程，支持可测试的只安装模式，失败时保留旧 App。
- [x] 2. [修改] `scripts/build-app.sh` — 为无 `NARC Dev` 证书的 GitHub 用户执行真实 ad-hoc 签名与严格验证，删除输出中过时的 Workspace 提示。
  - 稳定证书与 ad-hoc 两条分支现统一经过 `codesign --verify --deep --strict`，无证书时不再误报“已回退”。
- [x] 3. [运行] `scripts/install.sh` — 先跑 `bash -n`，再用临时 `NARC_INSTALL_DIR` + `NARC_SKIP_LAUNCH=1` 建立安装基线，核对 App 路径、Bundle ID、签名和非零失败文案。
  > ⚡ 修订：首次基线已证明安装/签名通过，但成功路径泄露完整构建日志；本步先在 `scripts/install.sh` 将成功日志收敛为用户文案（构建失败时仍展开完整错误），再重跑同一验收。
- [x] 4. [创建] `NARC/Sources/Views/OnboardingView.swift` — 实现简洁首次使用界面与 `OnboardingPresentationPolicy`，使用现有 DesignTokens 和无障碍标签。
  - 界面只教“点 N”和“`⌃⌥Q`”，权限卡明确说明 Assistant/Todo/Note/Badge 不依赖辅助功能。
- [x] 5. [创建] `NARC/Sources/Views/OnboardingWindow.swift` — 复用 Assistant/Preferences 的 AppKit 窗口模式，提供 `present()` / `dismiss()` 并保证关闭窗口不退出 App。
  - 窗口关闭与按钮取消共用一次性 dismiss 回调，引导可在任意屏幕居中重新打开。
- [x] 6. [修改] `NARC/Sources/Services/HotkeyService.swift` — 为权限检查和全局快捷键注册增加默认兼容的静默首启参数，静默模式不自动打开系统设置。
  > ⚡ 修订：未授权时必须复用 `registerDevNoAXHotkeys()` 保留 `⌃⌥Q`/`⌃⌥N`；定时器发现授权后先完整注销降级 hotkey/event handler，再注册窗口布局与钉选，禁止重复 handler。
- [x] 7. [修改] `NARC/Sources/App/AppDelegate.swift` — 接入首启策略、OnboardingWindow、静默权限检查、“使用指南”右键/菜单栏入口及 Assistant 转化路径，不恢复 Workspace。
  - 首启现延后旧权限 Alert、系统设置与通知授权请求，先展示一个使用指南；完成后持久化，且右键/菜单栏可 force 重新打开。
- [x] 8. [创建] `NARC/Tests/OnboardingTests.swift` — 覆盖未完成首启、已完成重启和 force 重新打开三条策略路径。
  - 已新增三条纯策略测试，不依赖用户真实 UserDefaults 或 TCC 状态。
- [x] 9. [运行] `Package.swift` — 运行 Onboarding 定向测试、完整 Debug build 和 `git diff --check`，记录新增警告数。
  - 首启策略 3/3 实际执行通过，完整 NARC Debug 模块链接通过，未出现新警告。
- [x] 10. [修改] `README.md` — 重写中文主文档：首屏给出一条安装命令、两个呼出动作、当前 Assistant/Badge/窗口能力、权限边界、更新/卸载/故障排查与开发命令，移除 Workspace/Claude Hook 主入口的过时叙述。
- [x] 11. [修改] `README.en.md` — 与中文 README 保持相同的安装、呼出、功能、权限和限制边界，不额外承诺未验证能力。
- [x] 12. [修改+运行] `NARC/Sources/Views/FloatingWidgetWindow.swift`、`NARC/Tests/FloatingWidgetInteractionTests.swift`、`build/NARC.app` — 从排除 `.git/.build/build` 的临时干净目录执行安装脚本；真实 QA 发现 300ms 时间门槛会丢弃慢点击，因此先改为“未进入拖动且位移小于 5pt 即点击”并补回归测试，再重新安装并验证首次指南、点 `N`、右键“使用指南”、Assistant、`⌃⌥Q` 注册证据和重启不重复弹出。
  > ⚡ 修订：右键、首次引导、Assistant 与重启路径已真实通过；`computer-use` 不支持触发全局快捷键，`⌃⌥Q` 以 Carbon 注册测试/日志为直接证据，不能伪装成 GUI 端到端。
- [x] 13. [运行] `/Applications/WeChat.app` — 用 Computer Use 与只读 Accessibility 探针核对顶层窗口、会话列表、标题、未读状态和虚拟滚动暴露，输出和文档中只记录元数据/能力而不记录个人内容。
- [x] 14. [创建] `docs/research/wechat-priority-conversations.md` — 结合真实 AX 探针和 Apple 公开 API 文档，对比顶层窗口、AX 会话行、系统通知、OCR、私有数据库/Hook，给出可实施的“用户显式标记 + 可见行监听 + 失效反馈”MVP 或明确的 No-Go 结论。
- [x] 15. [修改] `docs/PROJECT.md` — 将 GitHub 源码安装、首次使用界面和微信重点会话研究边界写入当前稳定产品决策。
- [x] 16. [修改] `docs/VERSIONS.md` — 为 v2.0 增加可追踪的 GitHub 安装/首启需求 ID，把微信重点会话按研究结论放入 gap 或后续候选，不伪装成已实现监听。
- [x] 17. [修改] `docs/FEATURES.md` — 更新用户可见的本地安装、首次指南和微信细粒度监听状态，保留已知限制。
- [x] 18. [运行] `Package.swift` — 在新鲜 scratch path 运行完整测试、Debug/release App 构建、签名校验、计划文件 diff check 与安装脚本静态检查。
- [x] 19. [运行] `.harness/verify.sh` — 如入口存在则运行，否则运行 `harness check .`，记录 exit code、pass/warning/failure 数与新增问题。
- [x] 20. [运行] `plan.md` — 按用户目标做完成审计：安装命令、呼出说明、功能介绍、权限边界、真实首启交互和微信研究结论每项必须有直接证据。

## Interaction QA
- 干净路径：用户 clone/download 后执行一条命令，终端最后只给出可行动的结果；安装产物位于 `~/Applications/NARC.app` 并能启动。
- 前置失败：非 macOS、缺 `swift`、构建失败、准备启动新副本时已有 NARC 运行，均要停止且给出一条明确下一步，不留半安装 App。
- 首次启动：只出现一个使用指南，不同时叠加权限 Alert/系统设置；关闭或打开 Assistant 后记住完成状态。
- 悬浮点击：按住超过 300ms 但未移动仍应打开面板；移动达到 5pt 才进入拖动，不用时间门槛猜用户意图。
- 重新查看：右键悬浮 `N` 和菜单栏都能打开使用指南，不会重置 Todo/Note 或权限。
- 核心呼出：点 `N` 打开 Panel，`⌃⌥Q` 打开 Quick Capture，右键可打开 Assistant；关闭并重启后仍一致。
- 权限往返：已授权显示完成；未授权可主动打开系统设置，但不阻止 Assistant/Todo/Note/Badge。
- 微信探针：仅读取当前可见 AX 语义，不点击会话；研究文档只记录可用 role/attribute/稳定性，不记录标题和正文。

## 禁止项
- 禁止把 `swift run` 当作普通用户的日常启动方式；终端只用于首次安装/开发，安装后用户直接启动 App。
- 禁止要求普通用户创建自签名证书、手动复制 App Bundle、编辑 Claude Hook 或理解 SPM。
- 禁止安装脚本在检测到运行中 NARC 时强制 kill，禁止破坏式覆盖无备份的已安装 App。
- 禁止在 README 把 Workspace、Claude 嵌入终端、微信消息内容监听或自动更新写成当前能力。
- 禁止将 macOS Notification Center 数据库、微信本地 DB、OCR 或私有 Hook 作为默认方案；如无公开稳定的状态源，必须明确降级或 No-Go。

## 验收标准
- README 首屏有一条可复制安装命令，不超过两个日常必记动作；中英文安装、功能和限制语义一致。
- 临时干净目录的 `bash scripts/install.sh` 退出 0，安装 App 的 `CFBundleIdentifier=com.mickmi.narc`，`codesign --verify --deep --strict` 退出 0，启动后进程路径指向安装目录。
- 首次指南真实可见且可重新打开；Assistant、Panel、Quick Capture 各至少走一次真实路径，重启后首次指南不重复弹出。
- 微信方案文档明确回答：“窗口”的实体层级、可标记的稳定标识、可读的未读状态、不可见/离屏限制、权限、失效反馈、隐私与是否值得进入实现。
- 完整测试不低于 19/19，Debug/release 构建、安装、签名、diff check 和 Harness 关键检查 0 failure，不新增编译警告族。

## 阻塞
（当前为空。）

## 建议
（当前为空。）

## 自检日志

### Step 1 — 2026-08-20 03:44
- files: scripts/install.sh, plan.md
- verify: `bash -n scripts/install.sh` exit 0; required-path scan passed; `git diff --check -- scripts/install.sh plan.md` exit 0
- notes: 项目中无现有安装入口可复用，因此复用 `build-app.sh` 并新建只负责前置检查、安装和用户回执的薄脚本。

### Step 2 — 2026-08-20 03:45
- files: scripts/build-app.sh, plan.md
- verify: `bash -n scripts/build-app.sh` exit 0; signing/output contract scan passed; `git diff --check -- scripts/build-app.sh plan.md` exit 0
- notes: 本步只证明脚本结构与签名分支收敛正确；真实构建与签名留在 Step 3。

### Step 3 — 2026-08-20 03:48
- files: scripts/install.sh, build/NARC.app（构建产物）, plan.md
- verify: temporary release install exit 0; Bundle ID `com.mickmi.narc`; forced ad-hoc `codesign --verify --deep --strict` exit 0; staging leftovers 0; running-NARC path exit 3 with actionable guidance; `bash -n` and `git diff --check` exit 0
- notes: 首次基线暴露完整构建内部日志，本步按 Planner 修订改为“成功路径隐藏、失败路径展开”；重跑后输出只剩构建进度、安装位置和三条用户指令。

### Step 4 — 2026-08-20 03:50
- files: NARC/Sources/Views/OnboardingView.swift, plan.md
- verify: `swiftc -frontend -parse NARC/Sources/Views/OnboardingView.swift` exit 0; required-copy/policy scan passed; `git diff --check` exit 0
- notes: 复用 DesignTokens 与现有 SwiftUI 按钮模式；本步只做语法/契约验证，模块编译与真实视觉留到 Step 9/12。

### Step 5 — 2026-08-20 03:51
- files: NARC/Sources/Views/OnboardingWindow.swift, plan.md
- verify: `swiftc -frontend -parse NARC/Sources/Views/OnboardingWindow.swift` exit 0; lifecycle contract scan passed; `git diff --check` exit 0
- notes: 复用 AssistantHubWindow 的多屏定位和 App 激活方式，没有新建第二套窗口管理服务。

### Step 6 — 2026-08-20 03:52
- files: NARC/Sources/Services/HotkeyService.swift, plan.md
- verify: `swiftc -frontend -parse NARC/Sources/Services/HotkeyService.swift` exit 0; after Planner revision, complete Debug `swift build` exit 0; no-AX registration / handler removal / upgrade scan passed; `git diff --check` exit 0
- notes: README 对照发现未授权时核心 `⌃⌥Q`/`⌃⌥N` 也被跳过，因此本步回退后按修订重做：复用既有 no-AX 注册，授权后先注销 hotkey 与 event handler 再升级完整映射。

### Step 7 — 2026-08-20 03:55
- files: NARC/Sources/App/AppDelegate.swift, plan.md
- verify: `swiftc -frontend -parse NARC/Sources/App/AppDelegate.swift` exit 0; onboarding/menu/permission contract scan passed; visible Workspace entry scan returned none; `git diff --check` exit 0
- notes: 第一次远距离大补丁因函数上下文不匹配而零写入失败，后续按已读局部分块应用成功；真实模块编译留在 Step 9。

### Step 8 — 2026-08-20 03:56
- files: NARC/Tests/OnboardingTests.swift, plan.md
- verify: `swiftc -frontend -parse NARC/Tests/OnboardingTests.swift` exit 0; three-state test scan passed; `git diff --check` exit 0
- notes: 实际执行和模块链接留在 Step 9，本步只确认测试文件语法与覆盖意图。

### Step 9 — 2026-08-20 03:57
- files: Package.swift（仅运行验证）, plan.md
- verify: `swift test --filter onboarding` exit 0 with 2/2; `swift test --filter userCanForceTheGuideToOpenAgain` exit 0 with 1/1; complete Debug `swift build` exit 0; planned-file `git diff --check` exit 0
- notes: 第一个过滤器只命中 2/3，未被误报为完整通过；补跑 force 用例后三条路径才全部有执行证据。

### Step 10 — 2026-08-20 04:07
- files: README.md, plan.md
- verify: install command / floating N / `⌃⌥Q` / data path semantic scan passed; stale Workspace/terminal/Claude Hook/current-version claims returned none; 12 Markdown fences are balanced; `git diff --check -- README.md` exit 0
- notes: 精确字符串初检因 Markdown 把 `N` 包在行内代码中而未命中，改用语义兼容匹配确认内容存在；调用层转义和 zsh 只读通用变量各失败一次，均未执行或修改项目内容。

### Step 11 — 2026-08-20 04:09
- files: README.en.md, plan.md
- verify: install path / two actions / Assistant data / Accessibility / per-conversation boundary / Workspace boundary scan passed; stale product claims returned none; 12 Markdown fences are balanced; `git diff --check -- README.en.md` exit 0
- notes: 初次旧路径扫描把 `~/Applications` 内部的 `/Applications` 子串误判为系统级路径，改用负向边界后确认不存在真实旧路径；中英文产品承诺保持一致。

### Step 12 — 2026-08-20 04:19
- files: NARC/Sources/Views/FloatingWidgetWindow.swift, NARC/Tests/FloatingWidgetInteractionTests.swift, isolated NARC.app, plan.md
- verify: clean-source `bash scripts/install.sh` exit 0 twice; strict signing exit 0; first guide visible with one window; Assistant opened; completion default became 1; right-click guide reopened; restart showed widget only; pointer-policy tests 3/3 passed; coordinate left click produced a 320x420 panel beside the 128x128 widget; startup log recorded `Registered hotkey: Quick Capture ⌃⌥Q`
- notes: AX element click does not enter the NSPanel mouse-event route and `computer-use` cannot invoke global shortcuts, so left click used one real coordinate action plus CGWindow size evidence, while `⌃⌥Q` used actual Carbon registration output; removed the 300ms tap timeout so deliberate slow clicks remain valid until movement reaches 5pt.

### Step 13 — 2026-08-20 04:24
- files: /Applications/WeChat.app（只读运行态）, plan.md
- verify: WeChat 4.1.11 (269136), bundle `com.tencent.xinWeChat`; Computer Use returned one 735x861 top-level window, 10 non-semantic label nodes, 0 list/row/scroll-area nodes, 0 selected state, 0 explicit unread tokens, and no AX scroll actions
- notes: 未点击、未滚动、未输入，未记录联系人/群名/消息摘要；当前真实 AX 树无法稳定标识会话行、会话级未读或虚拟列表边界，因此不能把“可见行监听”当作现成 MVP。

### Step 14 — 2026-08-20 04:27
- files: docs/research/wechat-priority-conversations.md, plan.md
- verify: official Apple AX/AXObserver/UserNotifications/Vision/ScreenCaptureKit sources linked; Go/No-Go, evidence tiers, safe MVP, 5–8 day estimate, and reevaluation triggers present; forbidden supported-monitoring claims returned none; `git diff --check` exit 0
- notes: 结论为“重点会话书签可做、会话级未读监听当前 No-Go”；系统通知只能读取本 App、AX 无会话行、OCR 需要屏幕录制且只覆盖可见区域，私有数据库/注入/Hook 永久不进入方案。误在非仓库副本创建的文件已删除并移回用户指定仓库路径。

### Step 15 — 2026-08-20 04:29
- files: docs/PROJECT.md, plan.md
- verify: traceable v2.0 GitHub/first-use heading, install contract, two actions, permission boundary, research link, and WeChat No-Go scan passed; `git diff --check` exit 0
- notes: 将源码安装与首次指南提升为稳定产品决策；未知微信会话状态不得显示为零。

### Step 16 — 2026-08-20 04:29
- files: docs/VERSIONS.md, plan.md
- verify: `assistant-012`/`013`/`014` and `assistant-backlog-004` all present; prohibited WeChat content/OCR/private paths listed under Excluded; `git diff --check` exit 0
- notes: 重点会话书签只进入 Backlog 候选，等待用户确认后按 5–8 个工程日立项；没有伪装成 v2.0 已实现监听。

### Step 17 — 2026-08-20 04:29
- files: docs/FEATURES.md, plan.md
- verify: GitHub install / onboarding / slow-click / WeChat boundary rows present; stale “onboarding missing” and supported per-conversation monitoring claims returned none; `git diff --check` exit 0
- notes: 源码安装与首次指南进入成熟；Quick Capture 仍因 GUI 全局快捷键限制保留“需调整”，只记录已验证的 Carbon 注册事实。

### Step 18 — 2026-08-20 04:34
- files: clean copy under /private/tmp/narc-step18.UtDikv, Package.swift, planned files, plan.md
- verify: clean source contained no `.build`/`build`; full `swift test --scratch-path ...` exit 0 with 25/25; Debug App build + strict codesign + Bundle ID gate exit 0; Release App build + strict codesign + Bundle ID gate exit 0; both shell scripts parsed; complete planned-file `git diff --check` exit 0
- notes: 唯一编译告警仍是既有 `NotificationListView.swift:106` 的 macOS 14 `onChange` 弃用提示；本轮新增文件没有新增 warning。第一次组合测试因沙箱缓存权限失败且末尾 diff 掩盖退出码，已拆分并在授权后用独立退出码重跑通过。

### Step 19 — 2026-08-20 04:34
- files: Harness project state（只读检查）, plan.md
- verify: `.harness/verify.sh` absent, so `harness check .` exit 0; 17 passed, 2 warnings, 0 failed, total 19
- notes: 两条既有 warning 为 `.prompts/` 是真实目录而非 symlink、pre-commit hook 未安装；均不属于本计划产品改动，未自动清理或安装。

### Step 20 — 2026-08-20 04:35
- files: plan.md and all planned artifacts（只读完成审计）
- verify: no unchecked items except Step 20 before this update; all required artifacts present; README install/two-action/Workspace boundary scan passed; version IDs and WeChat Go/No-Go scan passed; repository-wide `git diff --check` exit 0
- notes: 用户目标已逐项闭环；工作树另有大量用户既有/前序未提交改动，本轮未清理、回退、提交或发布。微信重点会话书签仅进入 Backlog，等待用户下一次明确确认后实现。

## Executor 指导
- 当前工作树有大量用户既有改动；修改前必须先读当前文件和局部 diff，不回退非本计划内容。
- 安装脚本是产品入口，错误文案必须直接给出下一条用户命令，不向普通用户暴露 cdhash、SPM、Designated Requirement 等内部概念。
- 安装验证必须用临时目录和 `NARC_SKIP_LAUNCH=1`，未到真实 QA 步骤前不替换用户当前运行中的 App。
- 首次引导不得把全部快捷键、所有模块和权限术语堆给用户；细节留在 README/偏好设置。
- WeChat AX 探针先读语义树，禁止使用坐标点击、滚动或输入；如输出包含个人标题，只在当前工具输出中短暂分析，不回写到项目。
