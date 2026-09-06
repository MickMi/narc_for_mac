[**中文**](README.md) | [English](README.en.md)

# NARC for Mac

> 一个常驻菜单栏、随时可召回到眼前的本地个人助手。

NARC 有两个始终可达的入口：顶部菜单栏提供稳定入口，桌面悬浮 `N` 锚定当前注意力。你不必离开正在工作的窗口，就能先记下一件事、感知应用级未读，或找回散落的窗口。

> **当前状态：v2 开发预览。** 源码安装、本地数据与召回定位逻辑已经通过本机或自动验证；菜单栏点击、全局快捷键、真实双显示器召回、全屏 Space 与首次权限路径仍在手工验收。当前版本不是稳定版承诺。

## 一条命令开始

需要 macOS 14 或更高版本、Git 与 Xcode Command Line Tools。首次构建需要网络。

复制这一行到终端：

```bash
git clone https://github.com/MickMi/narc_for_mac.git && cd narc_for_mac && bash scripts/install.sh
```

脚本会在本机从源码构建 NARC，放到 `~/Applications/NARC.app` 并启动。它不需要 `sudo`；完成后也不需要保持终端打开。

如果缺少 Xcode Command Line Tools，先运行：

```bash
xcode-select --install
```

NARC 坚持 source-only：这是唯一支持的普通用户获取方式。项目不提供 DMG、PKG、预编译 App ZIP 或二进制 GitHub Release，也不要求用户准备开发者证书、公证或执行手工签名。

## NARC 在哪里

NARC 是菜单栏应用，默认不显示 Dock 图标。

| 入口 | 动作 |
|---|---|
| 菜单栏 `N` 左键 | 召回桌面悬浮 `N`，并展开它旁边的轻量面板 |
| 菜单栏 `N` 右键 | 打开使用指南、偏好设置、关于或退出 |
| 桌面悬浮 `N` 左键 | 打开或关闭轻量面板 |
| 桌面悬浮 `N` 右键 | 打开 Assistant、使用指南或偏好设置 |
| `⌃⌥N` | 把悬浮 `N` 召回鼠标所在屏幕，并保持面板展开 |

悬浮 `N` 可以拖动，也可以在偏好设置中调整尺寸或重置位置。同一屏幕召回时保留你放置的位置；跨屏召回使用目标屏幕内的安全位置。

## 三条核心路径

### 1. 先记下来，再决定放哪

按 `⌃⌥Q`，或直接使用轻量面板中的随手箱：

1. 输入内容，不必先判断它是 Todo 还是 Note。
2. 按 Return 保存到本地 Inbox；空白内容不会提交。
3. 面板保留最近三条记录。
4. 稍后把记录显式转为 Todo 或 Note；转换成功后，原 Inbox 项不会重复保留。

重复呼出不会清空尚未提交的草稿。保存失败时，内容留在输入框中并显示错误。

完整 Assistant 使用独立窗口管理内容：Todo 可以切换完成状态，Notes 可以搜索和删除。

### 2. 感知应用级未读

NARC 聚合已启用应用暴露给 macOS 的 Dock Badge，默认关注微信、企业微信和飞书。聚合数字显示在菜单栏与桌面悬浮 `N` 上；超过 99 时显示 `99+`。

这个数字只代表应用级未读：

- NARC 不读取消息正文。
- NARC 不知道是哪一个会话产生了未读。
- 同一 App 存在多个系统实例时取可信的最大值，不重复相加。
- 如果目标 App 没有暴露可信 Badge，NARC 会在最后可信值后追加 `?`（例如 `14?`）；没有可信旧值时显示 `?`，不会把未知伪装成新的零。

### 3. 找回和排列窗口

这些能力需要 macOS 辅助功能权限：

| 快捷键 | 动作 |
|---|---|
| `⌃⌥P` | 标记当前窗口，稍后从面板找回 |
| `⌃⌥←` / `⌃⌥→` | 左半屏 / 右半屏 |
| `⌃⌥↑` / `⌃⌥↓` | 上半屏 / 下半屏 |
| `⌃⌥U` / `⌃⌥I` / `⌃⌥J` / `⌃⌥K` | 四个角落 |
| `⌃⌥↩` / `⌃⌥C` | 全屏 / 居中 |

5 秒内重复同一方向快捷键会尝试把窗口移动到相邻显示器。跨屏路径和全屏 Space 行为仍属于开发预览验收范围。

## 当前成熟度

| 能力 | 状态 | 当前边界 |
|---|---|---|
| GitHub 源码一条命令 | 已验证 | 本机构建、安装到用户 Applications 并启动；不产生安装包 |
| 菜单栏 + 桌面悬浮 `N` | 开发预览 | 无 Dock 与悬浮球点击已做本机检查；召回定位有自动测试，菜单栏、全局快捷键与真实双屏仍待验收 |
| Inbox 随手记 | 开发预览 | 持久化、迁移、草稿保留与转换有自动测试；完整真实交互继续验收 |
| Todo / Notes / Assistant | 开发预览 | 核心管理路径已接通，仍在补充真实交互覆盖 |
| 应用级未读 | 取决于目标 App | 只读取 macOS 可见的应用级 Badge，不保证每个 App 始终提供数值 |
| 窗口标记与排列 | 可用但需权限 | 多显示器、跨 Space 和部分窗口类型受 macOS 行为限制 |

详细状态见 [功能清单](docs/FEATURES.md)，版本范围见 [版本计划](docs/VERSIONS.md)。

## 首次使用与权限

首次打开随手箱时，入口内会显示一段简短引导。只有成功保存第一条记录，才算完成核心引导；选择“稍后”只对本次运行生效。

Inbox、Todo、Notes 和应用级 Badge 不需要辅助功能权限。NARC 不会在启动时主动索取辅助功能或通知权限；窗口工具会先解释用途，通知权限只在首次真实投递时请求。

窗口能力的授权位置：

**系统设置 → 隐私与安全性 → 辅助功能 → NARC**

## 数据与隐私

- Inbox、Todo 和 Notes 默认只保存在本机。
- 数据文件位于 `~/Library/Application Support/NARC/assistant-v1.json`。
- 旧数据会在保留现有 Todo 与 Note 的前提下迁移到当前格式。
- 当前版本不调用外部模型 API，也没有云同步或团队协作。
- NARC 不读取微信或企微消息正文，不使用截图 OCR、私有数据库、进程注入或非公开 Hook。

删除 App 不会自动删除个人记录，避免误删。

## 当前不做什么

- 不显示 Dock 图标，也不恢复 Workspace 或嵌入式终端入口。
- 不提供对话式 AI、自动分类或跨模块 AI 执行。
- 不连接 Apple Notes、Reminders、Calendar、GitHub 或其他外部服务。
- 不支持微信/企微会话级未读或消息正文。
- 不支持第三方动态插件、脚本市场或插件权限系统。
- 不提供自动更新、DMG、PKG、预编译 App 或签名公证分发链。

这些边界的目的是先把“捕获、感知、找回”做成可靠、低干扰的本地闭环。

## 更新

先从 NARC 菜单选择 **Quit NARC**，再在仓库目录运行：

```bash
git pull && bash scripts/install.sh
```

安装脚本不会强制关闭正在运行的 NARC，也不会删除个人记录。

## 卸载

1. 从 NARC 菜单选择 **Quit NARC**。
2. 删除 `~/Applications/NARC.app`。

个人记录仍会保留。只有确认不再需要数据时，才删除：

`~/Library/Application Support/NARC`

## 常见问题

### 看不到 NARC

NARC 默认不在 Dock 中。先看菜单栏中的 `N`，或运行：

```bash
open ~/Applications/NARC.app
```

如果 NARC 已经运行，按 `⌃⌥N` 可召回悬浮 `N`。

### 快捷键没有反应

- `⌃⌥N` 和 `⌃⌥Q` 在 NARC 启动后注册，不依赖辅助功能权限。
- 窗口标记和排列会在首次使用时说明并请求辅助功能权限。
- 如果快捷键被其他 App 占用，退出冲突 App 后重启 NARC。

### 企微或微信数字不一致

NARC 读取 macOS LaunchServices 暴露的 Dock Badge。目标 App 尚未登录、没有暴露 Badge、存在多实例或状态尚未刷新时，数字可能延迟；未知状态会显示 `?`，有最后可信值时会显示类似 `14?`。

### 更新时提示 NARC 正在运行

先选择 **Quit NARC**，然后重新执行：

```bash
bash scripts/install.sh
```

## 开发与验证

```bash
# 构建可运行的 Debug App
bash scripts/build-app.sh debug
open build/NARC.app

# 完整测试
swift test

# 防止误引入安装包、证书链或自动更新
bash scripts/verify-source-only-distribution.sh

# 只构建 Swift Package
swift build
```

技术栈：Swift 5.9 Package、SwiftUI + AppKit、macOS 14+。产品目标见 [PROJECT](docs/PROJECT.md)。
