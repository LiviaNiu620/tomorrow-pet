import Foundation

struct GoogleOAuthToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scope: String
    var tokenType: String

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow < 90
    }
}

struct GoogleCalendarDescriptor: Identifiable, Codable, Hashable {
    var id: String
    var summary: String
    var primary: Bool
    var selected: Bool
    var backgroundColor: String?

    var displayName: String {
        primary ? "\(summary)（主要）" : summary
    }
}

struct GoogleCalendarListResponse: Decodable {
    var nextPageToken: String?
    var items: [GoogleCalendarListItem]

    enum CodingKeys: String, CodingKey {
        case nextPageToken
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
        items = try container.decodeIfPresent([GoogleCalendarListItem].self, forKey: .items) ?? []
    }
}

struct GoogleCalendarListItem: Decodable {
    var id: String
    var summary: String
    var primary: Bool?
    var selected: Bool?
    var backgroundColor: String?
}

struct GoogleEventsResponse: Decodable {
    var nextPageToken: String?
    var items: [GoogleEvent]

    enum CodingKeys: String, CodingKey {
        case nextPageToken
        case items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
        items = try container.decodeIfPresent([GoogleEvent].self, forKey: .items) ?? []
    }
}

struct GoogleEvent: Decodable {
    struct EventDate: Decodable {
        var date: String?
        var dateTime: String?
        var timeZone: String?
    }

    var id: String
    var status: String?
    var summary: String?
    var start: EventDate
    var end: EventDate
}

struct GoogleTokenResponse: Decodable {
    var accessToken: String
    var expiresIn: Int
    var refreshToken: String?
    var scope: String?
    var tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}
