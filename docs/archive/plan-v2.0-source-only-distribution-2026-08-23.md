> 🧭 状态：已完成 | 进度 8/8 | 当前归属：Reviewer | 最近卡点：无

# Plan: NARC 源码分发边界收口

## 目标

把 NARC 的公开交付方式永久收敛为“从 GitHub 用一条命令拉取源码并在本机准备好 App”，删除安装包、Release artifact、稳定证书、公证和自动更新路线，保留普通用户无需理解的本地 `.app` 组装与 ad-hoc 签名。

## v2.0.0 · 2026-08-23 · 一条命令获取和运行

## 产品决定

- 唯一支持的普通用户入口是 README 首屏的一条 GitHub 命令；它自动完成拉取、构建、放置到 `~/Applications/NARC.app` 和启动。
- 不制作或发布 DMG、PKG、预编译 ZIP App、GitHub Release artifact、App Store 包，也不引入 Sparkle 或其他自动更新框架。
- 不要求 Developer ID、自签名证书、Apple Notarization、手工签名、`sudo`、手动复制 App 或移除 quarantine。
- 保留本地 `.app` Bundle，因为 Bundle ID、图标、启动行为和 macOS 集成依赖它；构建脚本始终自动使用 ad-hoc 签名并严格校验，用户文档不把签名当成操作步骤。
- Assistant、Todo、Notes、Quick Capture 和 Dock Badge 不依赖辅助功能权限；只有窗口排列、钉选和重新激活其他 App 窗口需要用户按 macOS 要求授权。
- ad-hoc 构建无法保证辅助功能授权跨每次重编都保持；不以引入稳定证书来掩盖这个系统边界。
- 不修改业务功能、不恢复 Workspace、不引入依赖、不清理本轮范围外的既有工作树。

## Preflight

- 仓库中没有 DMG/PKG 生成命令，但 `.github/workflows/release.yml` 会在 `v*` tag 上发布 `NARC.app.zip`。
- `scripts/update-restart.sh` 强制依赖 `NARC Dev` 证书并承诺授权跨重编保持。
- `scripts/build-app.sh` 同时支持稳定证书与 ad-hoc 两条路径，并向开发者建议手工复制到 `/Applications`。
- `docs/architecture.md` 仍把 Developer ID、公证、GitHub Releases 和 Sparkle 写成部署路线。
- `scripts/install.sh` 已具备一条命令构建、安装到用户目录和启动的基础能力，不需要另造安装器。

## 步骤

- [x] 1. [删除] `.github/workflows/release.yml`、`scripts/update-restart.sh` — 移除预编译 Release artifact 和稳定证书入口。
- [x] 2. [修改] `scripts/build-app.sh` — 只保留自动 ad-hoc 签名与严格校验，删除证书探测、`/Applications` 手工安装和全局权限提示。
- [x] 3. [创建] `scripts/verify-source-only-distribution.sh` — 对活跃交付文件扫描 DMG/PKG/Release artifact/Developer ID/公证/稳定证书/Sparkle 回归，并核验本地 ad-hoc 构建契约。
- [x] 4. [修改] `README.md`、`README.en.md` — 明确唯一一条源码命令、无安装包/证书/公证步骤，以及核心功能与可选窗口权限边界。
- [x] 5. [修改] `docs/PROJECT.md`、`docs/FEATURES.md`、`docs/VERSIONS.md`、`docs/architecture.md` — 统一产品目标、功能状态、版本排除项和被取代的历史 ADR。
- [x] 6. [运行] Shell 与静态边界验证 — 执行脚本语法检查、source-only checker、残留扫描和 `git diff --check`。
- [x] 7. [运行] 干净源码安装验证 — 在临时安装根目录执行 `NARC_SKIP_LAUNCH=1 bash scripts/install.sh`，核验 Bundle ID、ad-hoc 签名和用户回执。
- [x] 8. [运行] 项目回归与 Harness — 执行 Swift 测试/构建及 Harness 验证，逐条审计原始要求并完成 Reviewer 交接。

## 验收标准

- 活跃仓库中不存在 DMG/PKG/预编译 App Release、Developer ID、公证、稳定证书或 Sparkle 的可执行入口或当前规划。
- README 首屏只要求复制一条命令；普通用户不需要下载 Release、手工安装、准备证书、理解签名或使用 `sudo`。
- `.github/workflows/release.yml` 与 `scripts/update-restart.sh` 不存在。
- `scripts/build-app.sh` 只执行 `codesign --sign -`，且 `codesign --verify --deep --strict` 退出 0。
- 临时目录的一条命令安装退出 0，产物 Bundle ID 为 `com.mickmi.narc`，不会替换用户当前 App。
- 文档不声称所有能力零权限，也不把窗口功能的 macOS 辅助功能授权包装成安装步骤。
- Swift 测试、构建、静态边界检查和 Harness 关键检查均有本轮输出证据。

## 风险与停止条件

- 若删除 Release workflow 会同时移除其他独立发布能力，停止并拆分；当前检查确认该文件只负责预编译 App Release。
- 若 ad-hoc 签名无法生成可启动 Bundle，保留失败证据并回 Planner，不退回稳定证书路线。
- 若首次构建因网络或 Xcode Command Line Tools 缺失失败，只报告外部前置条件，不用安装包绕过。
- 同一错误指纹出现两次，输出 Debug Card 并停止碰运气式重试。

## 自检日志

### Step 1 — 2026-08-23
- files: `.github/workflows/release.yml`、`scripts/update-restart.sh`、`plan.md`
- verify: 两个精确路径均不存在；活跃脚本和工作流残留扫描未命中 Release action、稳定证书、公证、DMG/PKG 或 Sparkle 入口。
- notes: Release workflow 只负责预编译 App ZIP 发布，证书脚本只负责稳定签名更新；删除没有牵连其他能力。

### Step 2 — 2026-08-23
- files: `scripts/build-app.sh`、`plan.md`
- verify: `bash -n scripts/build-app.sh` exit 0；脚本只保留 `codesign --sign -` 并继续执行 `codesign --verify --deep --strict`；`git diff --check` exit 0。
- notes: `.app` Bundle 保留为本地运行载体，签名降为无证书的自动构建细节；开发输出改为引导复用 `install.sh`。

### Step 3 — 2026-08-23
- files: `scripts/verify-source-only-distribution.sh`、`plan.md`
- verify: `bash -n` exit 0；`bash scripts/verify-source-only-distribution.sh` exit 0，输出 `Source-only distribution boundary verified`。
- notes: 项目没有可复用的分发边界 checker，因此新增只读检查；它不扫描自身，也不禁止文档解释被排除方案。

### Step 4 — 2026-08-23
- files: `README.md`、`README.en.md`、`plan.md`
- verify: 中英文首屏均保留且只保留一条 GitHub 命令；ZIP 备选入口已移除；旧的“用户安装时签名”表述扫描为 0；`git diff --check` exit 0。
- notes: README 明确不提供安装包和证书流程，同时如实说明只有可选窗口工具受 macOS Accessibility 约束。

### Step 5 — 2026-08-23
- files: `docs/PROJECT.md`、`docs/FEATURES.md`、`docs/VERSIONS.md`、`docs/architecture.md`、`plan.md`
- verify: 旧部署拓扑、未来 Sparkle 和生效中的 GitHub Releases ADR 扫描为 0；ADR-010 标记废弃并由 2026-08-23 的 ADR-018 取代；`git diff --check` exit 0。
- notes: 插件平台候选中的代码签名是未来插件隔离安全问题，不属于 App 分发证书链，因此未误删该安全边界。

### Step 6 — 2026-08-23
- files: 活跃 README、产品文档、分发脚本与 `plan.md`（验证）
- verify: 两个 README 各精确包含一条 clone/install 命令；Shell 语法、旧路径残留扫描、source-only checker 与 `git diff --check` 全部 exit 0。
- notes: 文档允许以否定句解释被排除方案，但活跃脚本和 workflow 中不能存在对应执行入口。

### Step 7 — 2026-08-23
- files: `scripts/install.sh`、`scripts/build-app.sh`、`/private/tmp/narc-source-only.f4h5RN/NARC.app`（临时产物）、`plan.md`
- verify: `NARC_INSTALL_DIR=/private/tmp/narc-source-only.f4h5RN NARC_SKIP_LAUNCH=1 bash scripts/install.sh` exit 0；Bundle ID `com.mickmi.narc`；`codesign --verify --deep --strict` exit 0；`Signature=adhoc`。
- notes: 沙箱内首次运行因 Swift 缓存和 `.build` 只读 exit 4；在获准的正常本机写入环境原命令一次通过，未修改安装逻辑，也未替换用户当前 App。

### Step 8 — 2026-08-23
- files: Swift Package、Harness、全部本轮交付文件（验证）
- verify: `swift test` exit 0，Swift Testing 25/25；release App 已由 Step 7 构建；`harness check .` exit 0，17 pass / 2 warning / 0 failure；最终 source-only audit 与 `git diff --check` exit 0。
- notes: Harness 两条既有 warning 为 `.prompts` 是真实目录和未安装 pre-commit hook，均不由本轮分发改动引入；原始要求逐项满足，没有 DMG/PKG/预编译 Release 或证书链残留入口。
