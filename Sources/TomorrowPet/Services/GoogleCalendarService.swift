import Combine
import Foundation
import OSLog

@MainActor
final class GoogleCalendarService: ObservableObject {
    static let shared = GoogleCalendarService(preferences: .shared)

    @Published private(set) var calendars: [GoogleCalendarDescriptor] = []
    @Published private(set) var isConnected: Bool
    @Published private(set) var isBusy = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let oauth = GoogleOAuthService()
    private let preferences: AppPreferences
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "GoogleCalendar")

    init(preferences: AppPreferences) {
        self.preferences = preferences
        isConnected = KeychainService.readGoogleToken() != nil
    }

    @discardableResult
    func connect(clientID: String, clientSecret: String) async -> Bool {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        statusMessage = "正在等待 Google 授权…"
        do {
            let token = try await oauth.authorize(clientID: clientID, clientSecret: clientSecret)
            preferences.googleClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            try KeychainService.saveGoogleClientSecret(clientSecret)
            try KeychainService.saveGoogleToken(token)
            isConnected = true
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            logger.error("Google Calendar authorization failed: \(error.localizedDescription, privacy: .private)")
            return false
        }

        do {
            try await loadCalendars()
            statusMessage = "Google Calendar 已连接"
            logger.info("Google Calendar authorization and calendar list sync succeeded")
            return true
        } catch {
            statusMessage = "Google 账户已授权；日历列表尚未同步"
            errorMessage = "\(error.localizedDescription)\n请确认该 Google Cloud 项目已启用 Google Calendar API，然后点击“刷新日历列表”。"
            logger.error("Google Calendar list sync failed after authorization: \(error.localizedDescription, privacy: .private)")
            return true
        }
    }

    func restoreConnection() async {
        guard isConnected, !preferences.googleClientID.isEmpty else { return }
        do {
            try await loadCalendars()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Google Calendar restore failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func disconnect(revoke: Bool = true) async {
        isBusy = true
        if revoke, let token = KeychainService.readGoogleToken() {
            await oauth.revoke(token)
        }
        try? KeychainService.saveGoogleToken(nil)
        calendars = []
        isConnected = false
        preferences.selectedGoogleCalendarIDs = []
        preferences.googleCalendarSelectionConfigured = false
        statusMessage = "已断开 Google Calendar"
        errorMessage = nil
        isBusy = false
    }

    func setCalendar(_ id: String, enabled: Bool) {
        if enabled {
            preferences.selectedGoogleCalendarIDs.insert(id)
        } else {
            preferences.selectedGoogleCalendarIDs.remove(id)
        }
        preferences.googleCalendarSelectionConfigured = true
    }

    func isCalendarEnabled(_ id: String) -> Bool {
        preferences.selectedGoogleCalendarIDs.contains(id)
    }

    func loadCalendars() async throws {
        let token = try await validAccessToken()
        var pageToken: String?
        var result: [GoogleCalendarDescriptor] = []
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
            var queryItems = [
                URLQueryItem(name: "maxResults", value: "250"),
                URLQueryItem(name: "minAccessRole", value: "reader")
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = queryItems
            let response: GoogleCalendarListResponse = try await get(components.url!, token: token)
            result.append(contentsOf: response.items.map {
                GoogleCalendarDescriptor(
                    id: $0.id,
                    summary: $0.summary,
                    primary: $0.primary ?? false,
                    selected: $0.selected ?? false,
                    backgroundColor: $0.backgroundColor
                )
            })
            pageToken = response.nextPageToken
        } while pageToken != nil

        calendars = result.sorted {
            if $0.primary != $1.primary { return $0.primary }
            return $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending
        }

        if !preferences.googleCalendarSelectionConfigured {
            let defaults = calendars.filter { $0.selected || $0.primary }.map(\.id)
            preferences.selectedGoogleCalendarIDs = Set(defaults.isEmpty ? calendars.map(\.id) : defaults)
            preferences.googleCalendarSelectionConfigured = true
        } else {
            let availableIDs = Set(calendars.map(\.id))
            preferences.selectedGoogleCalendarIDs.formIntersection(availableIDs)
        }
    }

    func events(from start: Date, to end: Date) async throws -> [CalendarEventSummary] {
        guard isConnected else { return [] }
        if calendars.isEmpty { try await loadCalendars() }
        let token = try await validAccessToken()
        let selected = calendars.filter { preferences.selectedGoogleCalendarIDs.contains($0.id) }
        var allEvents: [CalendarEventSummary] = []

        for calendar in selected {
            allEvents.append(contentsOf: try await events(
                calendar: calendar,
                from: start,
                to: end,
                token: token
            ))
        }
        return allEvents.sorted { $0.startDate < $1.startDate }
    }

    private func events(
        calendar: GoogleCalendarDescriptor,
        from start: Date,
        to end: Date,
        token: GoogleOAuthToken
    ) async throws -> [CalendarEventSummary] {
        let encodedCalendarID = calendar.id.addingPercentEncoding(withAllowedCharacters: .googlePathComponentAllowed)
            ?? calendar.id
        var pageToken: String?
        var result: [CalendarEventSummary] = []
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedCalendarID)/events")!
            var queryItems = [
                URLQueryItem(name: "timeMin", value: Self.rfc3339(start)),
                URLQueryItem(name: "timeMax", value: Self.rfc3339(end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "showDeleted", value: "false"),
                URLQueryItem(name: "maxResults", value: "2500")
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = queryItems
            let response: GoogleEventsResponse = try await get(components.url!, token: token)
            result.append(contentsOf: response.items.compactMap { event in
                guard event.status != "cancelled",
                      let dates = Self.dates(for: event) else { return nil }
                return CalendarEventSummary(
                    id: "google:\(calendar.id):\(event.id)",
                    title: event.summary.flatMap { $0.isEmpty ? nil : $0 } ?? "未命名事件",
                    startDate: dates.start,
                    endDate: dates.end,
                    isAllDay: dates.allDay,
                    calendarTitle: "\(calendar.summary) · Google",
                    source: .google
                )
            })
            pageToken = response.nextPageToken
        } while pageToken != nil
        return result
    }

    private func validAccessToken() async throws -> GoogleOAuthToken {
        guard var token = KeychainService.readGoogleToken() else {
            isConnected = false
            throw GoogleCalendarError.disconnected
        }
        if token.needsRefresh {
            let clientID = preferences.googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
            let secret = KeychainService.readGoogleClientSecret()
            guard !clientID.isEmpty else { throw GoogleCalendarError.missingClientID }
            guard !secret.isEmpty else { throw GoogleCalendarError.missingClientSecret }
            token = try await oauth.refreshedToken(token, clientID: clientID, clientSecret: secret)
            try KeychainService.saveGoogleToken(token)
        }
        return token
    }

    private func get<T: Decodable>(_ url: URL, token: GoogleOAuthToken) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleCalendarError.api(status: http.statusCode, message: Self.apiErrorMessage(data))
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GoogleCalendarError.decoding(error.localizedDescription)
        }
    }

    static func dates(for event: GoogleEvent, calendar: Calendar = .current) -> (start: Date, end: Date, allDay: Bool)? {
        if let startText = event.start.dateTime,
           let endText = event.end.dateTime,
           let start = parseRFC3339(startText),
           let end = parseRFC3339(endText) {
            return (start, end, false)
        }
        guard let startText = event.start.date, let endText = event.end.date else { return nil }
        var dateCalendar = calendar
        if let timeZoneID = event.start.timeZone, let timeZone = TimeZone(identifier: timeZoneID) {
            dateCalendar.timeZone = timeZone
        }
        let pieces = startText.split(separator: "-").compactMap { Int($0) }
        let endPieces = endText.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3, endPieces.count == 3,
              let start = dateCalendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2])),
              let end = dateCalendar.date(from: DateComponents(year: endPieces[0], month: endPieces[1], day: endPieces[2])) else {
            return nil
        }
        return (start, end, true)
    }

    private static func parseRFC3339(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func apiErrorMessage(_ data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return "Google API 请求失败。" }
        return error["message"] as? String ?? "Google API 请求失败。"
    }
}

private extension CharacterSet {
    static let googlePathComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~@"
    )
}
