[English](README.en.md) | **中文**

# NARC for Mac

> 一个常驻桌面的本地个人助手：随手记录、感知未读、找回窗口，不打断当前工作。

NARC 把三个高频动作收进一个悬浮 `N`：快速写下 Todo/Note、查看应用级未读、标记并重新找到重要窗口。它不替代终端、笔记软件或任务管理平台，而是减少在它们之间来回切换的成本。

> **当前状态：v2.0 开发中。** GitHub 本地安装、首次指南和核心能力已经接通；Quick Capture、Todo、Notes 等完整交互仍在持续验收，不作为正式发布版本承诺。

## 30 秒开始

### 1. 安装

需要 macOS 14 或更高版本。复制这一行到终端：

```bash
git clone https://github.com/MickMi/narc_for_mac.git && cd narc_for_mac && bash scripts/install.sh
```

首次构建需要网络，可能持续几分钟。脚本会检查环境，在本机准备好 NARC，放到 `~/Applications/NARC.app` 并启动；不需要 `sudo`，完成后也不需要保持终端打开。

这是 NARC 唯一支持的普通用户获取方式：项目不提供 DMG、PKG、预编译 App ZIP 或 GitHub Release 安装包，也不要求准备开发者证书、公证或手工签名。

如果提示缺少 Xcode Command Line Tools，先运行：

```bash
xcode-select --install
```

安装完成后，再执行上面的 NARC 安装命令。

### 2. 记住两个动作

| 动作 | 结果 |
|---|---|
| 点击桌面悬浮 `N` | 查看应用未读、监控状态和已标记窗口 |
| 按 `⌃⌥Q` | 随时记录一条 Todo 或 Note |

次级入口：

- 右键悬浮 `N`：打开 Assistant、使用指南或偏好设置。
- `⌃⌥N`：在鼠标所在屏幕开关 NARC 面板。
- 再次启动：打开 `~/Applications/NARC.app`，或运行 `open ~/Applications/NARC.app`。

首次启动会显示一张简短使用指南。完成后不会每次重复弹出，可随时从悬浮 `N` 的右键菜单重新打开。

### 3. 按需开启窗口权限

Todo、Notes、Quick Capture 和应用未读聚合可以直接使用。只有窗口排列、钉选和重新激活其他 App 的窗口需要辅助功能权限：

**系统设置 → 隐私与安全性 → 辅助功能 → NARC**

## 为什么需要 NARC

真正消耗注意力的通常不是一个大任务，而是反复出现的小切换：

- 临时想到一件事，必须离开当前窗口才能记下来。
- 微信、企业微信和飞书分别出现角标，需要逐个切换确认。
- 参考资料、项目窗口散落在多个显示器或 Space，稍后很难找回。
- 同样的窗口排列动作每天重复很多次。

NARC 的目标不是把所有工具塞进一个工作台，而是让“捕获、感知、找回”始终只隔一个动作。

## 三个核心能力

### 1. 随手记录

- **Quick Capture**：按 `⌃⌥Q`，显式选择 Todo 或 Note 后保存。
- **Todo**：查看未完成/已完成事项并切换完成状态。
- **Notes**：保存、搜索和删除本地便签。
- **Assistant**：集中查看 Todo、Notes，并再次打开 Quick Capture。

数据保存在 `~/Library/Application Support/NARC/assistant-v1.json`。

### 2. 感知应用未读

- 聚合微信、企业微信和飞书暴露给 macOS Dock 的应用级 Badge。
- 悬浮 `N` 上的红色数字是已启用监控应用的聚合未读数。
- 查询暂时失败时保留最后可信状态，避免把“未知”伪装成新的零未读。

NARC 当前不读取消息正文，也不能判断具体是哪个微信会话产生了未读。

### 3. 找回和排列窗口

- `⌃⌥P`：标记当前窗口，稍后从 NARC 面板快速找回。
- `⌃⌥←` / `⌃⌥→` / `⌃⌥↑` / `⌃⌥↓`：移动到左右上下半屏。
- `⌃⌥U` / `⌃⌥I` / `⌃⌥J` / `⌃⌥K`：移动到四个角落。
- `⌃⌥↩` / `⌃⌥C`：全屏 / 居中。
- 5 秒内重复同一方向快捷键：移动到相邻显示器。

## 当前功能状态

| 能力 | 状态 | 当前边界 |
|---|---|---|
| GitHub 本地准备与首次指南 | 可用 | 一条源码命令，本机生成 App；没有预编译安装包或自动更新 |
| Quick Capture / Todo / Notes | 开发中可用 | 本地持久化已覆盖，完整真实交互仍在持续验收 |
| 应用级未读聚合 | 可用 | 取决于目标 App 是否向 macOS 暴露有效 Dock Badge |
| 窗口标记与排列 | 可用 | 需要辅助功能权限，跨 Space 找回可能受窗口标题变化影响 |
| 微信重点会话书签 | 已研究、未实现 | 可以做显式书签，但不能承诺会话级未读监听 |
| 对话式 AI 与跨模块执行 | 未实现 | 模型、费用、隐私和动作确认边界留到后续版本 |

更细的成熟度记录见 [功能清单](docs/FEATURES.md)，版本归属见 [版本计划](docs/VERSIONS.md)。

## 数据与隐私

- Todo 和 Notes 默认只保存在本机，不上传云端。
- v2.0 不调用外部模型 API，也没有团队协作或云同步。
- NARC 只读取目标 App 提供给 macOS 的应用级 Badge，不读取微信/企微消息正文。
- 微信重点会话方案不使用截图 OCR、私有数据库、进程注入或非公开 Hook。
- 卸载 App 不会自动删除 Todo/Note 数据，避免误删；完全清空需要用户显式操作。

微信细粒度能力的真实证据和方案比较见[重点会话可行性研究](docs/research/wechat-priority-conversations.md)。

## 更新

先从 NARC 菜单选择 **Quit NARC**，再在仓库目录运行：

```bash
git pull && bash scripts/install.sh
```

如果终端当前不在仓库目录，先运行 `cd narc_for_mac`。安装脚本不会强制关闭正在运行的 NARC。

## 卸载

1. 从 NARC 菜单选择 **Quit NARC**。
2. 删除 `~/Applications/NARC.app`。

卸载 App 不会自动删除 Todo/Note。如果希望完全清空，再手动删除 `~/Library/Application Support/NARC`。

## 常见问题

### 没有看到悬浮 N

```bash
open ~/Applications/NARC.app
```

如果 App 已运行，点击 macOS 菜单栏中的 NARC 图标，选择 **Show NARC**。

### `⌃⌥Q` 或窗口快捷键无反应

- `⌃⌥Q` / `⌃⌥N` 会在 NARC 启动后注册，不依赖辅助功能权限。
- 窗口排列和钉选需要辅助功能权限。
- 如果快捷键被其他 App 占用，先退出冲突 App，再重启 NARC。

### 企微/微信数字不一致

NARC 读取 macOS LaunchServices 提供给 Dock 的 Badge 状态。目标 App 没有暴露 Badge、仍在登录，或多实例状态尚未刷新时，数字可能延迟或暂时不可见。

### 更新时提示 NARC 正在运行

从 NARC 菜单选择 **Quit NARC**，然后重新运行：

```bash
bash scripts/install.sh
```

## 当前产品边界

- Workspace 和嵌入式终端已从用户入口软下线；底层代码只保留一版用于回滚。
- 当前不支持微信/企微消息正文、会话级未读或自动标记重点会话。
- 当前没有云同步、多人协作、快捷键自定义或自动更新。
- 分发边界固定为 GitHub 源码一条命令；不提供 DMG、PKG、预编译 App ZIP、GitHub Release 安装包，也不规划签名证书和公证流程。
- 当前“插件化”是编译期内置模块契约，不支持安装第三方动态插件或脚本市场。
- NARC 是本地个人助手入口，不替代完整的终端、笔记、任务管理或沟通工具。

## 开发与验证

```bash
# Debug App
bash scripts/build-app.sh debug
open build/NARC.app

# 完整测试
swift test

# 源码分发边界检查
bash scripts/verify-source-only-distribution.sh

# 只构建 Swift Package
swift build
```

技术栈：Swift 5.9 Package、SwiftUI + AppKit、macOS 14+。产品目标与设计边界见 [PROJECT](docs/PROJECT.md)。

## 许可证

MIT
