import EventKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var calendarService: CalendarService
    @ObservedObject var googleCalendarService: GoogleCalendarService

    @State private var apiKey = ""
    @State private var saveMessage = ""
    @State private var dailyTime = Date.now
    @State private var weeklyTime = Date.now
    @State private var googleClientID = ""
    @State private var googleClientSecret = ""
    @State private var showGoogleCredentialImporter = false
    @State private var showManualGoogleCredentials = false
    @State private var importedGoogleProjectName: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            calendarTab
                .tabItem { Label("日历", systemImage: "calendar") }

            aiTab
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 680, height: 680)
        .padding(8)
        .onAppear {
            apiKey = KeychainService.readAPIKey()
            dailyTime = preferences.dailyTime
            weeklyTime = preferences.weeklyTime
            googleClientID = preferences.googleClientID
            googleClientSecret = KeychainService.readGoogleClientSecret()
        }
        .fileImporter(
            isPresented: $showGoogleCredentialImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false,
            onCompletion: handleGoogleCredentialImport
        )
    }

    private var generalTab: some View {
        Form {
            Section("提醒") {
                DatePicker("周一至周六", selection: $dailyTime, displayedComponents: .hourAndMinute)
                DatePicker("周日周计划", selection: $weeklyTime, displayedComponents: .hourAndMinute)
                Text("周日只发送一次周计划提醒；完成周计划后可继续安排周一。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("保存提醒时间") {
                    preferences.setDailyTime(dailyTime)
                    preferences.setWeeklyTime(weeklyTime)
                    Task {
                        try? await ReminderService.shared.schedule(preferences: preferences)
                        saveMessage = "提醒时间已保存"
                    }
                }
            }

            Section("桌面宠物") {
                Toggle("显示桌面团子", isOn: $preferences.petEnabled)
                    .onChange(of: preferences.petEnabled) { _, enabled in
                        NotificationCenter.default.post(name: .petVisibilityChanged, object: enabled)
                    }
            }

            if !saveMessage.isEmpty {
                Text(saveMessage)
                    .font(.caption)
                    .foregroundStyle(saveMessage.contains("失败") ? .red : .green)
            }
        }
        .formStyle(.grouped)
    }

    private var calendarTab: some View {
        Form {
            Section("连接总览") {
                LabeledContent("当前数据源", value: calendarService.sourceSummary)
                calendarStatusRow(
                    title: "Apple Calendar",
                    connected: calendarService.hasAccess
                )
                calendarStatusRow(
                    title: "Google Calendar",
                    connected: googleCalendarService.isConnected
                )

                if calendarService.hasAccess && googleCalendarService.isConnected {
                    Label(
                        "已同时连接 Apple 与 Google；事件会合并、去重后提供给 AI。",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.green)
                } else {
                    Text("Apple 与 Google 可以同时启用；连接一种不会关闭另一种。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("同步 Apple + Google") {
                        Task { await refreshCalendarData() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        !calendarService.hasAnyCalendarAccess
                            || calendarService.isLoading
                            || googleCalendarService.isBusy
                    )

                    if calendarService.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }

                if let date = calendarService.lastSuccessfulSyncAt {
                    LabeledContent(
                        "最近同步",
                        value: date.formatted(date: .omitted, time: .shortened)
                    )
                    .font(.caption)
                }

                if let error = calendarService.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Apple Calendar") {
                LabeledContent("状态", value: appleAuthorizationText)
                Text("Apple Calendar 由系统权限保护，只读取事件，不会新增、修改或删除日历内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(calendarService.hasAccess ? "重新读取 Apple Calendar" : "授权 Apple Calendar") {
                    Task { await calendarService.requestAppleAccessAndRefresh() }
                }
                .disabled(calendarService.isLoading)
            }

            Section("Google Calendar") {
                if googleCalendarService.isConnected {
                    HStack {
                        Button("刷新日历列表") {
                            Task {
                                do {
                                    try await googleCalendarService.loadCalendars()
                                    await refreshCalendarData()
                                } catch {
                                    googleCalendarService.errorMessage = error.localizedDescription
                                }
                            }
                        }

                        Button("撤销授权并断开", role: .destructive) {
                            Task {
                                await googleCalendarService.disconnect()
                                await refreshCalendarData()
                            }
                        }

                        if googleCalendarService.isBusy {
                            ProgressView().controlSize(.small)
                        }
                    }
                } else {
                    Button("导入 Desktop OAuth JSON 并连接") {
                        showGoogleCredentialImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(googleCalendarService.isBusy)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. 在 Google Cloud 中启用 Google Calendar API")
                        Text("2. 创建 Desktop app（桌面应用）OAuth 客户端")
                        Text("3. 下载 JSON，并在这里导入后完成浏览器授权")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let project = importedGoogleProjectName {
                        Label("已导入项目：\(project)", systemImage: "doc.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Link(
                            "打开 Google Cloud 凭据页面",
                            destination: URL(string: "https://console.cloud.google.com/apis/credentials")!
                        )
                        Link(
                            "启用 Calendar API",
                            destination: URL(string: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")!
                        )
                    }

                    DisclosureGroup(
                        "手动填写 OAuth 凭据",
                        isExpanded: $showManualGoogleCredentials
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("OAuth Client ID", text: $googleClientID)
                                .font(.body.monospaced())
                            SecureField("OAuth Client Secret", text: $googleClientSecret)
                            Text("仅支持 Desktop app 客户端。Client Secret 和授权令牌仅保存在 macOS Keychain。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("使用手动凭据连接") {
                                connectGoogleWithCurrentCredentials()
                            }
                            .disabled(
                                googleCalendarService.isBusy
                                    || googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                        .padding(.top, 8)
                    }
                }

                if let status = googleCalendarService.statusMessage {
                    Label(status, systemImage: googleCalendarService.isConnected ? "checkmark.circle.fill" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(googleCalendarService.isConnected ? .green : .secondary)
                }
                if let error = googleCalendarService.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if googleCalendarService.isConnected {
                Section("读取的 Google 日历") {
                    if googleCalendarService.calendars.isEmpty {
                        Text("尚未读取到日历。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(googleCalendarService.calendars) { calendar in
                            Toggle(calendar.displayName, isOn: Binding(
                                get: { googleCalendarService.isCalendarEnabled(calendar.id) },
                                set: { enabled in
                                    googleCalendarService.setCalendar(calendar.id, enabled: enabled)
                                    Task { await refreshCalendarData() }
                                }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    Text("仅申请 calendar.readonly；Google 的重复事件会按实际发生日期展开。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aiTab: some View {
        Form {
            Section("OpenAI") {
                SecureField("API Key（以 sk- 开头）", text: $apiKey)
                Text("Key 初始为空，只保存在 macOS Keychain，不会写进源码、任务文件或日志。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("模型", text: $preferences.openAIModel)
                Text("默认使用 \(AppConstants.defaultModel)。如果你的账户不可用，可以改为账户已开通的 Responses API 模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("保存 API Key") { saveKey() }
                        .buttonStyle(.borderedProminent)
                    Button("清除") {
                        apiKey = ""
                        saveKey()
                    }
                }

                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(saveMessage.contains("失败") ? .red : .green)
                }
            }

            Section("AI 数据范围") {
                Label("发送任务标题、领域、状态、日期、优先级和预计时长", systemImage: "checkmark.shield")
                Label("发送 Apple/Google Calendar 事件标题、时间和日历名称", systemImage: "calendar")
                Label("不发送参与者、地址、会议链接或 Calendar 备注", systemImage: "hand.raised")
            }
        }
        .formStyle(.grouped)
    }

    private var appleAuthorizationText: String {
        switch calendarService.authorizationStatus {
        case .fullAccess: "已授权"
        case .writeOnly: "仅写入（本应用需要读取）"
        case .denied: "已拒绝"
        case .restricted: "受系统限制"
        case .notDetermined: "尚未询问"
        @unknown default: "未知"
        }
    }

    @ViewBuilder
    private func calendarStatusRow(title: String, connected: Bool) -> some View {
        HStack {
            Label(title, systemImage: connected ? "checkmark.circle.fill" : "circle")
            Spacer()
            Text(connected ? "已连接" : "未连接")
                .foregroundStyle(connected ? .green : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func handleGoogleCredentialImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                throw GoogleCalendarError.invalidCredentialFile
            }
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess { url.stopAccessingSecurityScopedResource() }
            }

            let credentials = try GoogleOAuthService.desktopCredentials(
                from: Data(contentsOf: url)
            )
            googleClientID = credentials.clientID
            googleClientSecret = credentials.clientSecret
            importedGoogleProjectName = credentials.projectID
            googleCalendarService.errorMessage = nil

            Task {
                let connected = await googleCalendarService.connect(
                    clientID: credentials.clientID,
                    clientSecret: credentials.clientSecret
                )
                if connected {
                    googleClientID = preferences.googleClientID
                    googleClientSecret = KeychainService.readGoogleClientSecret()
                    await refreshCalendarData()
                }
            }
        } catch {
            if (error as NSError).code == NSUserCancelledError { return }
            googleCalendarService.statusMessage = nil
            googleCalendarService.errorMessage = error.localizedDescription
        }
    }

    private func connectGoogleWithCurrentCredentials() {
        Task {
            let connected = await googleCalendarService.connect(
                clientID: googleClientID,
                clientSecret: googleClientSecret
            )
            if connected {
                googleClientID = preferences.googleClientID
                googleClientSecret = KeychainService.readGoogleClientSecret()
                await refreshCalendarData()
            }
        }
    }

    private func refreshCalendarData() async {
        await calendarService.refreshTomorrow()
        await calendarService.refreshUpcomingWeek()
    }

    private func saveKey() {
        do {
            try KeychainService.saveAPIKey(apiKey)
            saveMessage = apiKey.isEmpty ? "API Key 已清除" : "API Key 已安全保存"
        } catch {
            saveMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}

extension Notification.Name {
    static let petVisibilityChanged = Notification.Name("TomorrowPet.petVisibilityChanged")
}
