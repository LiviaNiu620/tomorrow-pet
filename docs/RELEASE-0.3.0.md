# 0.3.0 新版分析与分发

## 已确认的新版

当前分支为 `redesign-dango`。新版入口是 `RootView`，已替代旧 `ContentView`。实际打开的应用包为 `dist/TomorrowPet.app`，版本 0.3.0。今天页面已通过原生窗口检查，能够显示 Google Calendar 事件、SOP 时段、任务候选和可用时长。

新版包含六个主要页面：今天、本周、任务库、习惯 · SOP、复盘、专注。设计采用粉、白、抹茶绿及墨色描边，任务时间轴与日历、SOP 固定占用共用一套排程计算。新增自然语言录入、任务顺延、周目标关联、专注计时、每日复盘及全局快捷键。35 项核心自检通过。

## 分发前需要关注的边界

- 主窗口关闭后，桌宠等入口仍使用 `AppWindowActivator` 激活现有窗口；窗口不存在时没有创建新窗口的分支，建议补充恢复窗口行为。
- 今天页固定为时间轴加右侧卡片，`RootView` 最小窗口为 1180 × 760；实际检查中标题区控件存在挤压，较小屏幕和不同文字尺寸应单独验收。
- `FocusTimer` 每秒减一，没有使用截止时间推导剩余时长。睡眠、后台暂停会导致计时与真实经过时间偏离。
- 新版任务详情采用即时保存，`JournalStore` 保存复盘和专注记录，但本地写入错误目前仅输出日志；发布前宜增加用户可见的失败提示与恢复机制。
- 当前 RootView 强制浅色。旧 README 中“跟随系统明暗模式”的描述不适用于这套新界面。
- SwiftUI、AppKit、EventKit、Keychain、Carbon 全局快捷键与 UserNotifications 是 macOS 平台实现，不能直接打包成 Windows EXE。Windows 需要单独实现界面及这些适配层。

以上为代码检查与有限窗口检查的结果，不代表所有功能均已完成端到端验收。没有发送新的 AI 请求、改变日历授权或向真实任务库添加测试数据。

## macOS 打包

```bash
./script/package_macos.sh
```

输出目录为 `dist/releases/`，包含 DMG、ZIP 与 SHA-256 校验文件。DMG 中的应用可拖到 Applications 安装。打包在独立的 `.build/release-staging/` 内完成，不退出正在使用的应用。

指定架构：

```bash
DANGO_ARCH=arm64 ./script/package_macos.sh
DANGO_ARCH=x86_64 ./script/package_macos.sh
```

GitHub Actions 为两种架构分别构建，运行核心测试，并将分发包上传为工作流 artifacts。

默认使用本地 ad-hoc 签名，不等于 Apple Developer ID 签名或 Apple 公证。用于公开分发时，可以在构建机器上配置 `MACOS_SIGNING_IDENTITY` 和 `MACOS_NOTARY_PROFILE`，脚本会对应用签名并提交 DMG 公证。脚本不会自动安装证书或上传私钥。

## Windows 范围

Windows 客户端的功能范围正在与项目所有者确认。该分支暂不宣称已生成 Windows 安装程序，也不把 macOS SwiftUI 二进制误标为跨平台软件。
