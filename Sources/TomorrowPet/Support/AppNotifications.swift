import Foundation

extension Notification.Name {
    static let openTomorrowPlanner = Notification.Name("TomorrowPet.openTomorrowPlanner")
    static let openWeeklyPlanner = Notification.Name("TomorrowPet.openWeeklyPlanner")
    static let openDailySOP = Notification.Name("TomorrowPet.openDailySOP")
    static let showQuickAdd = Notification.Name("TomorrowPet.showQuickAdd")
    static let openFocus = Notification.Name("TomorrowPet.openFocus")
    static let openReview = Notification.Name("TomorrowPet.openReview")
    static let showCommandPalette = Notification.Name("TomorrowPet.showCommandPalette")
    static let sopRemindersChanged = Notification.Name("TomorrowPet.sopRemindersChanged")
}

enum AppConstants {
    static let name = "明日团子"
    static let executableName = "TomorrowPet"
    static let bundleIdentifier = "com.tomorrowpet.desktop"
    static let keychainService = "com.tomorrowpet.desktop.openai"
    static let openAIKeyAccount = "api-key"
    static let googleOAuthService = "com.tomorrowpet.desktop.google-oauth"
    static let googleClientSecretAccount = "client-secret"
    static let googleTokenAccount = "oauth-token"
    static let defaultModel = "gpt-5.6"
}
