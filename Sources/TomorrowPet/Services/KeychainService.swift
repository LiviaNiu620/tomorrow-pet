import Foundation
import Security

enum KeychainService {
    static func readAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainService,
            kSecAttrAccount as String: AppConstants.openAIKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    static func saveAPIKey(_ value: String) throws {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainService,
            kSecAttrAccount as String: AppConstants.openAIKeyAccount
        ]

        if cleanValue.isEmpty {
            SecItemDelete(baseQuery as CFDictionary)
            return
        }

        let data = Data(cleanValue.utf8)
        let status = SecItemCopyMatching(baseQuery as CFDictionary, nil)
        if status == errSecSuccess {
            let attributes = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
        } else {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        }
    }

    static func readGoogleClientSecret() -> String {
        readString(service: AppConstants.googleOAuthService, account: AppConstants.googleClientSecretAccount)
    }

    static func saveGoogleClientSecret(_ value: String) throws {
        try saveString(value, service: AppConstants.googleOAuthService, account: AppConstants.googleClientSecretAccount)
    }

    static func readGoogleToken() -> GoogleOAuthToken? {
        let value = readString(service: AppConstants.googleOAuthService, account: AppConstants.googleTokenAccount)
        guard let data = value.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GoogleOAuthToken.self, from: data)
    }

    static func saveGoogleToken(_ token: GoogleOAuthToken?) throws {
        guard let token else {
            try saveString("", service: AppConstants.googleOAuthService, account: AppConstants.googleTokenAccount)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(token)
        guard let value = String(data: data, encoding: .utf8) else { throw KeychainError.encoding }
        try saveString(value, service: AppConstants.googleOAuthService, account: AppConstants.googleTokenAccount)
    }

    private static func readString(service: String, account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    private static func saveString(_ value: String, service: String, account: String) throws {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if cleanValue.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(cleanValue.utf8)
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        }
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)
    case encoding

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 错误 \(status)"
        case .encoding:
            return "无法编码要保存到 Keychain 的数据。"
        }
    }
}
