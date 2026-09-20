# Codex 回复提醒接入与验证

## v2.0.0 · 2026-09-20 · 应用内连接向导与原通知兼容

状态：用户明确允许后已实现并原身份安装，可体验预览；本轮未替用户启用真实连接，没有完成新路径的真实桌面验收。

1. NARC 设置 → AI 回复 → 连接回复提醒，阅读隐私说明后选择“允许并连接”。
2. 后台写入通知配置，保留原通知命令；界面显示“等待首次回复”。保存工作后完全退出并重开 ChatGPT / Codex，无需终端操作。
3. 完成一轮真实对话，设置页自动检查回执；收到后显示“已收到回复完成通知”。这只证明曾收到通知，不代表每轮都成功。

- 复用现有 adapter、提醒服务和安装器，新接入使用官方 notify，不改 Hook 信任或自动审核。旧 Hook 保留；关闭“显示回复提醒”仅停止卡片展示，元数据仍可能接收。
- 每个版本复制为按内容哈希命名的不可变脚本，每次连接具有 UUID 记录和独立回执。保留原 argv 作为恢复依据，不备份可能含密钥的完整配置；升级不嵌套转发，旧代回执不能确认新代连接。
- 配置合并保留其他语义及目标区段外注释；文件锁、写前比对、原子替换保护并发。符号链接、损坏配置、profile 覆盖和无法明确解析的写法失败关闭；不声称外部非协作写入完全无竞态。
- 用户明确授权原通知程序继续收到原始事件，事件可能带正文。原通知程序启动独立于 NARC 解析；NARC 丢弃正文，仅保存会话/回合/时间等元数据，不上传。生产回调本身可能执行的行为不由 NARC 改写。
- 本机 UI 检查了入口、完整同意弹窗与取消，没有点击最终允许。安装及取消前后 config `149b228f…b260`、hooks `8aa01cd7…601c`、Assistant `46c263ee…919b`、signer marker `ddd6a87f…5aaa` 不变。

本轮可复现验证（全部 exit 0）：

- `PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/codex-hook-tests.py` → 28/28；包含原 argv/载荷精确保留、元数据隐私、旧事件隔离、代次升级、8 路并发、配置竞争、回调失败和路径安全。
- `CLANG_MODULE_CACHE_PATH=/private/tmp/narc-pinned-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/narc-pinned-module-cache swift test --skip-update --scratch-path /private/tmp/narc-all-shortcuts-cached-o7lx2X --disable-sandbox --quiet --filter 'codexCompletion|todoNudge|floatingWidget'` → 26/26、0 failures。
- `PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/codex-notify-probe.py --surface app-server --integration` → PASS。客户端内置运行程序 `0.155.0-alpha.9.2` 使用本地模拟 Responses，生产 adapter 和模拟原回调均收到事件，NARC 无正文，真实 config/hooks 不变。未执行真实 Computer Use 收尾程序，不等于真实客户端验收。
- `bash scripts/verify-source-only-distribution.sh`、`git diff --check` → PASS；正常 Debug 安装保留 NARC Dev，`codesign --verify --deep --strict --verbose=2 /Users/mickmi/Applications/NARC.app` → valid on disk / satisfies Designated Requirement；构建与安装主程序、adapter 资源 cmp 均通过。

待验证/限制：新连接配置器需要 Python 3.11+，只支持默认 `.codex`，不自动安装依赖；notify 只有完成通知，不替代开始/中断协议。真实原 Computer Use 兼容、双对话、子任务、中断及多桌面仍待体验确认后验收。没有新增解除连接按钮。重复报错回归：早期脚本路径递归检测误匹配临时目录名称，已收窄为完整脚本文件名并加入测试；隔离集成探针由失败转为通过。

## v2.0.0 · 2026-09-20 · 无终端接入的可行性实验

以下为用户明确“允许”之前的历史阶段；其中权限阻塞已解决，当前状态以上节为准。

- 目标：用户只在 NARC 中点击连接和确认，不操作终端；先证明通知机制，再开发向导。现有 Hook 方案保留，不写 trust hash。
- 官方依据：[通知接口](https://learn.chatgpt.com/docs/config-file/config-advanced#notifications) 支持 `agent-turn-complete`，提供 thread-id/turn-id，但也可能附带 input-messages/last-assistant-message；这与只含状态的接口不同，适配器必须丢弃正文、不落盘、不上传。
- 本机实际 notify 已用于 Computer Use 的 turn-ended 收尾。直接覆盖并丢弃原命令不可接受；拟议分发器需要保留原命令与原始事件传递。此兼容行为可能涉及正文，必须获得用户明确同意。
- 已验证客户端内置 Codex `0.155.0-alpha.9.2`：独立 exec 与 app-server 临时会话均在 Hook 禁用时收到完成回调。连接本机 fake Responses 服务，不使用真实模型，无额外模型费用；回执仅保存临时元数据和字段名称，不保存正文。
- 可复现命令：`PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/codex-notify-probe.py --surface exec`、同命令替换为 `--surface app-server`。成功条件为运行完成、模拟服务收到请求、收到合法完成回执、config.toml/hooks.json 前后哈希相同；任何一项缺失均失败。需要 Python 3.11、本机回环端口权限及指定版本运行程序，不加入普通 CI。
- 失败历史：首次服务初始化未返回；补诊断确认探针 MCP 禁用参数的引号形成错误键，导致 invalid transport。仅修改探针参数后通过；未修改真实用户配置。探针增加 EOF 及时失败，避免无意义等待。
- 范围限制：app-server 协议实验不等于正在运行的桌面客户端已连通；原通知程序未参与实验，转发兼容、中断与子任务、乱序去重、重开和新手流程仍待验证。notify 不提供开始/中断事件，不能直接宣称与现有三事件 Hook 完全等价。
- 当前阻塞：实现分发器的补丁被权限审核拒绝（超出验证授权的持久配置修改、执行原命令和正文载荷转发）；补丁未写入。需用户明确同意后才实现“点击后接入”，不能绕过审核或用测试回执显示已连接。
- 状态更正：本轮只读确认三个 NARC Hook 已是 `--all`。下方“尚未写入”为用户后来点击配置前的历史记录，不代表当前全局配置状态；信任与真实多会话接入仍不由文件存在推断。

## v2.0.0 · 2026-09-20 · 自动覆盖多会话与单会话静音

状态：单会话真实链路已获用户确认；多会话已原身份安装，用户回复“验证成功”确认合并测试卡和逐条关闭，设置往返/重启通过。完整 Swift 回归 230/230、Python 16/16 通过；全局 Hook 尚未写入，真实双对话自动链路仍待验收。

### 预期使用流程

1. 安装新版后进入 NARC 偏好设置 → AI 回复 → 配置所有对话的自动提醒，确认后合并 Hook 定义。
2. 在 Codex `/hooks` 审查 NARC 定义并信任，再完全退出并重开客户端。这是一次全局接入，不需逐对话加 Hook；定义之后发生变化时仍可能要求重新审核。
3. 受支持对话回复后在悬浮球旁出现合并列表，点击对应“继续对话”尝试返回；× 仅忽略该回合，“不再提醒”静音该对话。
4. AI 回复 → 对话管理中可搜索、静音、恢复、设置本地别名。新接收的对话自动出现；恢复只提醒之后新结果，不重放旧提示。

### 数据与安全契约

- `--all` 从官方 Hook 的 `session_id`/`turn_id` 自动取标识，过滤子任务；旧 `--thread` 保留兼容。只读标题索引最后 256KB，不读 transcript 或正文，没有模型请求。
- `codex-completion/events/<thread>_<turn>.json` 按回合原子保存；文件锁保护并发写入，`startedAt` 用于乱序比较，中断终态阻止晚到 Stop 复活。事件只保留协议元数据，目录 0700/文件 0600，拒绝符号链接。
- 只清理命名匹配的事件文件，最多保留 512 个、24 小时；NARC 每两秒后台最多读 512 × 8193 字节，展示有效期一小时。已读 1024 项；最近会话元数据 200 条，静音规则保持可恢复。旧 latest.json 兼容读取，同一回合优先新协议。
- 全局关闭或单会话静音不是禁用 Hook，可能继续接收元数据；只停止展示。测试事件不会写入会话管理或冒充真实连接时间。
- 安装器在用户明确点击后，备份旧 hooks.json，原位替换 NARC 条目或追加；保留其他 Hook/数组位置、config.toml/notify 和信任记录。适配器复制到 `~/Library/Application Support/NARC/codex-completion/narc-codex-hook-v2.py`，不绑定 checkout 路径。只支持默认 `~/.codex` 配置位置。
- UI 的“最近收到真实事件”仅说明曾收到事件，不证明全局 Hook 全部受信任；普通 GPT 聊天及前台会话识别不宣称支持。Stop 仍只是回复结束候选，不等同任务成功。

### 本轮证据与待验证

- 体验确认后全量命令：`swift test --skip-update --scratch-path /private/tmp/narc-all-shortcuts-cached-o7lx2X --disable-sandbox --quiet`（现有模块缓存）→ 230/230、0 failures、exit 0。用户确认的是两条 preview 卡合并和逐条关闭，不替代全局 Hook 配置/信任/重开后的真实验证。
- `PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/codex-hook-tests.py`：16/16，exit 0；包括 24 会话并发、配置幂等、安全合并、隐私字段和安全路径。
- 现有 Swift 缓存下 `swift test --skip-update --scratch-path /private/tmp/narc-all-shortcuts-cached-o7lx2X --disable-sandbox --quiet --filter 'codexCompletion|todoNudge|floatingWidget'`：25/25，0 failures；包括合并、晚到 Stop、静音/恢复/重启、全局开关及预览状态隔离。
- 原签名初次拒绝后，续接时临时签名探针和正常 Debug 安装成功；未修改钥匙串设置，恢复原因未证实。新版严格验签、主程序及资源 cmp 均通过，个人数据/marker/hooks/config 哈希未变。
- CUA 验证 AI 回复入口、全局/单会话关闭 → 重启保持 → 恢复开启，以及一次配置确认框/取消。独立偏好读取确认静音 UUID。两条 preview 测试已投递，工具只选择悬浮球，合并卡与 × 逐项移除已询问用户确认。真实全局配置未写，真实双对话链路和完整 QA 保持开放。
- 依据 OpenAI Docs 核对 [Hooks 契约](https://developers.openai.com/zh-Hans/docs/hooks)。实现保留用户审核而非自动写入 trust；不依赖所有普通 ChatGPT 对话具有此事件接口。

## v2.0.0 · 2026-09-18 · 从本轮回复到继续对话

历史状态（9 月 18 日）：已安装实验版，用户确认测试卡及点击回跳；当时真实自动投递未验收。9 月 20 日重开客户端后用户已确认正常，后续以顶部阶段为准。

边界：仅用户指定的 Codex 类型会话。不是 ChatGPT 全账号监听，也不是普通 GPT 对话全部兼容。

### 接入

- Python 标准库 adapter `scripts/narc-codex-hook.py --thread <UUID> --title <显示名>` 从标准输入接收官方 hook JSON。
- 仅接受该会话的 `Stop`、`UserPromptSubmit`、`Interrupt`，丢弃正文、工具参数、cwd、transcript 路径；不读取历史文件，不调用模型。
- 只写 `~/Library/Application Support/NARC/codex-completion/latest.json`，目录 0700、文件 0600、原子替换、拒绝符号链接。单会话的后续状态覆盖前一状态。
- NARC 每两秒后台读取最多 8193 字节，校验版本、UUID、状态、大小和时间；过期一小时不提醒。已读账本最多 128 个回合，不改 Assistant 数据 schema。
- 卡片沿用 Todo 的非激活容器，但独立内容，与 Todo 卡错开展示；不抢焦点。用户点击才向已注册的 `com.openai.codex` 发送 `codex://threads/<UUID>`。
- URL 打开 API 成功只是系统接受请求，不证明选中正确会话；本机该路径的用户点击确认已取得。其他版本必须重新验证。

### 信任和回退

- 不替换用户现有 `notify`。独立追加三个 hook，并保留原数组位置，避免影响位置关联的已信任记录。
- 不写 trusted_hash，不启用绕过信任参数。按官方说明，在 Codex CLI 的 `/hooks` 中检查并信任新增的 `narc-codex-hook.py` 条目；不要批量批准未知钩子。客户端是否热加载或需重开会话必须实测，不为实验自动重启 ChatGPT。
- 停用实验：禁用/移除仅 command 包含本项目 `scripts/narc-codex-hook.py` 的三个新增条目；不要整体覆盖 hooks.json，防止丢失后续用户修改。已显示卡片可点击关闭，过期后不再展示。
- 当前适配使用 Stop 作为回复结束候选。其他 Stop hook 可以要求续跑，因此不能将 Stop 等同任务成功；继续回合/中断事件用于清除过时提示，是否覆盖全部续跑行为仍待验收。

### 验证与待办

- Swift 专项：`swift test --skip-update --scratch-path /private/tmp/narc-all-shortcuts-cached-o7lx2X --disable-sandbox --quiet --filter 'codexCompletion|todoNudge|floatingWidget'`，20/20、0 failures。
- Python：`PYTHONDONTWRITEBYTECODE=1 python3 scripts/tests/codex-hook-tests.py`，9/9、exit 0，覆盖正文丢弃、其他会话、子任务、未知事件、非法 ID、工作/中断、私有原子写入和符号链接。
- 原身份 Debug 安装、严格验签、构建/安装二进制 cmp、source-only 检查通过。未创建新证书或改变系统信任。
- 用户确认 `isPreview=true` 测试卡出现，点击回到原会话；已读账本写入 preview ID。没有把此夹具当真实事件。
- 待用户信任后：发起一轮真实消息→切到其他 App→回复结束出现一次提示→点击返回；重复投递、下一轮、手动中断、后台多桌面继续验收。

官方参考：[Hooks](https://developers.openai.com/es-419/docs/hooks)、[通知配置](https://developers.openai.com/zh-Hans/docs/config-file/config-advanced#通知)。
