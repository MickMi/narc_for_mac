# NARC Version Plan

> 本文件记录每个版本要证明的用户价值与需求归属。Git 分支、Tag、App Bundle 版本和发布产物仍以仓库与构建结果为真实状态源。

## 版本范围怎么定

- **Goal 是版本锚点**：版本内的 Requirement 必须直接证明 Goal，不能因为实现顺手就扩大范围。
- **状态机**：`draft` → `locked` → `in_progress` → `released`；进入 `locked` 后只接受不做就无法证明 Goal 的缺口和原需求澄清。
- **新增需求先分类**：`gap` 进入当前版本，`clarification` 更新当前描述，`new value` 进入未来版本或 Backlog。
- **三问判定**：它属于项目方向、版本 Goal 还是单项需求？当前版本是否冻结？不做它，版本 Goal 是否仍能被真实用户路径证明？
- **证据优先**：代码存在、TODO 勾选或编译通过都不等于版本可用；源码版本至少需要一致版本号、可定位的 Commit/Tag、一条命令安装记录和对应验收，不以预编译发布物作为完成证据。

## 历史基线

- 本地 Git Tag 可证明 `v1.0.0` 与 `v1.2.0`；文档将 Workspace 里程碑称为 v1.3，但当前没有对应本地 Tag，App Bundle 版本仍显示 `1.0.0`。
- v1.4 Workspace 增强曾进入历史工作树；旧的预编译分发候选已废弃，不在本文件中伪装成已发布版本或未来路线。
- v2.0 个人助手基础从 2026-08-20 起成为新产品主线；历史版本证据差异在发布前必须另行收口，但不阻塞本地功能验证。
- 2026-08-20 的产品收敛复审将 Workspace 从“并列保留”修订为“入口软下线一版、底层仅供回滚”；该修订属于 v2.0 Goal 澄清，不伪装成历史发布。

## v2.0.0 · 2026-08-20 · 个人助手基础

- Status: in_progress
- Branch: main（当前本地工作树；尚未形成发布分支或 Tag）
- Goal: 用户可以通过清晰一致的 Assistant 主入口快速创建、保存和重新管理 Todo 与 Note，同时可靠感知应用未读状态；Workspace 不再占用主产品入口。

### Requirements

- [x] `assistant-001` 固定个人助手项目目标、产品边界和版本范围，明确 Assistant 为主线，外部 AI 与动态插件延后。
- [x] `assistant-002` 建立编译期内置模块描述与 Registry，默认识别 Assistant、Notifications、Windows，拒绝重复模块 ID。
- [x] `assistant-003` 建立版本化本地 Todo/Note 数据存储，支持原子保存、重启恢复和损坏文件保护。
- [x] `assistant-004` 提供 Quick Capture，允许用户显式选择 Todo 或 Note，空白不能提交，失败时内容不丢失。
- [x] `assistant-005` 提供 Todo 页面，支持创建、查看未完成/已完成项目并切换完成状态。
- [x] `assistant-006` 提供 Notes 页面，支持创建、搜索和删除本地便签。
- [x] `assistant-007` 提供 Assistant Hub，并从 Dock 重开、悬浮窗右键、Panel 与全局 Quick Capture 路径进入。
- [ ] `assistant-008` 完成 Quick Capture、Todo、Notes、Assistant、Panel 与应用重启的真实交互验收。
- [x] `assistant-009` 对同一 Bundle ID 的多个 LaunchServices 实例去重读取 Dock Badge，多个有效值不累加，读取失败保留最后可信值。
- [x] `assistant-010` Dock 与悬浮圆点统一使用按可见重心居中的大写 `N`，并保留三档悬浮尺寸。
- [x] `assistant-011` 从 Panel、悬浮窗右键、偏好设置、默认模块与 `⌃⌥W` 软下线 Workspace，底层实现与 SwiftTerm 保留一版用于回滚。
- [x] `assistant-012` 提供 GitHub 源码一条命令准备：检查环境、本地构建、可恢复替换到 `~/Applications/NARC.app` 并启动，失败时给出下一条行动。
- [x] `assistant-013` 提供首次使用指南，只讲悬浮 `N` 与 `⌃⌥Q` 两个核心动作，完成后不重复弹出并允许从右键菜单重开。
- [x] `assistant-014` 用真实微信 4.1.11 AX 探针和 Apple 公开 API 完成重点会话可行性审查，明确书签可做、会话级未读监听当前 No-Go。
- [x] `assistant-015` 锁定 source-only 分发：删除预编译 Release 和稳定证书入口，禁止 DMG/PKG/预编译 App ZIP/公证/自动更新路线，并用静态 checker 防回归。

### Excluded

- 外部模型 API、自然语言自动分类、对话式回答和跨模块 AI 执行。
- Apple Notes、Reminders、Calendar、GitHub 或其他外部系统连接器。
- 团队协作、云同步、富文本数据库和复杂项目管理。
- 动态插件安装、第三方 Swift Bundle、脚本市场和插件权限系统。
- Workspace 新功能、公开入口和进一步视觉打磨；本版本只保留不可见回滚层。
- 微信/企微消息正文、会话级未读监听、默认 OCR、私有数据库读取、进程注入或 Hook。
- DMG、PKG、预编译 App ZIP、GitHub Release 安装包、Developer ID、公证、稳定自签名证书和自动更新框架。

## v2.1.0 · AI 编排

- Status: draft
- Goal: 在 v2.0 可验证数据与模块命令之上，让 AI 能理解自然语言、检索个人上下文并提出可确认的本地动作，而不把模型判断伪装成事实。

### Candidate Requirements

- [ ] `assistant-101` 建立可替换的模型适配边界，模型提供商、费用、隐私和离线降级由用户确认后锁定。
- [ ] `assistant-102` 将自然语言建议分类为 Todo、Note、Query 或 Command，并始终保留显式类型选择和撤销路径。
- [ ] `assistant-103` 跨 Todo、Notes、AI Activity 和模块状态检索，回答中标注来源与未验证推断。
- [ ] `assistant-104` 建立 AI 动作确认等级：低风险本地动作可撤销，高风险或外部写入必须确认。

## v2.2.0 · 个人连接器

- Status: draft
- Goal: 让用户在明确授权和可见失败反馈下，把 NARC 的个人上下文与常用系统服务连接起来。

### Candidate Requirements

- [ ] `connector-201` 评估并接入 Apple Notes / Reminders，明确双向同步、冲突和删除边界。
- [ ] `connector-202` 评估 Calendar、GitHub 与本地脚本连接器，按真实使用频率逐个立项。
- [ ] `connector-203` 为连接器提供权限、断连、重试、来源标识和数据撤回能力。

## v3.0.0 · 外部插件平台

- Status: draft
- Goal: 只有在至少三个真实外部连接器证明公共契约稳定后，才允许第三方扩展 NARC，而不牺牲宿主安全、兼容和可恢复性。

### Entry Gate

- 至少三个连接器已通过同一内置模块/命令契约运行一个完整版本周期。
- 已有明确的第三方开发者需求；仅为了“架构漂亮”不进入实现。
- 插件签名、版本兼容、权限隔离、崩溃隔离、升级与卸载方案均有可验证设计。

### Candidate Requirements

- [ ] `plugin-301` 定义版本化 Manifest、能力声明和宿主兼容协议。
- [ ] `plugin-302` 建立权限审批、数据边界、代码签名和运行隔离。
- [ ] `plugin-303` 建立安装、升级、禁用、卸载和故障恢复闭环。

## Backlog

- `assistant-backlog-001` AI Activity：将外部 Claude/Codex 会话状态、最近文件和跳转动作整理为个人助手模块，不依赖已软下线的 Workspace 入口。
- `assistant-backlog-002` 统一 Inbox：当 v2.0 的显式 Todo/Note 使用数据证明需要时，再评估“先收件、后分类”的单入口模型。
- `assistant-backlog-003` 提醒与周期任务：依赖 Todo 数据稳定和系统通知权限体验验证后立项。
- `assistant-backlog-004` 微信重点会话书签：用户显式维护名称/备注，复用微信应用级 Badge 与现有窗口找回；会话级状态固定显示“不可见”，经用户确认后可按 5–8 个工程日立项。
