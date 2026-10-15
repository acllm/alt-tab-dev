# alt-tab（复刻版）

[alt-tab-macos](https://github.com/lwouis/alt-tab-macos) 核心功能的 Swift 复刻：Windows 风格的 ⌥+Tab 窗口切换器。

按住 **⌥ (Option) 再按 Tab** 呼出切换器：所有窗口（含最小化）以缩略图网格展示，Tab / 方向键移动焦点，松开 ⌥ 或按 ↵ 切换到选中窗口，Esc 取消。

## 功能

- 全局热键 ⌥+Tab 呼出 / 前进，⇧+Tab 后退，方向键网格导航
- 窗口缩略图（CGWindowListCreateImage）、应用图标、窗口标题
- MRU（最近使用优先）排序：焦点事件 + z 序快照双重校正
- 支持最小化窗口（无缩略图，显示图标）与跨 Space 窗口
- 深色半透明覆盖层、焦点高亮环，布局自适应窗口数量（上限 7 列）
- 菜单栏常驻图标（退出 / 权限设置）

## 架构

```
Sources/AltTabCore/        纯逻辑库（无 AppKit，100% 单测覆盖）
  WindowFilter             窗口过滤（layer/策略/去重/幽灵窗口）
  MruWindowList            MRU 排序（focus 事件、z 序快照、存活同步）
  GridNavigator            网格焦点导航（水平环绕、垂直钳制）
  SwitcherState            状态机：事件 → 效果（显示/重载/移焦/提交/隐藏）
Sources/AltTabApp/         应用逻辑库（AppKit + AX + CG）
  WindowRepository         CG+AX 窗口枚举合并、AX 聚焦（dlsym 私有符号取窗口 id）
  HotkeyEventTap           CGEvent 全局键盘监听（⌥ 状态跟踪）
  SwitcherPanel            NSPanel 覆盖层 + 自绘网格视图
  ThumbnailProvider        后台缩略图捕获与缓存
  AppCoordinator           事件 → 状态机 → UI/系统 效果分发
  PermissionsCenter        TCC 权限检查与引导
Sources/AltTab/            可执行入口（--dump 诊断、--selftest 自检）
Tests/AltTabTests/         TDD 测试运行器（swift run AltTabTests）
Scripts/e2e/               端到端 UI 自检（swift run AltTabE2E）
```

## 构建与运行

```bash
swift build                 # 调试构建
swift run AltTabTests       # 运行全部单元测试（57 个）
./Scripts/make-app-bundle.sh    # 打包 build/AltTab Dev.app（release + ad-hoc 签名）
open "build/AltTab Dev.app"     # 运行
```

诊断模式（不启动 GUI）：

```bash
.build/debug/AltTab --dump         # 枚举当前可切换窗口并打印
.build/debug/AltTab --dump --verbose   # 附带每个 app 的 AX 结果
```

## 权限（关键）

应用需要两个系统权限：

1. **辅助功能**（必需）：全局热键与 AX 窗口控制。首次启动会弹引导，
   在 系统设置 → 隐私与安全性 → 辅助功能 中开启 "AltTab Dev"。
2. **屏幕录制**（可选）：窗口缩略图与 CG 标题。不授权仍可完整切换，
   只是显示应用图标占位。

⚠️ **ad-hoc 签名注意事项**：每次 `make-app-bundle.sh` 重新打包都会改变
二进制签名（cdhash），已授予的权限会静默失效（系统设置里的开关仍显示
开启，但不再匹配）。重新打包后需要到系统设置里把开关**关掉再打开**。
开发迭代频繁时建议保持一个不重建的 bundle 用于日常使用。

## 端到端验证

```bash
./Scripts/verify-app.sh     # 真实 .app 在 launchd 环境的完整自检
./Scripts/run-e2e.sh        # swift JIT 模式（继承终端权限，可测缩略图管线）
```

`verify-app.sh` 驱动真实 app 执行 显示 → Tab 前进 → 方向键 → Esc 隐藏
序列，逐步截图并做像素级面板检测。**屏幕锁定时**自动降级为窗口服务器
证据判定（锁屏层会覆盖一切窗口合成，此时连原版 AltTab 的面板也无法
显示，属系统行为）。解锁后重跑可得到完整的像素级验证。

## TDD 开发流程

本仓库采用测试先行：每个逻辑模块先写失败测试（红），再实现（绿），
逐循环提交（`git log --oneline` 可见 4 个核心 TDD 循环）：

```bash
git log --oneline
# 2707fde feat(core): window filtering with in-repo TDD harness
# ...     feat(core): MRU window ordering
# ...     feat(core): grid navigation and adaptive layout math
# ...     feat(core): switcher state machine
```

本机仅有 Command Line Tools（无 Xcode），XCTest 不可用、swift-testing
的运行集成损坏，因此使用仓库内自带的轻量测试运行器
（`Tests/AltTabTests/TestHarness.swift`），退出码驱动红绿循环。

## 与原版的差异（核心功能取舍）

- 无偏好设置界面、无多快捷键自定义（固定 ⌥+Tab）
- 无 Space/显示器角标、无鼠标交互、无黑名单
- 缩略图用 CGWindowListCreateImage（已废弃但可用，经 dlsym 运行时解析
  以规避 SDK 移除），未迁移 ScreenCaptureKit
- 单层 7 列自适应网格（原版行列均可配置）

## 已知限制

- 重新打包后需重新授权（见上方 ad-hoc 说明）
- AX 权限被系统撤销时，轮询会保留旧窗口列表而非清空（避免闪空面板）
- 锁屏状态下无法进行视觉验证（系统限制，见 verify-app.sh）
