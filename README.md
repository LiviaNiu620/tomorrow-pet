# 明日团子（Tomorrow Pet）

一款原生 macOS 桌面任务与计划应用。桌面上的团子会在晚上提醒你结合 Calendar 和统一任务库安排第二天，并在周日提醒你制定本周计划。

## 已实现

- 原生 macOS 三栏任务中心与菜单栏入口
- 全部、收件箱、今天、明天、即时、短期、长期、等待中和已完成视图
- 个人、工作、学习、健康、家庭、财务领域
- 任务状态、领域、时间层级、优先级、项目、计划日期、截止日期、复查日期、估时、标签和备注
- 搜索、优先级筛选、快捷添加、完成、删除和任务详情编辑
- 每天、每周（可选星期）、每月重复任务；完成后生成下一实例并保留历史
- 垃圾箱支持恢复、永久删除和二次确认；任务操作支持最多 20 步 `⌘Z` 撤销
- 本地 JSON 持久化；日计划只引用并更新统一任务，不复制已有任务
- Apple Calendar 与 Google Calendar 明日/未来七天事件聚合读取
- Apple 已同步 Google 时按标题和起止时间去重，单一来源失败时另一来源仍可使用
- OpenAI Responses API 严格 JSON Schema 明日规划
- AI Top 3、额外候选、理由、估时和负荷评估；用户确认后才保存
- OpenAI API Key 通过 macOS Keychain 存储，初始为空
- 每周一至周六晚间提醒与周日晚间周计划提醒
- 三项目标、周任务选择和未来七天 Calendar 的本周计划页
- 明日 AI 计划会显示并参考本周目标、周任务与周计划备注
- 透明、置顶、可拖动的桌面宠物 `NSPanel`
- 独立设置窗口，可配置提醒时间、日历账户、AI 模型、API Key 和宠物显隐
- Light/Dark Mode、自适应系统颜色、键盘菜单和 Reduce Motion 友好设计

## 系统要求

- macOS 14 或更高版本
- Apple Silicon Mac（当前构建脚本输出 arm64）
- Swift 6 / Xcode Command Line Tools
- 使用 AI 规划时需要一个 OpenAI API Key
- 直连 Google Calendar 时需要自行创建 Google Desktop OAuth 客户端

## 构建和运行

```bash
./script/build_and_run.sh
```

也可以在 Codex 中使用项目自带的 **Run** 动作。应用包会生成在：

```text
dist/TomorrowPet.app
```

验证构建但不启动：

```bash
./script/build_and_run.sh --build
```

运行核心逻辑测试：

```bash
./script/build_and_run.sh --test
```

本机的 Command Line Tools 如果存在 Swift 编译器与 SDK 小版本不一致，脚本会在 `.build/` 内创建写时复制的兼容 SDK，不修改系统文件。正常安装的 Xcode/SwiftPM 环境会优先使用 `swift build`。

## 第一次使用

1. 启动应用，在系统提示中允许通知。
2. 打开“设置 → AI”，填写 OpenAI API Key。Key 不会写入项目或任务文件。
3. 在“明日 AI 计划”或“本周计划”中授权 Apple Calendar；也可以按下方步骤连接 Google Calendar。
4. 在任务中心添加任务，并通过任务详情补充领域、日期和预计时长。
5. 打开“明日 AI 计划”，让团子生成建议，检查后点击“确认并加入明天”。

## 连接 Google Calendar

Google OAuth 凭据不会随项目提供，初始保持为空。配置步骤：

1. 打开 [Google Cloud Console](https://console.cloud.google.com/)，创建或选择项目。
2. 启用 **Google Calendar API**。
3. 配置 OAuth consent screen；如果应用仍处于测试状态，把自己的 Google 账户加入测试用户。
4. 在“API 和服务 → 凭据”中创建 OAuth Client，应用类型选择 **Desktop app（桌面应用）**。
5. 启动明日团子，打开“设置 → 日历”，填写 Client ID 和 Client Secret，再点击“连接 Google Calendar”。
6. 浏览器授权完成后返回应用，勾选要提供给团子读取的日历。

授权流程使用 OAuth 2.0 Installed App、PKCE `S256`、随机 `state` 和本机随机端口 loopback redirect：

```text
http://127.0.0.1:<random-port>/oauth2callback
```

应用只申请 `https://www.googleapis.com/auth/calendar.readonly`。Client Secret、access token 和 refresh token 仅存储在 macOS Keychain；Client ID 和日历选择存储在 UserDefaults。断开时可同时请求 Google 撤销授权。没有 Google 凭据或 Google 暂时不可用时，本地任务与 Apple Calendar 仍可正常使用。

如果 Google consent screen 未发布或未通过验证，只允许测试用户登录，这是 Google Cloud 项目状态所致；将账户加入测试用户即可在个人使用场景中继续。

## OpenAI 数据范围

AI 规划会发送：

- 活动任务的标题、领域、状态、时间层级、优先级、估时、截止日期和计划日期
- Apple/Google Calendar 事件的标题、开始/结束时间、日历名称和来源

不会发送 Calendar 参与者、地址、视频会议链接或事件备注。AI 不会直接修改 Calendar。默认模型根据实现时的[官方 OpenAI 模型目录](https://developers.openai.com/api/docs/models)设置为 `gpt-5.6`，可在设置中修改。

Responses API 与结构化输出实现依据：

- [Responses API：Create a response](https://developers.openai.com/api/reference/resources/responses/methods/create)
- [Structured model outputs](https://developers.openai.com/api/docs/guides/structured-outputs)

## 数据位置

- 任务和计划：`~/Library/Application Support/TomorrowPet/task-store.json`
- OpenAI API Key：macOS Keychain
- Google OAuth Client Secret 和令牌：macOS Keychain
- 提醒偏好、Google Client ID 和日历选择：macOS UserDefaults

普通删除会把任务移入垃圾箱，并保留原状态和删除时间；可以恢复，也可以在二次确认后永久删除或清空垃圾箱。最近 20 步任务添加、编辑、完成、恢复和移入垃圾箱操作可通过 `⌘Z` 逐步撤销。应用不会自动删除 Calendar 事件，也不会自动向 Calendar 写入时间块。

更完整的产品定位、交互流程、指标和迭代范围见 [PRODUCT_SPEC.md](PRODUCT_SPEC.md)。
