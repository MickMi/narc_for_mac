# NARC Personal Assistant — Design Brief

## v2.0.0 · 2026-08-20 · Quick Capture、Todo 与 Notes

### 一句话需求

让用户通过统一的 NARC 助手入口，在数秒内记下 Todo 或 Note，并在轻量 Assistant Hub 中重新查看和管理记录。

### 用户目标

- 用户正在终端、IDE 或其他 App 中工作时，不需要切换上下文即可记下一件事。
- 用户明确知道本次保存为 Todo 还是 Note，不依赖尚未接入的 AI 自动判断。
- 保存结果可以在 Assistant Hub 中重新找到，并且 App 重启后仍然存在。
- 保存失败时用户看得见原因，输入不会消失，也不会被成功动画误导。

### 入口关系

1. **Quick Capture**：全局快捷键为最高频入口；Panel 同时提供可发现按钮。
2. **Assistant Hub**：Panel 提供固定入口，用于查看 Todo 与 Notes。
3. **Workspace**：本版本从 Panel、右键菜单、偏好设置、Dock 重开和全局快捷键中软下线；底层仅保留一版用于回滚，不再与 Assistant 并列展示。

新全局快捷键在实现阶段完成冲突验证后锁定；设计稿只预留快捷键提示位置，不先写死组合键。

### Quick Capture

#### 形态

- 独立轻量浮层窗口，宽度约 440pt，高度随错误反馈小幅变化，不承载完整列表。
- 打开后输入框立即聚焦；窗口出现位置以当前鼠标屏幕或当前活动屏幕居中偏上为优先。
- 主体仅包含类型选择、输入区、提交动作和必要反馈，避免变成第二个 Assistant Hub。

#### 信息层级

1. 顶部：`Todo` / `Note` 双态选择，默认恢复上一次显式选择仅作为便利，不代表 AI 推断。
2. 中部：单一文本输入区；Todo 使用单行意图，Note 允许多行内容。
3. 底部：当前提交类型、确认键提示和取消提示。
4. 错误态：输入区下方显示一行可理解错误，不弹成功 Toast 掩盖失败。

#### 状态

| 状态 | 行为与反馈 |
|---|---|
| 初始 | 输入自动聚焦，提交不可用 |
| 有内容 | 提交可用，类型切换不清空输入 |
| 空白提交 | 不关闭窗口，输入区显示轻量校验反馈 |
| 保存中 | 防止重复提交，保留文本，不使用长期加载动画 |
| 保存成功 | 清空输入并关闭；真实 Store 状态已经更新后才能触发 |
| 保存失败 | 窗口保持、文本保留、错误可见，可再次提交或取消 |
| 取消 | 不保存并关闭；再次打开不恢复已取消草稿 |

### Assistant Hub

#### 形态

- 使用标准可调整大小的 NARC 窗口，与 Preferences 的标题栏行为一致。
- 默认内容由 `Todo` 与 `Notes` 两个顶层页面构成；不在 v2.0 加入聊天区、插件市场或 Workspace 镜像。
- 顶部始终提供 Quick Capture 入口，让“查看”与“快速新增”形成闭环。

#### Todo 页面

- 默认先展示未完成项目，再展示可折叠的已完成项目。
- 每行至少包含完成控件、标题和创建时间；v2.0 不展示尚未实现的截止日期、项目层级或提醒。
- 切换完成状态后立即反映真实 Store 状态；持久化失败必须回滚视觉状态或显示明确失败，不允许假完成。
- 空状态描述下一步动作，并提供新增入口。

#### Notes 页面

- 顶部提供本地搜索，搜索只过滤当前真实记录，不显示伪造摘要。
- 每行显示正文预览和更新时间；正文不完整展示时必须有明确截断。
- 删除动作需要可理解的确认或可撤销反馈；v2.0 不提供富文本、文件附件和云同步状态。
- 空状态与“搜索无结果”必须区分。

### 视觉复用

- 色彩仅使用 `Color.narcBackground`、`narcSurface`、`narcSurfaceMuted`、`narcText`、`narcTextMuted`、`narcAccent`、`narcSuccess`、`narcDanger`。
- 字体使用 `narcTitle`、`narcSubtitle`、`narcBody`、`narcCaption` 和 `narcMonoSmall`。
- 间距使用 `NarcSpacing`；圆角使用 `NarcRadius` 连续曲率；列表行优先复用 `softRowBackground`。
- 动画仅使用 `narcSnap` / `narcEase`，并尊重 Reduce Motion。
- 不新增 Design Token，不修改 Workspace 的 DesignTokens v5.5 语义。

### 键盘与可访问性

- Quick Capture 打开后必须能不碰鼠标完成：切换类型、输入、提交、取消。
- `Esc` 取消，提交键行为在实现阶段统一；多行 Note 不得因普通换行意外提交。
- Todo 完成控件、Note 删除动作、类型选择和搜索均需可读 accessibility label。
- 颜色不能成为 Todo 完成、保存失败或类型选择的唯一状态表达。

### 明确排除

- 不设计 AI 对话、自动分类置信度、模型选择或 Token/费用界面。
- 不设计 Apple Notes、Reminders、Calendar、GitHub 等连接器状态。
- 不设计动态插件安装、权限审批或插件市场。
- 不重排 Panel 当前 Notifications / Windows，不继续设计 Workspace 的新功能。

### Interaction QA

1. Quick Capture 打开后焦点正确，Todo/Note 往返切换不丢输入。
2. 空白、成功、保存失败、取消四条路径都有不同且真实的反馈。
3. Todo 创建与完成状态在重启后保持。
4. Note 创建、搜索和删除在重启后保持，空状态与无结果状态不同。
5. Assistant Hub 与 Panel 往返开关互不抢焦点；`⌃⌥W` 不再注册，Dock 重开和悬浮窗右键均进入 Assistant。

### 设计交付边界

本阶段复用既有组件和 Token，可直接按本简报实现功能性 SwiftUI；如果实现过程中需要新的视觉结构或 Token，必须暂停并回到设计评审，不由 Executor 临时发明。

## v2.0.0 · 2026-08-20 · Assistant 主入口与统一标记

### 品牌标记

- Dock 图标与桌面悬浮圆点统一使用 Heavy 大写 `N`，不再同时出现 `N` 与微型 `NARC` 两套字标。
- Dock 图标以 CoreText 字形轮廓的可见边界在蓝色圆角矩形内居中，禁止用字体行高或经验乘数定位。
- 悬浮 `N` 按 40pt、48pt、58pt 三档圆点等比缩放，并以 0.5pt 光学校正补偿字体 descender 空间。
- 通知数字仍位于圆点右上角，品牌标记变化不得改变 Badge、拖拽、呼吸或 Reduce Motion 状态。

### 主入口

- Dock 重开 NARC：打开 Assistant Hub。
- 悬浮圆点左键：保持打开快速面板；右键菜单第一项改为 Assistant Hub。
- 快速面板：保留 Quick Capture、Assistant、Preferences 与关闭按钮，不出现 Workspace。
- 偏好设置：不出现 Workspace 页签或 `⌃⌥W`；底层 Workspace 设置实现不属于用户可见设计。

### 视觉验收

1. Dock `N` 的可见包围盒中心与蓝色背景中心一致，不出现明显下沉。
2. Small、Medium、Large 三档悬浮圆点的 `N` 不裁切、不偏移，呼吸动画只改变透明度。
3. 企微真实 Badge 出现时，数字覆盖层不挤压或移动中心 `N`。
4. 所有可见入口中不再出现 Workspace 文案、图标或 `⌃⌥W` 提示。
