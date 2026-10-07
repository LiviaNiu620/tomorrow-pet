# 明日团子（Tomorrow Pet）

当前开发版为 **0.3.0 / Dango**：今天时间轴、本周容量规划、任务库、习惯 · SOP、复盘与专注六个页面，采用三色团子界面。任务支持自然语言录入、时间轴安排和周目标关联；专注与复盘保存于独立的 `journal.json`。

macOS 分发包构建：`./script/package_macos.sh`，输出至 `dist/releases/`。GitHub Actions 自动构建 Apple Silicon 与 Intel 的 DMG、ZIP 和校验文件。新版分析、平台限制和签名说明见 [0.3.0 分发说明](docs/RELEASE-0.3.0.md)。Windows 需要独立客户端移植，当前 SwiftUI 源码不支持直接生成 Windows 安装包。

一款原生 macOS 桌面任务与计划应用。桌面上的团子会在晚上提醒你结合 Calendar 和统一任务库安排第二天，并在周日提醒你制定本周计划。

## 已实现

- 原生 macOS 三栏任务中心与菜单栏入口
- 全部、收件箱、今天、明天、即时、短期、长期、等待中和已完成视图
- 个人、工作、学习、健康、家庭、财务领域
- 任务状态、领域、时间层级、优先级、项目、计划日期、截止日期、复查日期、估时、标签和备注
- 搜索、优先级筛选、快捷添加、完成、删除和任务详情编辑；今天、明天、即时、短期、长期等视图选择任务后都会自动打开同一套编辑器
- 每天、每周（可选星期）、每月重复任务；完成后生成下一实例并保留历史
- 垃圾箱支持恢复、永久删除和二次确认；任务操作支持最多 20 步 `⌘Z` 撤销
- 本地 JSON 持久化；日计划只引用并更新统一任务，不复制已有任务
- Apple Calendar 与 Google Calendar 明日/未来七天事件聚合读取
- Apple 已同步 Google 时按标题和起止时间去重，单一来源失败时另一来源仍可使用
- OpenAI Responses API 严格 JSON Schema 明日规划
- AI Top 3、额外候选、理由、估时和负荷评估；建议可在确认前修改标题、分类、优先级、估时与说明
- 任务详情支持“AI 自动拆解和规划”：结合期限、周期、任务库、未来 14 天 Calendar、本周计划和每日 SOP 生成可编辑步骤，确认后创建关联子任务
- OpenAI API Key 通过 macOS Keychain 存储，初始为空
- 每周一至周六晚间提醒与周日晚间周计划提醒
- 三项目标、周任务选择和未来七天 Calendar 的本周计划页
- 明日 AI 计划会显示并参考本周目标、周任务与周计划备注
- 独立“每日 SOP”打卡视图，按日期保存完成状态，不污染普通 Todo 列表；模板分组、时间、内容、说明和 AI 上下文开关均可编辑
- 固定早晨、Email、工作、健身、通勤、学习、复盘与睡眠节奏；周日自动追加周计划清单，月末最后一个周日自动追加月度复盘
- AI 明日计划会把 SOP 时间视为固定占用，避免重复建议日常习惯或把晚间时间安排过载
- “明日补充事项”支持输入 Calendar 以外的临时安排；AI 会逐条整理为任务，用户确认后加入明天
- 透明、置顶、可拖动的桌面宠物 `NSPanel`
- 独立设置窗口，可配置提醒时间、日历账户、AI 模型、API Key 和宠物显隐
- Dango 主界面采用固定浅色内容区与深色侧栏，提供键盘导航和命令面板；旧版部分视图仍使用系统颜色

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

## 更新后仍显示旧界面

GitHub 更新的是源码；正在运行的旧应用需要退出，并重新构建和启动：

```bash
./script/build_and_run.sh --verify
```

脚本先完成编译，再通过 macOS 请求现有实例正常退出，确认退出后替换 `dist/TomorrowPet.app` 并启动。若退出被拒绝或未完成，脚本会停止，不强制结束应用。运行环境需要允许访问 macOS 应用进程和 LaunchServices。

在“设置 → 通用 → 关于明日团子”查看版本、源码提交、构建时间和实际应用路径。新版为 `0.3.0`，主导航包含今天、本周、任务库、习惯 · SOP、复盘、专注；今天页显示统一时间轴。

## 第一次使用

1. 启动应用，在系统提示中允许通知。
2. 打开“设置 → AI”，填写 OpenAI API Key。Key 不会写入项目或任务文件。
3. 在“明日 AI 计划”或“本周计划”中授权 Apple Calendar；也可以按下方步骤连接 Google Calendar。
4. 在任务中心添加任务，并通过任务详情补充领域、日期和预计时长。
5. 打开“明日 AI 计划”，让团子生成建议，检查后点击“确认并加入明天”。
6. 选择任一较大的任务，在右侧详情中点击“AI 自动拆解和规划”，编辑步骤后再确认创建子任务。
7. 从侧边栏打开“每日 SOP”（快捷键 `⇧⌘S`），按当天时间线打卡；使用工具栏“编辑 SOP”自定义模板，周日和月末会自动出现额外计划清单。

## 连接 Google Calendar

Google OAuth 凭据不会随项目提供，初始保持为空。配置步骤：

1. 打开 [Google Cloud Console](https://console.cloud.google.com/)，创建或选择项目。
2. 启用 **Google Calendar API**。
3. 配置 OAuth consent screen；如果应用仍处于测试状态，把自己的 Google 账户加入测试用户。
4. 在“API 和服务 → 凭据”中创建 OAuth Client，应用类型选择 **Desktop app（桌面应用）**。
5. 在凭据列表中点击该 Desktop app 客户端的下载按钮，取得 OAuth JSON 文件。
6. 启动明日团子，打开“设置 → 日历”，点击“导入 Desktop OAuth JSON 并连接”，选择刚下载的文件。
7. 在浏览器中完成授权，返回应用后勾选要提供给团子读取的日历。

Apple Calendar 与 Google Calendar 是两个独立数据源，可以同时连接。连接完成后，“设置 → 日历”的连接总览会显示 **Apple + Google Calendar**；统一同步会合并两边事件，并对 Apple 中已经同步的 Google 事件自动去重。AI 明日计划和周计划使用合并后的结果。

授权流程使用 OAuth 2.0 Installed App、PKCE `S256`、随机 `state` 和本机随机端口 loopback redirect：

```text
http://127.0.0.1:<random-port>/oauth2callback
```

应用只申请 `https://www.googleapis.com/auth/calendar.readonly`。导入的 JSON 不会复制进应用项目或任务数据；授权成功后，Client Secret、access token 和 refresh token 仅存储在 macOS Keychain，Client ID 和日历选择存储在 UserDefaults。断开时可同时请求 Google 撤销授权。没有 Google 凭据或 Google 暂时不可用时，本地任务与 Apple Calendar 仍可正常使用。设置页也保留了手动填写 Client ID / Client Secret 的备用入口。

如果 Google consent screen 未发布或未通过验证，只允许测试用户登录，这是 Google Cloud 项目状态所致；将账户加入测试用户即可在个人使用场景中继续。如果浏览器授权成功但读取不到日历列表，请先确认项目已启用 **Google Calendar API**。

## OpenAI 数据范围

AI 规划会发送：

- 活动任务的标题、领域、状态、时间层级、优先级、估时、截止日期和计划日期
- Apple/Google Calendar 事件的标题、开始/结束时间、日历名称和来源

当你主动使用“AI 自动拆解和规划”时，还会发送所选任务的备注、项目、复查日期和周期，本周计划，以及每日 SOP 中启用了“提供给 AI”的项目。拆解步骤始终先显示为本地预览，只有点击确认后才会写入任务库。

不会发送 Calendar 参与者、地址、视频会议链接或事件备注。AI 不会直接修改 Calendar。默认模型根据实现时的[官方 OpenAI 模型目录](https://developers.openai.com/api/docs/models)设置为 `gpt-5.6`，可在设置中修改。

Responses API 与结构化输出实现依据：

- [Responses API：Create a response](https://developers.openai.com/api/reference/resources/responses/methods/create)
- [Structured model outputs](https://developers.openai.com/api/docs/guides/structured-outputs)

## 数据位置

- 任务和计划：`~/Library/Application Support/TomorrowPet/task-store.json`
- 每日 SOP 模板和打卡：`~/Library/Application Support/TomorrowPet/daily-sop.json`
- OpenAI API Key：macOS Keychain
- Google OAuth Client Secret 和令牌：macOS Keychain
- 提醒偏好、Google Client ID 和日历选择：macOS UserDefaults

普通删除会把任务移入垃圾箱，并保留原状态和删除时间；可以恢复，也可以在二次确认后永久删除或清空垃圾箱。最近 20 步任务添加、编辑、完成、恢复和移入垃圾箱操作可通过 `⌘Z` 逐步撤销。应用不会自动删除 Calendar 事件，也不会自动向 Calendar 写入时间块。

更完整的产品定位、交互流程、指标和迭代范围见 [PRODUCT_SPEC.md](PRODUCT_SPEC.md)。
