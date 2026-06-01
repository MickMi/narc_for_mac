# NARC Workspace Dashboard — Design Brief

> 用于喂给设计 AI（v0 / Galileo / Stitch / Figma Make / Claude / GPT 等）。
> 这是一份产品 + UX 描述，不包含具体代码。设计师 / AI 应该基于这份 brief 输出
> 视觉稿、组件库、交互原型即可。

---

## 1. 产品背景

**NARC（Notification & Application Resource Center）** 是一款 macOS 桌面工具，定位是「开发者的桌面指挥中心」：把 IM 红点、窗口管理、Claude Code 多任务状态聚合到一个常驻浮窗里。

**Workspace Dashboard** 是 NARC 内嵌的「多终端工作台」窗口，目标是把以前散落在 iTerm / Terminal.app / VS Code 终端中的 Claude Code 会话集中到一处管理。

### 目标用户

懂技术的 PM / 全栈工程师。一天会同时跑 3–8 个 Claude Code 会话，每个跑在不同 repo 上。痛点：

- 不知道哪个会话「卡住了」、哪个在「等审批」、哪个「跑完了」
- 切换需要在 iTerm tab、Cmd+Tab、Mission Control 之间反复跳
- 通知容易错过，回头来看时已经过了 10 分钟
- 复制别处的代码到终端，粘贴出来格式总是不对

---

## 2. Dashboard 在 NARC 中的角色

```
                    ┌─────────────────────────────────────┐
                    │  浮窗（48pt 圆形，永远在上）           │
                    │  - 单击 → 弹 Notification Panel     │
                    │  - 右键 → 召唤 / 隐藏 Dashboard     │← 本 brief 的对象
                    │  - 长按拖拽 → 移动                    │
                    └─────────────────────────────────────┘
```

Dashboard 是一个**独立的可缩放 macOS 窗口**（不是浮窗，不是 panel），右键浮窗或在 Dock 点击 NARC 图标时召唤。关闭窗口时 PTY 进程不死，下次召唤时 tab 完整保留。

---

## 3. 核心使用场景（典型一天）

| 时刻 | 用户行为 | Dashboard 应该展现 |
|---|---|---|
| 早 9:30 | 召唤 Dashboard，新建 3 个终端，分别跑 claude code 在不同 repo | 左侧 3 个 tab，自动按 cwd 命名 |
| 10:15 | 用户在 VS Code 写代码，Claude 跑到一半要审批 | tab 闪红，浮窗红点亮，回到 Dashboard 一眼能看到哪个 |
| 10:20 | 用户从 VS Code 复制一段代码粘到 claude prompt | 自动去掉 leading 缩进 |
| 11:00 | 用户专注敲代码，IM 来了消息 | Dashboard 顶部短暂滑出消息 ticker，不抢焦点 |
| 14:00 | 用户离开 1 小时回来 | 看到「3 个会话已完成、1 个等审批、1 个 stale」的清晰汇总 |
| 17:00 | 关闭 Dashboard 窗口去开会 | 子进程不死；下次召唤 tab 还在 |

---

## 4. 信息架构

### 4.1 整体布局

```
┌────────────────────────────────────────────────────────┐
│ [TopBar]  NARC Workspace · 3 个终端  ⌘⇧V 智能粘贴  [+] │
├──────────────┬─────────────────────────────────────────┤
│              │                                         │
│ [Sidebar]    │  [TerminalPane]                         │
│              │                                         │
│ ┃● claude-1  │  $ claude code                          │
│ ┃ └ 待审批 🔴│  > Read README.md                       │← 左侧脉动条 + tab 行红 wash
│              │  ✓ Read 1 file                          │
│  ● claude-2  │  > 帮我加一个 X 功能                    │
│    └ 思考中  │                                         │
│              │                                         │
│  ● term-3 🔴 │                                         │← 未读红点(状态变化但未被查看)
│    └ 已结束  │                                         │
│              │                                         │
├──────────────┴─────────────────────────────────────────┤
│ [BottomBar]  ~/projects/narc · 24 lines · zsh           │
└────────────────────────────────────────────────────────┘
```

**比例建议**：Sidebar 220–320pt 可拉伸；TerminalPane 撑满剩余空间；TopBar 44pt；BottomBar 24pt。

> **设计取向**：**sidebar 是 Dashboard 内唯一的通知 surface。** 不要再加顶部 ticker、右下浮卡、inline banner 这类平行通知组件——sidebar tab 本身就是实时状态监控器，把它的视觉密度做足即可。

---

### 4.2 各区域规范

#### TopBar（顶部工具栏）

- 左：图标 + "NARC Workspace" 标题 + "·" + "N 个终端" 计数
- 中：（预留位）
- 右：常驻"⌘⇧V 智能粘贴"提示 + 「+ 新建终端」按钮（capsule，accent color）
- 高度：44pt
- 视觉：semi-translucent，与 macOS 14+ 系统窗口工具栏一致

> **关于 ⌘⇧V 提示**：这个 chip 是为可发现性设计的——智能粘贴的快捷键不可能只用菜单暴露，所以工具栏右侧需要一个常驻的小提示让用户知道这个能力存在。chip 样式：图标 + 单色键帽 ⌘⇧V + "智能粘贴" 文字。

#### Sidebar（左侧 tab 列表）

> **核心设计原则**：sidebar 是 Dashboard 唯一的通知 surface，所以 tab 行需要承担"持续状态显示 + 瞬时变化提醒 + 事后查阅入口"三个角色。视觉层级要拉开。

每行 = 一个终端会话。**视觉结构（从左到右、从上到下）**：

```
┃ [● 状态点] [Title]                          [✏️ ✕ 或 🔴]
┃            ~/projects/repo  · 2m
┃            ⚠️ 待审批: rm -rf /tmp/old        ← Claude 状态徽章
↑
attention bar (3pt 宽，仅 needs-attention 时出现，红色 1Hz 脉动)
```

**三层 attention 视觉机制**：

| 层级 | 视觉 | 触发 | 含义 |
|---|---|---|---|
| **持续 attention** | 左侧 3pt 红色脉动条 + 行 wash 淡红 | Claude 处于 `waitingForApproval` | 用户必须现在处理 |
| **瞬时变化** | 右侧 8pt 红圆点 + 1pt 白边 | 状态从 X 变成 attention 状态时，且当前不是该 tab | 用户离开期间发生了变化 |
| **常态状态** | 仅状态点颜色 + 状态徽章文字 | 思考中 / 跑工具 / 等输入 等 | 知道在干什么就行，不用打扰 |

```
[● 状态点] [Title]                          [✏️ ✕]  ← hover 才显示
            ~/projects/repo  · 2m
            ⚠️ 待审批: rm -rf /tmp/old        ← Claude 状态徽章
```

**状态点颜色映射**：
| 颜色 | 含义 |
|---|---|
| 绿 (success) | 终端 alive，无 Claude 或 Claude 在等输入 |
| 蓝 (accent) | Claude 正在思考 / 跑工具 |
| 红 (danger) | Claude 等审批 |
| 黄 (warn) | Claude 在压缩上下文 |
| 灰 (faint) | 终端已 exit |

**Tab 行背景**：
- 待审批 → 淡红 wash + 选中时加深
- 选中 → accent 14% 透明
- hover → surface muted
- 默认 → 透明

**交互**：
- 单击 → 切换激活 tab
- 双击 title → 进入 inline rename（Esc 取消，Enter 提交）
- hover 出 ✏️（rename）✕（关闭）按钮
- 拖拽（未来）→ 重排序

#### TerminalPane（右侧终端区域）

- **完全是真实的 PTY-backed terminal**（用 SwiftTerm 渲染），渲染原生 ANSI
- 字体：SF Mono / Menlo 13pt（用户偏好可调，未来支持 ⌘+ / ⌘-）
- 背景：`NSColor.windowBackgroundColor` —— 跟 Dashboard 主题色统一（不是黑底）
- 前景：`NSColor.labelColor` —— 跟随明暗模式
- ANSI 16 色保持 SwiftTerm 默认 —— `git diff` `claude` 这类彩色输出要正常
- 滚动条：仅 hover 时显示
- 选中文本：自动复制到剪贴板（terminal 惯例）
- 多 tab 时，未激活的 tab `opacity = 0` 但**不释放**（PTY 后台继续跑）

#### BottomBar（底部状态栏，可选）

- 左：当前 tab 的 cwd（自动 ~ 折叠）
- 中：行/列数
- 右：shell 类型 + 持续时间
- 高度：24pt，字体 11pt monospace muted
- 用户切 tab 时实时刷新

---

## 5. 关键交互细节（必须支持）

### 5.1 智能粘贴（核心痛点）

**问题**：从 VS Code / Slack / Notion 复制带缩进的代码，粘贴后保留绝对缩进，用户再 yank 出来用就废了。

**期望行为**：粘贴时自动检测「最小公共缩进」并剥掉。例如：

```
原始（剪贴板）：
            const x = 1;
            const y = 2;
                const z = 3;

粘贴后（终端收到）：
const x = 1;
const y = 2;
    const z = 3;
```

**触发方式（待选）**：
- A 默认 Cmd+V 总是 dedent；YAML/Markdown 等会被误伤
- B Cmd+V 保持原样；Cmd+Shift+V 触发 dedent
- C 粘贴前弹出小预览（原始 / dedented / 包裹 markdown 三选一）

设计稿应该把这个交互体现出来（推荐 B 方案）。

### 5.2 跨 tab 持久化

关闭 Dashboard 窗口时**子进程不死**。设计稿应该有一个 affordance 表明「窗口关掉时不会丢」—— 例如顶部 close 按钮 hover 时 tooltip 写「关闭窗口（终端继续运行）」。

### 5.3 通知呈现 —— sidebar 是唯一通知 surface

**设计原则**：tab 本来就是终端实时状态的镜子。当 tab 状态变化或需要用户操作时，**优先在 tab 行上展示**，不要再加平行的通知组件（顶部 ticker、右下浮卡、inline banner 都不要）。

**三层视觉机制**（详见 §4.2 Sidebar）：

1. **持续 attention** —— 左侧 3pt 红色脉动条 + 行红 wash，只在 `waitingForApproval` 时启用
2. **瞬时变化** —— 右侧 8pt 未读红点（带白色 1pt 边），状态变化时且非当前 tab 才出现，用户切到该 tab 时自动消失
3. **常态状态** —— 状态点颜色 + 状态徽章文字（思考中/跑工具/等输入）

**为什么不要加新 surface**：用户在终端里专注敲代码，新加 surface 的代价是抢焦点；sidebar 在用户视线边缘，状态视觉可以做得很丰富但永远不抢焦点。

**预期结果**：用户离开 1 小时回来，扫一眼 sidebar 立刻知道：哪个完成了（绿点 + 红圆点）、哪个等审批（红色脉动条）、哪个在思考（蓝点）、哪个挂了（灰）。

### 5.4 全局快捷键（设计稿可在某处提示）

- `⌘⇧V` 智能粘贴（dedent，TopBar 已有提示）
- `⌘1` … `⌘9` 切到第 N 个 tab
- `⌘T` 新建终端
- `⌘W` 关闭当前 tab（带确认）
- `⌘+` / `⌘-` 调字号
- `⌘F` 终端内搜索（搜 scrollback）
- `⌘K` 清屏

---

## 6. 状态机 & 视觉差异

### Tab 状态对照表

| 状态 | 状态点 | Tab 背景 | 副标 |
|---|---|---|---|
| 空 / 刚启动 | 绿 | 默认 | shell 类型 + cwd |
| Claude 思考中 | 蓝 + 脉动 | 默认 | `⏳ 思考中…` |
| Claude 跑工具 | 蓝 | 默认 | `→ Read: README.md` |
| Claude 等审批 | 红 + 脉动 | 淡红 wash | `⚠️ 待审批: <tool>` |
| Claude 等输入 | 绿 | 默认 | `💬 等待输入` |
| Claude 压缩 ctx | 黄 | 默认 | `🗜 压缩上下文` |
| 进程 exit 0 | 灰（绿打勾） | 默认 | `✓ 已完成` |
| 进程 exit ≠ 0 | 红（暗） | 默认 | `❌ 异常退出` |

### 空状态

- 用户首次打开、还没新建任何 tab 时
- 中央大图标 + 主标题「还没有终端」+ 副标「点击右上角新建终端开始」+ 大号「+ 新建终端」按钮

---

## 7. 视觉风格倾向

**参考方向（按优先级）**：

1. **Warp.dev** —— 模块化命令块、状态条、清爽 UI 哲学
2. **Raycast** —— 列表行的密度、键盘优先、dark+light 主题
3. **macOS 14 Sonoma 系统应用**（Mail / Messages）—— 工具栏 / sidebar 比例

**避免**：
- 拟物化（gradient、阴影过重）
- 黑底彩色 ANSI 主题（这是 NARC，不是 iTerm —— 我们是「workspace」，要跟 macOS 系统应用统一）
- 过度图标化的左侧 nav（Slack 风）

**色彩 token（已有）**：
- accent: 系统蓝
- success: 系统绿
- warn: 系统橙
- danger: 系统红
- background: `NSColor.windowBackgroundColor`
- surface muted: 中性灰
- text: `NSColor.labelColor` / muted / faint 三档

明暗模式自动跟随系统。所有色彩通过 SwiftUI semantic colors 映射，**不要使用硬编码 hex**。

---

## 8. 边界场景（设计稿至少覆盖一个）

1. **20 个 tab**：sidebar 滚动条；快捷数字键超过 9 之后？
2. **超长 cwd**：`~/very/deep/path/that/is/too/long/to/show` —— 头部省略 `~/.../path`
3. **Claude 卡住 stale**：tab 应该黄色半透明 + "stale 2m" 副标
4. **进程 OOM 被杀**：tab 灰 + 死亡时间 + 一键「重启」按钮
5. **网络断开** / hook socket 挂了：顶部 banner「Hook 未连接，状态可能不准」+ 重试按钮

---

## 9. 我们已经做出的技术决定（设计可参考但不必拘泥）

- 实际渲染用 SwiftTerm（PTY-backed real terminal）
- 持久化 PTY（关窗不杀进程）
- Hook 数据通过 `NARC_SESSION_ID` env 关联到 tab
- macOS 14+ only，明暗模式跟随系统
- 不用 Electron / WebView，纯原生 SwiftUI + AppKit

---

## 10. 给 AI 的输出建议

**期望产出**：
1. 主界面高保真稿（含上述 5 个区域 + 至少 3 个 tab，至少 1 个处于"待审批"状态展示左侧脉动条 + 行红 wash）
2. tab 状态变化时未读红点出现的关键帧动画
3. 新建终端按钮 hover/active 状态
4. 空状态稿
5. 智能粘贴（5.1）的两态对比图：粘贴前的小预览卡片 / 粘贴后的终端
6. 顶部 ⌘⇧V 提示 chip 的细节图（图标 + 键帽 + 文字三段式）

**输出格式**（任选其一）：
- Figma 链接
- React + Tailwind 组件代码（v0 风格）
- HTML/CSS 静态页

**不需要**：图标自定义、Logo 重设计、营销页 / Landing。
