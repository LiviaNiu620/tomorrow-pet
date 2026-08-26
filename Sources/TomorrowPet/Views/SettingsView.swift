import EventKit
import SwiftUI

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

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            calendarTab
                .tabItem { Label("日历", systemImage: "calendar") }

            aiTab
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .frame(width: 640, height: 600)
        .padding(8)
        .onAppear {
            apiKey = KeychainService.readAPIKey()
            dailyTime = preferences.dailyTime
            weeklyTime = preferences.weeklyTime
            googleClientID = preferences.googleClientID
            googleClientSecret = KeychainService.readGoogleClientSecret()
        }
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
                TextField("OAuth Client ID", text: $googleClientID)
                    .font(.body.monospaced())
                SecureField("OAuth Client Secret", text: $googleClientSecret)
                Text("凭据初始为空。请在 Google Cloud 创建“桌面应用”OAuth 客户端；Client Secret 和授权令牌仅保存在 macOS Keychain。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(
                    "打开 Google Cloud 凭据页面",
                    destination: URL(string: "https://console.cloud.google.com/apis/credentials")!
                )

                HStack {
                    if googleCalendarService.isConnected {
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
                    } else {
                        Button("连接 Google Calendar") {
                            Task {
                                await googleCalendarService.connect(
                                    clientID: googleClientID,
                                    clientSecret: googleClientSecret
                                )
                                if googleCalendarService.isConnected {
                                    googleClientID = preferences.googleClientID
                                    await refreshCalendarData()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            googleCalendarService.isBusy
                                || googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }

                    if googleCalendarService.isBusy {
                        ProgressView().controlSize(.small)
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
