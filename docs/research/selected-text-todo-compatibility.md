# 划词创建 Todo · 标准选区读取兼容矩阵

## v2.0.0 · 2026-09-11 · 划词读取兼容性 Gate

### 当前结论

本文件建立 `assistant-022` 的真实应用验收矩阵与证据格式。当前只完成了本机系统、应用版本和现有源码边界的只读核对，**尚未执行任何一行真实选区读取测试**；因此下方所有 App × Surface 行均标为“待验证”，不能据此宣称支持。

第一阶段只允许在用户按下专用全局快捷键时，锁定当时的前台 App 与焦点控件，再通过 macOS Accessibility 的标准文本属性发起一次选区读取；读取成功后形成本次快照，并把确认后的内容写入 NARC 唯一的本地 `AssistantStore`。本阶段明确不使用以下回退：

- 不读取或改写系统剪贴板；
- 不模拟 `⌘C`、鼠标拖选或其他键盘事件；
- 不持续监听选区、窗口内容或用户输入；
- 不使用 OCR、屏幕录制、AI、私有接口或无界 AX 树扫描；
- 不把无法读取、超时或空选区猜成一条 Todo。

### 证据分层

| 层级 | 含义 | 当前可用于什么结论 |
|---|---|---|
| 静态证据 | 源码、Bundle `Info.plist`、本机系统版本或公开 API 边界 | 只能证明实现/环境事实，不能证明某个 App 的选区可读 |
| 真实应用证据 | 在指定版本、指定界面、指定夹具上执行完整快捷键路径，并核对 UI 与本地数据 | 可以判定该 App × Surface 在本次环境下的结果 |
| 待验证 | 尚未跑真实快捷键路径，或证据字段不完整 | 不得标为“支持”“有条件支持”或“不支持” |

### 判定定义

| 判定 | 必须同时满足的条件 |
|---|---|
| 直接支持 | 同一界面连续 10 次均精确读取标准夹具；每次只新增 1 条 Todo；焦点保持在来源 App；剪贴板 `changeCount` 不变；无权限、空选区、长按和撤销路径也通过 |
| 有条件支持 | 真实证据证明仅在明确、可复现且能向用户解释的条件下可用，例如只支持输入框、不支持网页正文；条件外必须明确失败且零写入 |
| 不支持 | 在权限有效、夹具有效且排除瞬时错误后，标准 AX 路径仍稳定不提供选区；NARC 明确反馈不兼容且没有回退或数据写入 |
| 瞬时失败 | 出现 `cannotComplete`、目标进程切换、元素失效或超时等暂态结果；只允许提示重试，不能据此把整个 App 判为不支持 |
| 待验证 | 尚未执行，或缺少任一关键证据字段；这是本文件当前所有矩阵行的状态 |

“支持”是具体界面的结论，不是整个应用的永久承诺。同一应用的网页正文、输入框、编辑器、终端、消息正文和消息输入框必须分别判定；应用升级后也必须重新抽样。

### 本机 Preflight

下表只证明 2026-09-11 本机安装状态，不证明选区兼容性。

| 项目 | 当前值 | 证据类型 |
|---|---|---|
| macOS | 26.5.2（25F84），Apple Silicon `arm64` | 静态证据：`sw_vers`、`uname -m` |
| TextEdit | 1.20，`com.apple.TextEdit`，`/System/Applications/TextEdit.app` | 静态证据：Bundle `Info.plist` |
| Safari | 26.5.2，`com.apple.Safari`，`/Applications/Safari.app` | 静态证据：Bundle `Info.plist` |
| Google Chrome | 152.0.7977.84，`com.google.Chrome`，`/Applications/Google Chrome.app` | 静态证据：Bundle `Info.plist` |
| Visual Studio Code | 1.128.0，`com.microsoft.VSCode`，`/Applications/Visual Studio Code.app` | 静态证据：Bundle `Info.plist` |
| Preview | 11.0，`com.apple.Preview`，`/System/Applications/Preview.app` | 静态证据：Bundle `Info.plist` |
| 企业微信 | 5.0.10，`com.tencent.WeWorkMac`，`/Applications/企业微信.app` | 静态证据：Bundle `Info.plist` |

执行矩阵前必须再次记录版本。如果版本变化，不覆盖旧证据；新增一轮带日期的记录。

### 2026-09-11 自动化边界记录

- 使用 leaf `5ACFA8…` 的稳定本地身份构建 Debug `.app`，严格签名校验通过；启动时把 Assistant 数据指向 `/private/tmp` 下的空隔离目录，日志确认辅助功能有效且 Carbon 已注册 `⌃⌥T`。
- 从 macOS 的 NARC 应用菜单进入偏好设置，真实界面显示“划词创建 Todo”、当前值 `⌃⌥T` 与“已启用”；本次没有修改用户快捷键。
- 当前 Computer Use 的合成 `Control+Option+T` 会把按键直接送进 TextEdit，而不是走 Carbon 全局热键。该尝试曾改变标准夹具源文本，因此立即停止，并被判定为无效样本；Todo 隔离文件未生成，剪贴板 `changeCount` 保持 `1643 → 1643`。
- 测试前后个人 `assistant-v1.json` 的 SHA-256 均为 `08593244ee5c6d2687cd4ae89e8fde33257ffcda4494857d1fda9d5b019caaf8`；空隔离目录已删除，原安装版 NARC 已恢复运行。
- 因无法自动化真实物理 Carbon 按键，下方 13 行仍全部为“待验证”。这些记录只证明构建、隔离、注册日志与设置入口，不证明任何目标 App × Surface 已兼容。

### 标准夹具

真实测试只使用以下人工构造内容，不选择个人聊天、生产代码、密码、令牌或其他私密文本。

| 夹具 ID | 内容/构造 | 用途 | 预期业务结果 |
|---|---|---|---|
| `SEL-SHORT-CJK-01` | `NARC-划词任务-20260911-A1` | 中文、连字符、数字的短选区 | 直接创建 1 条完整 Todo |
| `SEL-SHORT-MIXED-02` | `Review NARC issue #42（今天）` | 中英文与标点混合 | 直接创建 1 条完整 Todo |
| `SEL-EDGE-SPACE-03` | 在短夹具首尾各加入空格和换行 | 首尾规范化 | 只移除首尾空白，正文不改写 |
| `SEL-LONG-240-04` | 精确 240 个 Unicode grapheme | 长文阈值下边界 | 不进入长文确认，直接创建 1 条 Todo |
| `SEL-LONG-241-05` | 精确 241 个 Unicode grapheme | 长文阈值上边界 | 先确认；确认前 Todo 增量为 0 |
| `SEL-LONG-LINES-06` | 4 个非空逻辑行，总长度少于 240 | 多行长文边界 | 先确认；内部换行不被静默改写 |
| `SEL-VSCODE-4K-07` | 在临时文件中生成约 4 KiB、含多行和 emoji 的文本 | VS Code 长选区与 AX 响应风险 | 只显示确认；取消时零写入，确认时全文保存且界面无长时间冻结 |
| `SEL-EMPTY-08` | 仅放置光标，不选中文字 | 空选区 | 明确提示，Todo 增量为 0 |
| `SEL-DUPLICATE-09` | 预先创建一条与 `SEL-SHORT-CJK-01` 同标题的 Todo | 精确撤销 | 撤销只删除本次 UUID，预存同名项保留 |
| `SEL-PDF-TEXT-10` | 本地生成、带真实文本层的单页 PDF，正文为短夹具 | Preview 文本层 | 待真实读取判定 |
| `SEL-PDF-SCAN-11` | 把同页渲染为纯图片后生成扫描件 PDF | Preview 无文本层 | **预期不支持**；仍须实测并保持明确失败、零写入、零 OCR |
| `SEL-OVERSIZE-12` | 生成 65,537 个 UTF-16 文本单元的选区 | 异常大选区上限 | 明确要求缩小选区；不得调用 range-to-string，不创建 Todo |

长文本夹具必须由测试代码按 grapheme 数生成，不用 UTF-8 字节数代替字符边界。确认后的 Todo 保存完整规范化选区；预览可以视觉截断，但数据不得静默截断。

### App × Surface 矩阵

“候选读取路径”是实现要尝试并记录的标准 AX 路径，不是兼容结论。真实结果栏必须填写实际 AX role/subrole、成功属性或错误码、耗时分布和 Gate 证据。

| App / 版本 | Surface | 标准夹具 | 候选读取路径 | 当前状态 | 验证前预期 | 真实结果与证据 |
|---|---|---|---|---|---|---|
| TextEdit 1.20 | 纯文本正文编辑区 | `SEL-SHORT-CJK-01`、`SEL-EDGE-SPACE-03` | focused element/有限父链的 `AXSelectedText`；必要时标准 range + value | **待验证** | 基准样本 | 待填写 |
| TextEdit 1.20 | 富文本正文编辑区 | `SEL-SHORT-MIXED-02`、`SEL-LONG-LINES-06` | 同上 | **待验证** | 核对富文本是否仍返回纯文本选区 | 待填写 |
| Safari 26.5.2 | 普通网页正文 | `SEL-SHORT-CJK-01` | focused WebArea/有限父链的标准选区属性 | **待验证** | 不预判；网页选区可能不属于当前 focused element | 待填写 |
| Safari 26.5.2 | 网页 `input` / `textarea` | `SEL-SHORT-MIXED-02` | focused text control 的 `AXSelectedText`；必要时标准 range + value | **待验证** | 与网页正文分开判定 | 待填写 |
| Google Chrome 152.0.7977.84 | 普通网页正文 | `SEL-SHORT-CJK-01` | focused WebArea/有限父链的标准选区属性 | **待验证** | 不预判；若需要浏览器额外辅助模式，必须标条件支持 | 待填写 |
| Google Chrome 152.0.7977.84 | 网页 `input` / `textarea` | `SEL-SHORT-MIXED-02` | focused text control 的 `AXSelectedText`；必要时标准 range + value | **待验证** | 与网页正文分开判定 | 待填写 |
| Visual Studio Code 1.128.0 | 编辑器短选区 | `SEL-SHORT-CJK-01`、`SEL-SHORT-MIXED-02` | focused editor/有限父链的标准选区属性 | **待验证** | 不预判；记录 Electron 辅助模式状态 | 待填写 |
| Visual Studio Code 1.128.0 | 编辑器长选区 | `SEL-LONG-241-05`、`SEL-VSCODE-4K-07` | 优先直接 `AXSelectedText`；range + value 回退必须有范围和耗时保护 | **待验证** | **高风险样本**：不得为取一段选区同步拉取无界完整文档并阻塞主线程 | 待填写 |
| Visual Studio Code 1.128.0 | 集成终端 | `SEL-SHORT-MIXED-02` | focused terminal/有限父链的标准选区属性 | **待验证** | 独立于编辑器判定；不复用 NARC 内嵌终端私有选区能力 | 待填写 |
| Preview 11.0 | 有文本层 PDF | `SEL-PDF-TEXT-10` | focused PDF 内容元素/有限父链的标准选区属性 | **待验证** | 只核对真实文本层 | 待填写 |
| Preview 11.0 | 扫描件 PDF | `SEL-PDF-SCAN-11` | 仅标准选区属性 | **待验证** | **预期不支持**；禁止 OCR、截图或剪贴板回退 | 待填写 |
| 企业微信 5.0.10 | 消息正文可见选区 | `SEL-SHORT-CJK-01` | focused 消息内容元素/有限父链的标准选区属性 | **待验证** | 不预判；自绘消息区可能不暴露标准选区 | 待填写 |
| 企业微信 5.0.10 | 消息输入框 | `SEL-SHORT-MIXED-02` | focused text control 的 `AXSelectedText`；必要时标准 range + value | **待验证** | 与消息正文分开判定 | 待填写 |

### 单行证据记录模板

每次矩阵执行至少记录以下字段。不得记录个人选区正文；标准夹具只记 ID、字符数和预先计算的摘要。

```text
run_id:
tested_at:
macos_version_build:
narc_build_and_signing_requirement:
source_app_name_version_bundle:
surface:
fixture_id_grapheme_count_digest:
accessibility_granted_before_trigger:
configured_shortcut:
source_pid_before_trigger:
focused_ax_role_subrole:
selected_text_path_or_ax_error:
read_elapsed_ms:
feedback_state:
source_pid_after_feedback:
clipboard_change_count_before_after:
todo_count_before_after:
created_todo_id_or_none:
stored_digest_matches_fixture:
undo_result_and_remaining_ids:
repeat_press_count_created_count:
restart_persistence_result:
sanitized_ui_evidence:
verdict:
notes:
```

性能字段至少采集 10 次并报告 P50/P95；原始日志只能记录 bundle、surface、属性路径、错误码、字符数、摘要和耗时，禁止打印选中文字。

### 每行必须通过的 Gate

#### 1. 读取与内容 Gate

- 成功时，本地 Todo 的规范化正文与夹具摘要完全一致，不丢 emoji、标点或内部换行。
- 空选区、纯空白、属性不支持、权限缺失、目标切换和瞬时失败均不创建 Todo。
- 超过 65,536 个 UTF-16 文本单元时明确拒绝且零写入；range 回退必须在读取正文前执行同一上限判断。
- `.cannotComplete` 等暂态错误只能显示“暂时无法读取，请重试”，不得直接归类为不兼容。
- 长文本确认出现前 Todo 增量必须为 0；取消后仍为 0；确认一次后才为 1。

#### 2. Todo 事务 Gate

- 正常短选区一次按键只新增 1 条 Todo，并取得本次创建的稳定 UUID。
- 按住快捷键 2 秒且系统产生重复 key-down 时仍只新增 1 条；松开后再次按下才允许新建下一条。
- 成功反馈只能在原子写盘成功后出现；写盘失败时内存、磁盘和 UI 都不得声称已创建。
- 撤销按本次 UUID 删除；`SEL-DUPLICATE-09` 的预存同名 Todo 必须保留。
- 撤销写盘失败时 Todo 保持存在，反馈明确说明失败，不能先从界面消失。
- 未撤销的成功 Todo 在 NARC 重启后仍存在；已成功撤销的 Todo 在重启后仍不存在。

#### 3. 焦点与反馈 Gate

- 在读取完成前不得激活 NARC、打开 Assistant 或改变来源 App 的 focused PID。
- 短选区成功、空选区、不兼容和瞬时失败使用非激活反馈；反馈出现后来源 App 仍是前台。
- 长文本确认属于用户明确触发的额外交互，但必须使用已经捕获的快照；确认期间来源选区变化不能偷换待保存内容。
- 正常路径不自动展开悬浮球面板、不播放声音、不发送系统通知；唯一 `AssistantStore` 更新后现有匿名 Todo cue 可以自然刷新。

#### 4. 剪贴板与输入 Gate

- 每次测试记录 `NSPasteboard.general.changeCount` 前后值，必须完全一致。
- 测试期间不得出现模拟 `⌘C`、合成键盘/鼠标事件或来源 App 文本被修改。
- 快捷键注册失败时不执行读取；偏好设置必须继续显示和持久化真实仍生效的旧组合。

#### 5. 权限与隐私 Gate

- 无辅助功能权限时，NARC 先解释“只在本次快捷键触发时读取选区”，再提供唯一系统授权入口；不自动重放失败动作。
- 授权后提示返回来源 App、重新确认选区并再次按快捷键，通常无需重启 NARC。
- 手动输入 Inbox/Todo/Notes 继续不依赖辅助功能；文案不得笼统写成“所有 Todo 都需要权限”或“辅助功能只用于窗口”。
- Toast、应用日志、测试报告和截图不展示个人选区正文；真实应用测试只使用标准夹具。

### 真实执行流程

1. 使用稳定本地签名的 Debug `.app`，并把 `AssistantStore` 指向已验证位于 `/private/tmp` 的全新隔离文件；如果不能证明隔离路径实际生效，立即停止，不得用真实个人数据继续。
2. 记录 NARC 签名 requirement、系统/应用版本、当前快捷键、来源 PID、隔离 Todo 数和剪贴板 `changeCount`。
3. 在指定 Surface 中只打开标准夹具，选中目标文本，确认来源 App 仍在前台。
4. 真实按下当前设置的全局快捷键；分别执行单击、2 秒长按、松开再按、空选区、权限拒绝/恢复和长文本确认/取消。
5. 同时核对用户可见反馈与隔离 JSON：不能只看 Toast，也不能只看测试进程返回值。
6. 执行精确撤销、同名保护和重启往返；记录 UUID 与摘要，不记录正文。
7. 核对剪贴板、来源焦点和来源文档无变化后，才为该行填写真实判定。
8. 删除隔离目录并恢复原已安装稳定 App；测试前后只读核对个人 Assistant 文件摘要保持一致。

### 已知风险与停止条件

- Safari/Chrome 的网页正文选区可能挂在 WebArea 或其有限父链，而不是当前 focused element；只允许固定深度的标准属性探测，不能退化为遍历整棵网页 AX 树。
- Electron/Chromium 的 AX 暴露可能受版本、应用辅助模式和具体控件影响。任何额外模式必须记录为条件，不能默认为所有用户开启。
- VS Code 长选区可能诱发读取完整编辑器 value、跨进程 AX 长尾或大字符串复制。实现必须优先直接选区属性、在后台执行并设置范围/耗时保护；出现可见冻结、无界全文读取或内容错位时停止该回退，并把对应 Surface 保持为待验证或不支持。
- 当控件暴露 `AXSelectedTextRange` 时，实现会先按 65,536 个 UTF-16 单元预检并拒绝异常大范围；若控件只暴露直接 `AXSelectedText`，系统 API 仍可能先返回整段文本再由 NARC 拒绝保存。`SEL-OVERSIZE-12` 如出现明显冻结或内存尖峰，应立即停止并把该 Surface 保持为待验证，而不是扩大上限。
- Preview 扫描件没有标准文本层时预期不支持。本阶段不得为提高覆盖率引入 OCR 或屏幕录制。
- 企业微信消息区可能是自绘界面；输入框成功不能证明消息正文也成功，反之亦然。
- App 升级、focused element 失效或 `cannotComplete` 会产生瞬时差异；连续错误必须先区分暂态失败和稳定不支持，不能靠重复尝试碰运气。
- 任何一次测试导致个人 Todo 变化、剪贴板 `changeCount` 变化、来源文本变化、NARC 抢焦点或日志出现真实选区正文，立即停止整轮矩阵并先修复隔离/隐私问题。

### 兼容矩阵完成条件

只有在每一行都具备完整证据字段后，才能把“待验证”改为“直接支持”“有条件支持”或“不支持”。v2.0 的最低发布 Gate 是：

- TextEdit 至少一个正文 Surface 直接支持，作为标准实现基线；
- Safari 与 Chrome 的网页正文、输入框分别有真实判定；
- VS Code 短选区与长选区分别有结果，长选区没有主线程冻结或无界全文读取；
- Preview 文本层与扫描件分别判定，扫描件不触发任何 OCR 回退；
- 企业微信消息正文与输入框分别判定；
- 所有失败路径均保持零 Todo 增量、零剪贴板变化和来源焦点不变；
- 长按只创建一次，撤销只删除本次 UUID，写盘失败不出现假成功。

在这些证据完成前，对外文档可以把实现列为“开发预览”，但不得声称任一 App 或 Surface 已支持，也不得省略仍在进行的真实兼容验证。
