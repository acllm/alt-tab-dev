# AltTab Dev

[alt-tab-macos](https://github.com/lwouis/alt-tab-macos) 核心功能的 Swift 复刻：Windows 风格的 ⌥+Tab 窗口切换器。纯 Swift Package 项目（无需 Xcode 工程文件），核心逻辑 100% 单元测试覆盖（TDD 开发）。

按住 **⌥ (Option) 再按 Tab** 呼出切换器：所有窗口（含最小化）以网格展示，Tab / 方向键移动焦点，松开 ⌥ 或按 ↵ 切换到选中窗口。**⌥+`** 只在当前应用的窗口间循环。

## 功能

- 全局热键 ⌥+Tab（全部窗口）/ ⌥+`（当前应用窗口），两种范围可在面板显示时实时切换
- 窗口缩略图（带行为自检：捕获不可靠时自动降级为应用图标，绝不显示错误截图）
- MRU（最近使用优先）排序：焦点事件 + z 序快照双重校正
- 支持最小化窗口与跨 Space 窗口切换
- 深色半透明覆盖层、焦点高亮环，布局自适应窗口数量（上限 7 列）
- 菜单栏常驻图标（退出 / 权限设置）

## 快速开始

```bash
git clone https://github.com/acllm/alt-tab-dev.git
cd alt-tab-dev
swift build                     # 需要 macOS 13+ / Swift 5.9+
swift run AltTabTests           # 运行全部单元测试
./Scripts/make-app-bundle.sh    # 打包 build/AltTab Dev.app
open "build/AltTab Dev.app"
```

首次运行需在 系统设置 → 隐私与安全性 → **辅助功能** 中授权（app 会自动弹引导）。

诊断模式（不启动 GUI）：

```bash
.build/debug/AltTab --dump              # 枚举当前可切换窗口并打印
.build/debug/AltTab --dump --verbose    # 附带每个应用的 AX 枚举结果
```

## 权限

| 权限 | 必需性 | 用途 | 缺失时的行为 |
|---|---|---|---|
| 辅助功能 | 必需 | 全局热键、AX 窗口控制 | 热键完全不可用，app 会引导授权 |
| 屏幕录制 | 可选 | 窗口缩略图 | 自动降级为应用图标，无弹窗打扰 |

**开发者注意**：TCC 授权按代码签名身份记录。ad-hoc 签名在每次重编译后变化，会导致授权静默失效（设置里开关仍显示打开）。仓库的打包脚本默认使用本地稳定身份 `AltTab Dev Local Signing`（见 `Scripts/make-app-bundle.sh`），创建一次后重编译不再失效：

```bash
# 一次性创建本地签名身份（10 年有效期）
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=AltTab Dev Local Signing/O=personal" \
  -config <(printf '[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=AltTab Dev Local Signing\n[v3]\nbasicConstraints=CA:TRUE\nkeyUsage=digitalSignature,keyCertSign\nextendedKeyUsage=codeSigning\n') \
  -keyout key.pem -out crt.pem
openssl pkcs12 -export -legacy -inkey key.pem -in crt.pem -out id.p12 -passout pass:xxx
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P xxx -T /usr/bin/codesign
```

## 架构

```
Sources/AltTabCore/        纯逻辑库（零 AppKit 依赖，100% 单测覆盖）
  WindowFilter             窗口过滤（layer / 激活策略 / 去重 / 幽灵窗口）
  MruWindowList            MRU 排序（焦点事件、z 序快照、存活窗口同步）
  GridNavigator            网格焦点导航（水平环绕、垂直钳制、Tab 循环）
  SwitcherState            状态机：键盘事件 → UI 效果（含 ⌥+` 应用范围切换）
Sources/AltTabApp/         应用逻辑库（AppKit + AX + CG）
  WindowRepository         CG + AX 窗口枚举合并；AX 聚焦（dlsym 桥接窗口 id）
  HotkeyEventTap           CGEvent 全局键盘监听（⌥ 状态跟踪、合成事件吞并）
  SwitcherPanel            NSPanel 覆盖层 + 网格自绘视图
  ThumbnailProvider        缩略图捕获 + 捕获能力行为自检
  AppCoordinator           事件 → 状态机 → UI / 系统效果分发
  PermissionsCenter        TCC 权限检查与引导
Scripts/                   打包、端到端验证工具
Tests/AltTabTests/         TDD 测试运行器（67 个用例）
```

### 关于测试运行器

本仓库使用仓库内自带的轻量测试运行器（`Tests/AltTabTests/TestHarness.swift`）而非 XCTest/swift-testing：纯命令行工具链（无 Xcode）环境下两者均不可用，自研运行器以退出码驱动 TDD 红→绿循环，零外部依赖。在有完整 Xcode 的环境下迁移到 swift-testing 也很容易（测试语义一一对应）。

### 开发验证工具

```bash
./Scripts/verify-app.sh     # 真实 .app 在 launchd 环境的端到端自检（截图 + 像素判定）
./Scripts/run-e2e.sh        # swift JIT 模式跑完整管线（继承终端权限）
tail -f /tmp/alttab-dev.log # 运行时诊断日志（权限状态、热键事件、探测结果）
```

## TDD 开发流程

所有核心逻辑先写失败测试（红），再实现（绿），逐循环提交：

```
$ git log --oneline
feat: ⌥+` cycles current app's windows; reliable screen-recording probe
feat: icon-fallback thumbnails with behavioral capture probe
fix: per-window thumbnails; drop escape-cancel; one-time prompts
feat(app): GUI shell, e2e self-verification, panel fixes
feat(core): switcher state machine          ← TDD 循环 4
feat(core): grid navigation                 ← TDD 循环 3
feat(core): MRU window ordering             ← TDD 循环 2
feat(core): window filtering + TDD harness  ← TDD 循环 1
chore: scaffold SPM package
```

## 与原版的差异（核心功能取舍）

- 无偏好设置界面、无多快捷键自定义（固定 ⌥+Tab / ⌥+`）
- 无多显示器角标、无鼠标交互、无黑名单/例外列表
- 缩略图用 CGWindowListCreateImage（dlsym 运行时解析，规避 SDK 移除），未迁移 ScreenCaptureKit
- 单层 7 列自适应网格

## 已知限制

- 屏幕录制授权需重启 app 生效（macOS 系统行为）；未授权时缩略图自动降级为应用图标
- 屏幕锁定状态下窗口不合成（系统行为），锁屏中无法做视觉验证
- AX 权限被系统撤销时，轮询保留旧窗口列表而非清空（避免闪空面板）

## License

[MIT](LICENSE)。本项目为独立实现，致敬 [alt-tab-macos](https://github.com/lwouis/alt-tab-macos)（GPL-3.0）。
