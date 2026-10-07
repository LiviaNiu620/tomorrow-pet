# 明日团子 Windows 版（0.3.0）

Windows 10/11 x64 的独立 Electron 客户端，沿用 Dango 粉／白／抹茶绿风格。macOS 继续使用仓库中的原生 SwiftUI 客户端。

## 功能

- 今天／明天任务、时间轴拖动排程、Top 3、日历和 SOP 信息。
- 任务库、优先级、领域、日期、备注、项目、标签、重复任务、垃圾箱恢复与最近 20 步撤销。
- 本周七天安排和按周保存的三个目标。
- 按日期打卡的 SOP，支持每天、周日和月末周日，支持编辑习惯。
- 专注计时使用实际截止时间，支持暂停、恢复和专注记录。
- 每日复盘、精力／心情及待办顺延。
- OpenAI 明日计划、严格输出校验、确认后写入任务；密钥由系统加密保存。
- 桌面团子、系统托盘、应用运行时计划提醒、Ctrl+Shift+Space 全局随手记。
- ICS 日历快照导入，支持时区与未来 60 天的重复事件；JSON 备份和 Mac 数据导入。

## 与 Mac 版的差异

本版不是 SwiftUI 的自动转换结果，两套客户端的核心数据字段兼容，但界面实现独立。Windows 当前不包含 Apple Calendar 原生权限、Google OAuth 实时同步、AI 子任务拆解和可编辑的完整 SOP 时间块界面。可导入 Mac 的 SOP 时间块并用于 AI 任务放置。日历使用 `.ics` 快照，需再次导入才能更新。Windows 提醒要求应用仍在托盘运行，不是关机后的系统调度任务。

## 开发和打包

需要 Node.js 24（最低 22.12）、npm，以及构建安装包时使用 Windows。

```bash
cd windows
npm ci
npm run check
npm test
npm run smoke
npm start
npm run dist
```

`npm run dist` 生成 `dist/windows/TomorrowPet-0.3.0-Windows-x64-Setup.exe` 和 ZIP 解压运行包。GitHub Actions 使用 Windows runner 实际运行测试及 Electron 冒烟测试，然后生成安装程序与 SHA-256 校验文件。

默认安装包未配置 Windows 代码签名，系统可能显示未知发布者。可通过 electron-builder 的标准证书环境变量配置正式签名；仓库不保存证书或私钥。

## 数据迁移

Windows 数据保存在 `%APPDATA%/TomorrowPet-Windows/dango.json`，每次写入保留上一份 `.bak`，原子替换当前文件。文件损坏时停止载入并保留原文件。密钥单独保存在系统加密后的文件中，不进入导出备份。

设置 → 导入备份，可分别导入 Mac 的 `task-store.json`、`daily-sop.json` 和 `journal.json`。任务按 ID 合并；相同 ID 使用导入记录更新。导入前可先导出当前 Windows 备份。Mac 不自动读取 Windows 的完整备份格式。

## 验证范围

核心逻辑通过 Node 测试验证；Electron 冒烟测试使用独立临时目录，不读取真实任务数据，检查七个页面、任务创建与撤销 IPC 和横向溢出。AI 测试使用本地数据验证 schema 和映射逻辑，不产生真实 API 费用。实际 API 调用和系统通知应在用户配置后进行验收。

实现参考：[OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs)。
