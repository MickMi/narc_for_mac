# 按钮单行保护检查

日常执行 `swift test --no-parallel` 时，`ButtonLayoutContractTests` 会自动运行本项目的检查脚本；现有 CI 的 Swift 测试步骤也包含它，不依赖个人 Harness 安装路径。

只检查这个约束时：

```sh
swift test --no-parallel --filter ButtonLayoutContractTests
python3 -B scripts/tests/button-layout-contract.py .
```

检查当前搜索窗口的图文单行声明、回答操作区紧凑替代、图标提示和连接按钮加载态。负向测试仅修改临时源码副本，验证删除保护会失败；缺失文件不能算通过。

本检查是具体控件的源码保护，不是通用 Swift 解析或像素验收。合法重构须同步更新检查；最窄窗口、长文案、字号变化、真实溢出与点击仍要验收。不能因为单行声明存在就认定布局正确。

来源：Harness v0.26 开发样板，2026-09-23 纳入 NARC。本地脚本是独立快照，不在运行时下载或同步规则。未改全局 Harness、未自动写 Brain、未发布。
