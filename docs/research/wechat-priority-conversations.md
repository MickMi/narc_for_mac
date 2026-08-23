# 微信重点会话可行性研究

## v2.0.0 · 2026-08-20 · 微信重点会话可行性结论

### 结论

**可以做“重点会话书签”，当前不能可靠做“重点会话未读监听”。**

NARC 可以让用户手动记录一个重点微信会话，并把它与现有的微信应用级未读、窗口找回能力放在一起；但在当前微信 macOS 4.1.11 上，没有公开、稳定、可持续监听的会话对象或会话级未读状态。产品界面必须显示“状态不可见”，不能用 `0` 冒充“没有未读”。

v2.0 建议只交付安全且诚实的书签能力，不进入 OCR、私有数据库、进程注入或 Hook。若未来微信公开 API 或重新暴露稳定的 AX 会话行，再单独立项监听能力。

### 证据分层

#### 已验证事实

- 本机目标：微信 macOS 4.1.11（269136），Bundle ID `com.tencent.xinWeChat`。
- 只读 Computer Use 探针看到一个 735×861 顶层窗口；树中只有 10 个无语义标签节点。
- 当前树中有 0 个 list/row/scroll-area、0 个 selected 状态、0 个显式 unread/未读 token、0 个 AX 滚动动作。
- 探针未点击、未滚动、未输入，也没有保存联系人、群名或消息摘要。
- Apple Accessibility 可以从目标进程创建顶层 AX 对象并读取它实际支持的属性；相关调用也可能返回“不支持/无法完成”。[AXUIElementCreateApplication](https://developer.apple.com/documentation/applicationservices/1459374-axuielementcreateapplication?language=objc) · [AXUIElementCopyAttributeValues](https://developer.apple.com/documentation/applicationservices/1462060-axuielementcopyattributevalues)
- AXObserver 只能订阅目标 AX 元素实际支持的通知；官方 API 明确存在 `kAXErrorNotificationUnsupported`。[AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate?language=objc) · [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification) · [AX notification overview](https://developer.apple.com/documentation/applicationservices/axnotificationconstants_h)
- `UNUserNotificationCenter` 只能取回“本 App”的已送达通知，不能作为读取微信通知内容的公开入口。[getDeliveredNotifications](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getdeliverednotifications%28completionhandler%3A%29) · [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- Apple Vision 能在本机对图像做文字识别；若要持续获取微信窗口画面，ScreenCaptureKit 需要用户授予屏幕录制权限。[Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images) · [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)

#### 推断

- 当前微信把主要会话 UI 作为自绘/非语义节点暴露。即使屏幕上肉眼可见会话，NARC 也拿不到稳定的 AX row、identifier、selected 和 unread 属性。
- 没有会话元素时，AXObserver 无对象可订阅；轮询同一棵树也不会凭空获得会话级状态。
- 窗口标题最多可用于“找回一个独立窗口”，不是稳定会话 ID，也不能证明未读数；重命名、同名会话和窗口复用都会产生歧义。

#### 未验证

- 未确认微信未来版本是否会重新提供语义化会话列表。
- 未确认所有“独立聊天窗口”是否都暴露稳定且唯一的标题；本轮没有创建或操作用户会话窗口。
- 未找到微信官方面向 macOS 桌面客户端的会话/未读公开 API；这属于本次检索结果，不等于永远不存在。

### 方案对比

| 方案 | 能标记 | 能监听会话未读 | 隐私/权限 | 稳定性 | v2.0 决策 |
|---|---:|---:|---|---|---|
| 手动重点会话书签 + 微信应用级 Badge | 是 | 否，显示“状态不可见” | 低；只存用户输入的名称/备注 | 高 | **Go** |
| 独立微信窗口 + 现有窗口钉选 | 是，标记窗口 | 否 | 辅助功能 | 中；标题/窗口会变化 | **Go，作为窗口能力说明** |
| AX 会话行 + AXObserver | 理论上是 | 理论上是 | 辅助功能 | 当前无会话行，无法实施 | **No-Go，等待上游变化** |
| ScreenCaptureKit + Vision OCR | 可识别可见文本 | 只能猜测可见区域 | 屏幕录制；会处理私密界面 | 低；布局、缩放、主题、虚拟滚动都会破坏结果 | **No-Go，非默认产品路径** |
| 私有数据库 / 注入 / Hook | 可能 | 可能 | 高风险，越过公开边界 | 极低，升级即破坏 | **永久 No-Go** |

### 推荐的安全 MVP

1. 在 Assistant 中新增“重点会话书签”，由用户显式输入名称和可选备注。
2. 每个书签只显示微信应用级状态：`微信未运行`、`微信运行中 · App 未读 14` 或 `App 未读不可见`。
3. 会话级状态固定显示 `未读状态不可见`，禁止显示推测数字。
4. 操作只提供“打开微信”和“关联当前独立窗口（可选）”；窗口关联复用现有 PinnedWindow 能力。
5. 本地只保存书签文案、关联窗口的现有引用和时间戳；不保存截图、不采集消息正文。
6. 微信升级或关联失效时，明确显示“需要重新关联”，不静默指向别的会话。

这个 MVP 解决的是“我有哪些重点对象、快速回到微信”，不是“精确知道哪个会话来了几条消息”。两者必须在命名和验收标准上分开。

### 工作量估算

| 范围 | 估算 | 说明 |
|---|---:|---|
| 书签数据模型、增删改查、Assistant 列表 | 2–3 天 | 复用现有本地 AssistantStore 与模块框架 |
| 关联微信应用级 Badge、打开微信、失效状态 | 1–2 天 | 复用 AppMonitorService；不读消息内容 |
| 可选关联独立窗口、回归与文档 | 2–3 天 | 复用 PinnedWindowService，接受标题歧义并显式提示 |
| 合计可发布 MVP | 5–8 个工程日 | 含测试与真实交互 QA，不含设计大改 |
| OCR 实验 | 1–2 周原型 | 仍不能保证准确率、后台可见性或虚拟列表完整性 |
| OCR 产品化 | 不建议排期 | 权限与隐私成本高，可靠性不满足个人助手的信任要求 |

### 重新评估触发条件

只有出现以下任一证据才重开“会话级监听”方案：

- 微信官方提供桌面会话/未读 API；
- 真实微信版本稳定暴露可枚举的 AX 会话 row、唯一标识和 unread/value，并能通过 AXObserver 收到变化；
- 用户明确接受屏幕录制与可见区域 OCR 的隐私/误报边界，且原型达到事先约定的准确率与资源占用门槛。

在此之前，版本计划只登记“重点会话书签”，不得写成“重点会话监听已支持”。
