[English](README.en.md) | **中文**

# NARC for Mac

**Notification & Application Resource Center**

把 IM 通知、Claude Code 会话、窗口操作收进一个桌面浮球里。NARC 是 macOS 开发者的注意力守门人——补充终端能力，而不是替代终端能力。

> 仓库名 `narc_for_mac`，产品名 **NARC**。

## 为什么需要它

单用一个终端、一个 IDE、一个显示器时，你不会觉得有什么问题。但当你的日常工作变成这样：

- 微信角标亮了 → ⌘Tab 切过去 → 发现是群公告 → 切回来 → 忘了刚才在干嘛
- Claude Code 在某个 iTerm 标签页里等权限审批 → 你不知道 → 3 分钟后才想起来去看 → 已经超时了
- 4 个项目开了 6 个终端窗口，分布在 3 个 Space → 每次找对窗口都要划触摸板 → 一天重复几十次
- 钉了一个参考文档窗口在 Space 2 → 需要看时 ⌘Tab 翻 20 个应用找不到 → 只能重新打开
- 窗口拖到屏幕左边，再拖一个到右边，第三个居中——每天做几十次窗口排列

你会发现，打断你的不是某个大问题，而是无数微操作的累积。**注意力被切碎，上下文被冲走，操作被重复浪费**。

NARC 解决的就是这个碎片化——把三类隐性成本收敛到一个 48pt 的圆圈里。

## 适合谁

NARC 适合这些场景：

- 每天在终端里跑 Claude Code，经常被权限审批打断
- 同时用微信、企业微信、飞书，不想分别检查未读消息
- 多显示器、多 Space 工作流，频繁在窗口间切换
- 习惯纯键盘操作，想用快捷键代替拖拽
- 想在一个窗口里管理所有 Claude Code 会话状态，不需要记住"标签页 3 是哪个项目"

**如果你只是偶尔在 IDE 里用 AI 补全、不需要 IM 通知管理、单显示器单 Space 工作——NARC 对你来说可能太重了。** 它是一个面向重度终端 + AI 工作流用户的注意力管理工具。

## 5 分钟开始

### 1. 构建

```bash
git clone https://github.com/MickMi/narc_for_mac.git
cd narc_for_mac
./scripts/build-app.sh
open build/NARC.app
```

构建脚本使用固定的 `NARC Dev` 身份签名。重新构建后辅助功能权限不会丢失。

### 2. 安装 Claude Code Hook（可选，但建议安装）

```bash
cp scripts/narc-hook.py ~/.claude/hooks/narc-hook.py
chmod +x ~/.claude/hooks/narc-hook.py
```

然后在 `~/.claude/settings.json` 中加入：

```json
{
  "hooks": {
    "PermissionRequest": [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "Stop":              [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "SessionStart":      [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }],
    "SessionEnd":        [{ "type": "command", "command": "python3 ~/.claude/hooks/narc-hook.py" }]
  }
}
```

### 3. 首次启动

NARC 会提示授予**辅助功能权限**（系统设置 → 隐私与安全性 → 辅助功能）。授权后重启 NARC。

### 4. 验证加载

做完上面三步后，确认这些表现：

- 屏幕右下角出现一个浮动圆圈，角标显示聚合未读数
- 左键点击圆圈 → 通知面板滑出，显示微信/企业微信/飞书的运行状态
- 右键点击圆圈 → 仪表盘打开，点击"+ 新建终端" → 输入 `claude` → 新标签页中出现交互终端
- `⌃⌥N` 切换面板，`⌃⌥→` 把当前窗口贴到右半屏，`⌃⌥P` 钉选当前窗口

**如果浮动圆圈没有出现**：检查辅助功能权限是否已授予并重启 NARC。

## 成功后应该看到什么

浮动圆圈（右下角，48pt，始终置顶）：

- **红色角标** — IM 消息 + Claude 待审批的聚合数
- **左键** → 通知面板（IM 状态、Claude 审批、钉选窗口）
- **右键** → 工作区仪表盘（多终端标签页 + 实时 Claude 状态）

仪表盘内：

- 每个标签页显示 **Claude 实时状态徽章**：`⏳ 思考中` / `⚠️ 待审批` / `💬 等待输入` / `■ 已结束`
- Claude 等待审批时，对应标签页**闪烁红色**
- 关闭仪表盘窗口，终端会话**继续运行**；重新打开从上次位置继续

| 以前 | 现在 |
|------|------|
| ⌘Tab 切 3 个 IM 应用检查角标 | 看一眼浮动圆圈 |
| 翻 iTerm 标签页找等审批的 Claude 会话 | 看到红色闪烁标签 → 点一下 |
| 拖窗口排列 | `⌃⌥→` 半屏，`⌃⌥C` 居中 |
| 划触摸板在 Space 间找钉住的窗口 | `⌃⌥P` 钉选 → 面板点击跳转 |

## 核心能力

| 能力 | 支持 | 说明 |
|------|------|------|
| 统一 IM 通知源（微信/企业微信/飞书） | ✅ | 一个聚合角标替代三个分散通知源 |
| Claude Code 会话状态实时监控 | ✅ | 通过 Unix Socket + Python Hook 感知 6 种状态 |
| 嵌入式多终端仪表盘 | ✅ | 基于 SwiftTerm，关闭窗口不杀进程 |
| 键盘驱动窗口贴靠（10 种布局） | ✅ | 单次 setFrame 调用，零延迟 |
| 跨 Space 窗口钉选与激活 | ✅ | AppleScript 驱动，无动画闪烁 |
| 强制 Claude Code 100% 响应及时 | ❌ | 它监控状态并通知你，不控制执行 |
| 跨 Space 窗口激活 100% 成功 | ❌ | AppleScript 依赖窗口标题匹配；极端相似标题可能歧义 |
| 企业微信角标 100% 准确 | ❌ | WeCom 使用自定义 Dock 渲染，`lsappinfo` 无法保证始终检测到 |
| 消息内容预览（"谁发了什么"） | ❌ | v2.1 规划中，当前只读角标数 |
| 自动更新 | ❌ | v1.5 规划中（Sparkle 框架） |

**一句话：NARC 把"被动感知消息"、"主动管理窗口"、"随时掌控 Claude 会话"三件事收进一个浮球。它不是万能面板——它专注解决重度终端用户的三类注意力税。**

## 它会改哪些文件

| 操作 | 写入位置 | 用途 | 回滚方式 |
|------|---------|------|---------|
| `./scripts/build-app.sh` | `build/NARC.app` | 构建产物 | `rm -rf build/` |
| `cp scripts/narc-hook.py ...` | `~/.claude/hooks/narc-hook.py` | Claude Code 事件拦截 | `rm ~/.claude/hooks/narc-hook.py` |
| 编辑 `settings.json` | `~/.claude/settings.json` | Hook 注册（手动编辑） | 删除 hook 配置块 |
| 正常使用 | `~/Library/Preferences/com.narc.NARC.plist` | 应用偏好与钉选窗口 | `defaults delete com.narc.NARC` |
| `cp -R build/NARC.app /Applications/` | `/Applications/NARC.app` | 安装至 Applications（可选） | 拖入废纸篓 |

## 工作原理

NARC 有四层：

| 层 | 职责 | 关键文件/技术 |
|----|------|-------------|
| 感知层 | Dock 角标轮询、Claude 事件监听、快捷键注册 | `AppMonitorService` (lsappinfo)、`ClaudeSessionService` (Unix Socket)、`HotkeyService` (Carbon Event) |
| 状态层 | 会话生命周期管理、窗口状态机、钉选持久化 | `TerminalSessionManager`、`WindowLayoutState` (5s TTL)、`PinnedWindowService` (AppleScript) |
| 视图层 | 浮动组件、通知面板、仪表盘、Toast 横幅 | SwiftUI + AppKit (NSPanel)、SwiftTerm 嵌入式终端 |
| 集成层 | Claude Code Hook 事件路由、`NARC_SESSION_ID` 注入 | Python hook → Unix Socket → 精准标签页匹配 |

推荐的交互拓扑：

```text
macOS Dock Badge (lsappinfo)
        │
        ▼
  NARC 浮动圆圈 ──左键──▶ 通知面板（IM + Claude + 钉选）
        │
     右键
        │
        ▼
  工作区仪表盘 ──▶ 标签页 1: Claude Code (project A)
               ──▶ 标签页 2: Claude Code (project B)
               ──▶ 标签页 3: zsh (server logs)
               ──▶ 标签页 4: claude (debug session)
        │
  NARC_SESSION_ID ──▶ Hook 事件路由回对应标签页
```

## 快捷键

日常高频只用这几个：

| 快捷键 | 效果 |
|--------|------|
| `⌃⌥N` | 开关 NARC 面板 |
| `⌃⌥→` | 当前窗口 → 右半屏 |
| `⌃⌥←` | 当前窗口 → 左半屏 |
| `⌃⌥P` | 钉选当前窗口 |
| `Esc` | 关闭面板 |

完整列表：

```text
⌃⌥←  ⌃⌥→  ⌃⌥↑  ⌃⌥↓    半屏（左/右/上/下）
⌃⌥U  ⌃⌥I  ⌃⌥J  ⌃⌥K    四角（左上/右上/左下/右下）
⌃⌥↩  ⌃⌥C               全屏 / 居中
```

**跨屏技巧**：5 秒内按同一方向键两次 → 窗口跳到相邻显示器。

## 设计原则

- **浮球不挡路**：48pt 圆形，始终置顶，拖拽自由。128×128 透明画布让阴影不裁剪，但只有中央 48pt 可点击。
- **关闭 ≠ 杀死**：仪表盘窗口关闭后 PTY 子进程继续运行。灵感来自 tmux 的 detach——窗口只是视图，会话才是资产。
- **状态可见，不被打断**：角标和徽章让你感知状态而不必切换上下文。只有 Claude 等审批时才主动闪烁红色。
- **纯键盘优先**：窗口贴靠和钉选都是两次按键完成。不需要精确拖拽或记住 Space 编号。
- **稳定身份**：自签名使用固定的 `NARC Dev` 身份，cdhash 跨构建不变，辅助功能权限不丢失。
- **不做万能面板**：NARC 不读消息内容（v2.1 前），不替代 iTerm，不管理 Dock。聚焦三类注意力税，其他的留给专用工具。

## 当前限制

- Prompt 约束无法保证 Claude Code 100% 及时响应；它监控状态并通知，不控制执行
- 跨 Space 窗口激活依赖 AppleScript 标题匹配；高度相似的窗口标题可能定位错误
- 企业微信角标依赖 `lsappinfo` CLI；WeCom 的自定义 Dock 渲染可能导致漏检
- Claude Code Hook 需要手动安装（复制脚本 + 编辑 settings.json），尚未自动化
- 嵌入式终端中，少数 kitty 键盘协议专用组合键可能与原生终端表现不同
- 暂无自动更新机制（v1.5 规划 Sparkle）
- 窗口贴靠不支持自定义布局比例（如 1/3 屏），目前只有固定预设

## 路线图

| 版本 | 重点 |
|------|------|
| **v1.3** ← 当前 | 工作区仪表盘、D 规范浮动组件、面板 Claude 出口 |
| v1.4 | 标签页字号 `⌘+`/`⌘-`、`⌘1`–`⌘9` 切换、拖拽排序标签页、回滚搜索 |
| v1.5 | Developer ID 签名 + 公证 + GitHub Release CI |
| v2.0 | IDE 任务监控（VS Code 扩展桥接） |
| v2.1 | 消息内容预览 |
| v3.0 | 第三方集成插件系统 |

## 开发与验证

```bash
# 完整构建
./scripts/build-app.sh

# 开发模式运行
swift run -c release NARC

# 检查 App 是否被 Gatekeeper 接受
spctl --assess --verbose build/NARC.app

# 验证辅助功能权限
tccutil reset Accessibility com.narc.NARC   # 重置后重启 NARC 测试授权流程

# 验证 Hook 通信
echo '{"event":"test"}' | nc -U /tmp/narc-claude.sock
```

项目语言 Swift 5.9，UI 框架 SwiftUI + AppKit，嵌入式终端基于 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)，最低部署目标 macOS 14 Sonoma。

## 许可证

MIT

---

*基于 Swift、SwiftUI、SwiftTerm 以及大量 ⌃⌥ 组合键构建。*
