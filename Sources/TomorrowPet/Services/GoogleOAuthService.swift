import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct GoogleOAuthService {
    static let calendarReadOnlyScope = "https://www.googleapis.com/auth/calendar.readonly"

    static func desktopCredentials(from data: Data) throws -> GoogleOAuthClientCredentials {
        struct Client: Decodable {
            var clientID: String
            var clientSecret: String
            var projectID: String?

            enum CodingKeys: String, CodingKey {
                case clientID = "client_id"
                case clientSecret = "client_secret"
                case projectID = "project_id"
            }
        }
        struct CredentialFile: Decodable {
            var installed: Client?
            var web: Client?
        }

        let file: CredentialFile
        do {
            file = try JSONDecoder().decode(CredentialFile.self, from: data)
        } catch {
            throw GoogleCalendarError.invalidCredentialFile
        }
        guard let installed = file.installed else {
            if file.web != nil { throw GoogleCalendarError.webCredentialFile }
            throw GoogleCalendarError.invalidCredentialFile
        }
        let clientID = installed.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let clientSecret = installed.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw GoogleCalendarError.missingClientID }
        guard !clientSecret.isEmpty else { throw GoogleCalendarError.missingClientSecret }
        guard clientID.hasSuffix(".apps.googleusercontent.com") else {
            throw GoogleCalendarError.invalidCredentialFile
        }
        return GoogleOAuthClientCredentials(
            clientID: clientID,
            clientSecret: clientSecret,
            projectID: installed.projectID
        )
    }

    func authorize(clientID: String, clientSecret: String) async throws -> GoogleOAuthToken {
        let cleanID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanID.isEmpty else { throw GoogleCalendarError.missingClientID }
        guard !cleanSecret.isEmpty else { throw GoogleCalendarError.missingClientSecret }

        let server = try LoopbackOAuthServer()
        let redirectURI = try await server.start()
        let verifier = try Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.pkceChallenge(for: verifier)
        let state = try Self.randomURLSafeString(byteCount: 32)

        guard let authorizationURL = Self.authorizationURL(
            clientID: cleanID,
            redirectURI: redirectURI,
            state: state,
            challenge: challenge
        ) else {
            throw GoogleCalendarError.invalidAuthorizationURL
        }

        let didOpenBrowser = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }
        guard didOpenBrowser else { throw GoogleCalendarError.browserOpenFailed }

        let callbackURL = try await server.waitForCallback()
        let callback = try Self.parseCallback(callbackURL)
        guard callback.state == state else { throw GoogleCalendarError.stateMismatch }
        if let error = callback.error { throw GoogleCalendarError.authorizationDenied(error) }
        guard let code = callback.code else { throw GoogleCalendarError.missingAuthorizationCode }

        return try await exchangeCode(
            code,
            clientID: cleanID,
            clientSecret: cleanSecret,
            redirectURI: redirectURI,
            verifier: verifier
        )
    }

    func refreshedToken(
        _ token: GoogleOAuthToken,
        clientID: String,
        clientSecret: String
    ) async throws -> GoogleOAuthToken {
        guard !token.refreshToken.isEmpty else { throw GoogleCalendarError.missingRefreshToken }
        let fields: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "refresh_token": token.refreshToken,
            "grant_type": "refresh_token"
        ]
        let response: GoogleTokenResponse = try await tokenRequest(fields)
        return GoogleOAuthToken(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(60, response.expiresIn - 30))),
            scope: response.scope ?? token.scope,
            tokenType: response.tokenType
        )
    }

    func revoke(_ token: GoogleOAuthToken) async {
        guard var components = URLComponents(string: "https://oauth2.googleapis.com/revoke") else { return }
        components.queryItems = [URLQueryItem(name: "token", value: token.refreshToken)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func exchangeCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        redirectURI: URL,
        verifier: String
    ) async throws -> GoogleOAuthToken {
        let fields: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": redirectURI.absoluteString,
            "grant_type": "authorization_code"
        ]
        let response: GoogleTokenResponse = try await tokenRequest(fields)
        let scope = response.scope ?? ""
        guard scope.split(separator: " ").contains(Substring(Self.calendarReadOnlyScope)) else {
            throw GoogleCalendarError.calendarScopeNotGranted
        }
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw GoogleCalendarError.missingRefreshToken
        }
        return GoogleOAuthToken(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(max(60, response.expiresIn - 30))),
            scope: scope,
            tokenType: response.tokenType
        )
    }

    private func tokenRequest<T: Decodable>(_ fields: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60
        request.httpBody = Self.formEncoded(fields).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GoogleCalendarError.api(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw GoogleCalendarError.decoding(error.localizedDescription)
        }
    }

    static func authorizationURL(
        clientID: String,
        redirectURI: URL,
        state: String,
        challenge: String
    ) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: calendarReadOnlyScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }

    static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    static func parseCallback(_ url: URL) throws -> (code: String?, state: String?, error: String?) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleCalendarError.invalidCallback
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] where values[item.name] == nil {
            values[item.name] = item.value ?? ""
        }
        return (values["code"], values["state"], values["error"])
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) == errSecSuccess else {
            throw GoogleCalendarError.randomGenerationFailed
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func formEncoded(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }
            .map { "\(formEscape($0.key))=\(formEscape($0.value))" }
            .joined(separator: "&")
    }

    private static func formEscape(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Google 返回了无法读取的错误。"
        }
        return object["error_description"] as? String
            ?? object["message"] as? String
            ?? object["error"] as? String
            ?? "Google API 请求失败。"
    }
}

final class LoopbackOAuthServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.tomorrowpet.google-oauth-loopback")
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingResult: Result<URL, Error>?
    private var readyContinuation: CheckedContinuation<URL, Error>?
    private var didFinish = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                readyContinuation = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    self.queue.async {
                        switch state {
                        case .ready:
                            guard let port = self.listener.port else {
                                self.fail(GoogleCalendarError.loopbackServerFailed("没有可用端口"))
                                return
                            }
                            self.readyContinuation?.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/oauth2callback")!)
                            self.readyContinuation = nil
                        case .failed(let error):
                            self.fail(GoogleCalendarError.loopbackServerFailed(error.localizedDescription))
                        case .cancelled:
                            if !self.didFinish { self.fail(GoogleCalendarError.authorizationCancelled) }
                        default:
                            break
                        }
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }
                listener.start(queue: queue)
                queue.asyncAfter(deadline: .now() + 300) { [weak self] in
                    self?.fail(GoogleCalendarError.authorizationTimedOut)
                }
            }
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                if let pendingResult {
                    self.pendingResult = nil
                    continuation.resume(with: pendingResult)
                } else {
                    callbackContinuation = continuation
                }
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.finish(.failure(GoogleCalendarError.loopbackServerFailed(error.localizedDescription)))
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first else {
                self.finish(.failure(GoogleCalendarError.invalidCallback))
                return
            }
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2,
                  let callbackURL = URL(string: "http://127.0.0.1\(parts[1])") else {
                self.finish(.failure(GoogleCalendarError.invalidCallback))
                return
            }

            let html = """
            <!doctype html><html lang="zh-CN"><meta charset="utf-8">
            <title>返回明日团子</title>
            <body style="font:16px -apple-system;padding:48px;max-width:560px;margin:auto">
            <h1>授权结果已返回明日团子</h1><p>请回到应用查看连接状态；你现在可以关闭这个页面。</p></body></html>
            """
            let body = Data(html.utf8)
            let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in
                connection.cancel()
            })
            self.finish(.success(callbackURL))
        }
    }

    private func fail(_ error: Error) {
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        finish(.failure(error))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !didFinish else { return }
        didFinish = true
        listener.cancel()
        if let callbackContinuation {
            self.callbackContinuation = nil
            callbackContinuation.resume(with: result)
        } else {
            pendingResult = result
        }
    }
}

enum GoogleCalendarError: LocalizedError, Equatable {
    case missingClientID
    case missingClientSecret
    case invalidCredentialFile
    case webCredentialFile
    case invalidAuthorizationURL
    case browserOpenFailed
    case randomGenerationFailed
    case loopbackServerFailed(String)
    case authorizationCancelled
    case authorizationTimedOut
    case authorizationDenied(String)
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case calendarScopeNotGranted
    case missingRefreshToken
    case disconnected
    case invalidResponse
    case api(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID: "请先填写 Google OAuth Client ID。"
        case .missingClientSecret: "请先填写 Google OAuth Client Secret。"
        case .invalidCredentialFile: "这个 JSON 不是有效的 Google Desktop OAuth 凭据文件。请从 Google Cloud 下载桌面应用客户端 JSON。"
        case .webCredentialFile: "检测到 Web application OAuth 凭据；明日团子需要 Desktop app（桌面应用）类型的 JSON。"
        case .invalidAuthorizationURL: "无法创建 Google 授权地址。"
        case .browserOpenFailed: "无法打开默认浏览器进行 Google 授权。"
        case .randomGenerationFailed: "无法生成安全的 OAuth 随机值。"
        case .loopbackServerFailed(let message): "无法启动本机 OAuth 回调：\(message)"
        case .authorizationCancelled: "Google 授权已取消。"
        case .authorizationTimedOut: "Google 授权等待超过 5 分钟，请重试。"
        case .authorizationDenied(let message): "Google 未授权访问：\(message)"
        case .invalidCallback: "Google OAuth 回调格式无效。"
        case .stateMismatch: "Google OAuth 安全状态不匹配，已拒绝本次授权。"
        case .missingAuthorizationCode: "Google 没有返回授权码。"
        case .calendarScopeNotGranted: "没有获得 Google Calendar 只读权限。"
        case .missingRefreshToken: "Google 没有返回刷新令牌，请重新授权。"
        case .disconnected: "Google Calendar 尚未连接。"
        case .invalidResponse: "Google 返回了无法识别的响应。"
        case .api(let status, let message): "Google API 请求失败（HTTP \(status)）：\(message)"
        case .decoding(let message): "Google Calendar 数据解析失败：\(message)"
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
