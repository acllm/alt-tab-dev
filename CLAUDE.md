# AltTab Dev — 开发约定

纯 Swift Package 项目（无 Xcode 工程，命令行工具链即可开发）。核心逻辑 100% TDD（`Tests/AltTabTests` 自研轻量运行器，`swift run AltTabTests`）。

## 开发循环

- **每次改动后运行 `./Scripts/verify.sh`**（全量：构建 → 单测 → 枚举冒烟 → 缩略图管线 → JIT E2E → 真实 .app 截图判定，约 1–2 分钟）。注意：L5 会在屏幕上闪现切换面板约 7 秒，并 pkill 重启正在运行的 AltTab Dev。
- 快速迭代（改核心逻辑、不想被打扰屏幕）用 `./Scripts/verify.sh --quick`（约 30 秒，跳过缩略图与 L5）。
- TDD 红→绿小循环只需 `swift run AltTabTests`。
- 验证产物（各层日志、截图、diag.txt）归档在 `build/e2e/<时间戳>/`；运行时诊断日志在 `/tmp/alttab-dev.log`。
- L5 像素判定显示自适应（从 `/tmp/alttab-e2e/diag.txt` 的 `panel.frame` + `NSScreen.screens` 换算），换显示器无需改脚本。前置条件：GUI 会话未锁屏、终端持有屏幕录制授权；缺失时 L5 自动 SKIP 并给出原因。

## 本机环境备注（开发用 Mac）

- 双 5K 显示器（各 2560×1440 pt @2x）；`screencapture -x` 输出主屏 5120×2880。
- 终端已持有辅助功能 + 屏幕录制授权（L3/L4 直接可用）。
- 钥匙串已有稳定签名身份 `AltTab Dev Local Signing`（重编译不丢 TCC 授权）。
