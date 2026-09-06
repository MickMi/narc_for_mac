# STATE - trusted handoff

> 任何 AI 打开本项目，先读这里。这里不记录强/弱模型身份，只记录可信事实、当前边界、待验证项和下一步。

## ENTRY POINT
- 当前阶段: v2 双入口个人助手开发预览，发布前收口期。
- `plan.md`: 存在且执行中；Steps 1–8 已完成，当前进入剩余真实交互验收。
- 当前分支: `feat/v2-dual-anchor-preview`；不得直接 push `main`。
- Harness 定位: 开发规范、证据纪律、边界控制、验证闭环和交接格式。模型强弱切换只是可选调度策略，不是项目状态。
- 发布口径: 只发布 GitHub 源码与 PR；不创建 DMG、PKG、预编译 App ZIP、二进制 GitHub Release、证书链或自动更新。

## 当前可信事实
- 产品入口固定为顶部菜单栏 + 桌面悬浮 `N`，默认无 Dock；`⌃⌥N` 把悬浮球召回鼠标所在屏幕并保持面板展开。
- 随手记录采用 Inbox：Return 保存，最近三条可见，之后显式转 Todo/Note；面板、`⌃⌥Q` 与 Assistant 共用同一份草稿状态。
- Todo、Notes 与 Inbox 保存到 `~/Library/Application Support/NARC/assistant-v1.json`；文件名保持兼容，内部 schema 为 v2。
- 应用未读只读取 macOS LaunchServices 的应用级 Dock Badge；多实例取最大可信值，未知时在最后可信值后追加 `?`，无旧值时显示 `?`。
- 启动期不主动请求辅助功能或通知权限；窗口动作首次使用时解释并请求，通知仅在首次真实投递时请求。
- App Bundle 版本为 `2.0.0 (2)`；当前仍是开发预览，没有 v2 Tag 或二进制 Release。
- 完整 Swift 测试当前为 62 项；最新一次通过，发布前仍需完成最终全量门禁。
- 已归档一批不可信中间产物到 `docs/archive/stale-harness-v1/`，仅隔离，不删除。
- 当前业务视角功能清单记录在 `docs/FEATURES.md`；它只描述用户可见能力状态，不作为 bug backlog 或实现计划。
- 高频无权限 UI 验证可使用 `NARC_DEV_NO_AX=1`；该模式保留 `⌃⌥N` 与 `⌃⌥Q`，跳过 AX 窗口能力和系统通知。
- 以下历史文档仍可作为背景参考，但不是当前 bug 修复的自动指令:
  - `docs/PRD-claude-tab-monitor.md`
  - `docs/blueprint-claude-tab-monitor.md`
  - `docs/reviews/claude-tab-monitor-2026-06-10.md`
  - `docs/PRD-workspace-ux-polish.md`
  - `docs/blueprint-smart-copy.md`
  - `docs/blueprint-widget-drag-fix.md`
  - `docs/reviews/smart-copy-drag-fix-2026-06-18.md`
- `docs/archive/stale-harness-v1/` 内文档来自旧 Harness 中间状态，后续不得直接当作执行蓝图。

## 已完成的本机真实检查
- 最终源码已重新安装为 `~/Applications/NARC.app`；Bundle 为 `2.0.0 (2)`、`LSUIElement=true`，签名有效且二进制与本轮构建一致。
- 悬浮 `N` 可见并显示检查时的应用级 Badge 29（WeChat 3 + WeCom 26）；点击后默认打开 Inbox，输入框自动聚焦，Return 保存、关闭重开后的草稿保留均已通过。
- 本轮临时测试记录已精确清理，Inbox 恢复为 0，既有 Todo/Notes 保持不变。

## 已修改但待真实手测
- Inbox 最近三条、Todo/Note 转换和写盘错误保留的自动测试已通过，真实转换与错误路径仍待手测。
- 菜单栏左右键分流与状态栏数字/未知态。
- 干净偏好下的分阶段引导，以及首次窗口动作与首次通知的按需权限路径。
- 真实双显示器召回、重复 `⌃⌥N` 不关闭面板、全屏 Space 和跨屏窗口动作。

## 当前已知产品问题
- LaunchServices 不保证所有 App 始终暴露 Badge；`?` 后缀表示状态不可确认，不是零未读。
- 微信/企微会话级未读没有可信公开状态源，当前明确不实现。
- Workspace 与嵌入式终端入口已软下线；残留底层只作一版回滚，不属于当前产品承诺。
- AI 编排、外部连接器和动态插件平台属于后续版本，当前不实现。

## 已隔离的旧中间产物
- `docs/archive/stale-harness-v1/PRD-backlog-v14-v15.md`
- `docs/archive/stale-harness-v1/PRD-diff-drawer.md`
- `docs/archive/stale-harness-v1/PRD-next-round.md`
- `docs/archive/stale-harness-v1/blueprint-backlog-v14-v15.md`
- `docs/archive/stale-harness-v1/blueprint-diff-drawer.md`
- `docs/archive/stale-harness-v1/reviews/backlog-v14-v15-2026-06-23.md`

## 下一步建议
1. 完成 Step 9 剩余的菜单栏、Carbon 快捷键、真实双屏/全屏、Inbox 转换/错误和干净权限/引导验收。
2. 推送功能分支并创建 PR；CI 通过且 review 无阻断后再合并，暂不打 v2 正式 Tag。

## 回合卡片要求
- 只要本回合有交付物、状态变化、归档、文件改动、卡点或阶段推进，最终回复必须输出回合卡片。
- 如果没有回合卡片，应视为没有完整遵守 Harness 交接约束。
