import Foundation
import Combine
import CryptoKit
import Network
import Security

/// OpenAI's documented open-source Sign in with ChatGPT flow.
/// OAuth credentials are stored in the iOS Keychain, never in UserDefaults.
@MainActor
final class ChatGPTSignInManager: ObservableObject {
    @Published private(set) var email: String?
    @Published private(set) var displayName: String?
    @Published private(set) var hasIdentity = false
    @Published private(set) var canUseChatGPTPlan = false
    @Published private(set) var isSigningIn = false

    var onAuthenticated: ((String?) -> Void)?
    var onBrowserCompleted: (() -> Void)?

    private let authorizationEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    private let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    private let resource = "https://api.openai.com/v1"
    private let keychainKey = "com.sinchix33.gptplus.siwc.credentials"
    private let hostIDKey = "com.sinchix33.gptplus.siwc.host-id"

    private var listener: NWListener?
    private var activePort: UInt16?
    private var pending: PendingAuthorization?
    private var credentials: Credentials?

    private struct PendingAuthorization {
        let state: String
        let nonce: String
        let verifier: String
        let redirectURI: String
        let clientIDUsed: String
        let isNewRegistration: Bool
    }

    private struct Credentials: Codable {
        var clientID: String
        var hostID: String
        var subject: String
        var email: String?
        var name: String?
        var idToken: String
        var accessToken: String
        var refreshToken: String?
        var scopes: [String]
        var expiresAt: Date
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let id_token: String?
        let token_type: String?
        let expires_in: Double
        let scope: String?
    }

    init() {
        if let saved = Self.readKeychain(key: keychainKey),
           let decoded = try? JSONDecoder().decode(Credentials.self, from: saved) {
            credentials = decoded
            email = decoded.email
            displayName = decoded.name
            hasIdentity = true
            canUseChatGPTPlan = decoded.scopes.contains("chatgpt.tokens.use.direct")
        }
    }

    func prepareAuthorization() async throws -> URL {
        guard !isSigningIn else { throw SignInError.alreadyInProgress }
        isSigningIn = true
        defer { if pending == nil { isSigningIn = false } }

        let hostID = stableHostID()
        let state = Self.randomURLSafeString(byteCount: 32)
        let nonce = Self.randomURLSafeString(byteCount: 32)
        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let isNew = credentials == nil
        let clientID = credentials?.clientID ?? "dynamic_agent_client"

        let listenerParameters = NWParameters.tcp
        listenerParameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: .any
        )
        let newListener = try NWListener(using: listenerParameters, on: .any)
        listener = newListener

        let redirectURI: String = try await withCheckedThrowingContinuation { continuation in
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = newListener.port?.rawValue else {
                        continuation.resume(throwing: SignInError.callbackListenerFailed)
                        return
                    }
                    Task { @MainActor in
                        self?.activePort = port
                        continuation.resume(returning: "http://127.0.0.1:\(port)/auth/callback")
                    }
                case .failed:
                    continuation.resume(throwing: SignInError.callbackListenerFailed)
                default:
                    break
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    let request = String(decoding: data ?? Data(), as: UTF8.self)
                    let requestLine = request.components(separatedBy: "\r\n").first ?? ""
                    let pieces = requestLine.split(separator: " ")
                    let target = pieces.count > 1 ? String(pieces[1]) : "/"
                    let html = "<html><body><h3>GPT Plus</h3><p>Sign-in received. You can return to GPT Plus.</p></body></html>"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    Task { @MainActor in
                        await self?.receiveCallbackTarget(target)
                    }
                }
            }
            newListener.start(queue: .main)
        }

        pending = PendingAuthorization(
            state: state,
            nonce: nonce,
            verifier: verifier,
            redirectURI: redirectURI,
            clientIDUsed: clientID,
            isNewRegistration: isNew
        )

        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var query = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]
        if isNew {
            query.append(URLQueryItem(name: "agent_name_hint", value: "GPT Plus"))
        } else if let savedIDToken = credentials?.idToken {
            query.append(URLQueryItem(name: "id_token_hint", value: savedIDToken))
            if let email { query.append(URLQueryItem(name: "login_hint", value: email)) }
        }
        components.queryItems = query
        guard let url = components.url else { throw SignInError.invalidAuthorizationURL }
        return url
    }

    private func receiveCallbackTarget(_ target: String) async {
        // Ignore incidental browser requests such as favicon probes.
        guard target == "/auth/callback" || target.hasPrefix("/auth/callback?") else { return }
        guard let pending, let activePort else { return }
        guard let components = URLComponents(string: "http://127.0.0.1:\(activePort)\(target)") else {
            failCallback(SignInError.invalidCallback)
            return
        }
        guard components.host == "127.0.0.1",
              components.path == "/auth/callback",
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == pending.state else {
            failCallback(SignInError.stateMismatch)
            return
        }

        if let oauthError = components.queryItems?.first(where: { $0.name == "error" })?.value {
            failCallback(SignInError.authorizationDenied(oauthError))
            return
        }
        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            failCallback(SignInError.missingAuthorizationCode)
            return
        }

        let callbackClientID = components.queryItems?.first(where: { $0.name == "client_id" })?.value
        let issuedClientID: String
        if pending.isNewRegistration {
            guard let callbackClientID, callbackClientID.hasPrefix("oaiapp_") else {
                failCallback(SignInError.missingIssuedClientID)
                return
            }
            issuedClientID = callbackClientID
        } else {
            if let callbackClientID, callbackClientID != pending.clientIDUsed {
                failCallback(SignInError.clientIDMismatch)
                return
            }
            issuedClientID = pending.clientIDUsed
        }

        do {
            var body = [
                "grant_type": "authorization_code",
                "client_id": issuedClientID,
                "code": code,
                "code_verifier": pending.verifier,
                "redirect_uri": pending.redirectURI,
                "resource": resource
            ]
            let tokenResponse: TokenResponse = try await postForm(tokenEndpoint, values: body)
            body.removeAll()
            guard let idToken = tokenResponse.id_token else { throw SignInError.missingIDToken }
            let identity = try await verifyIDToken(idToken, audience: issuedClientID, nonce: pending.nonce)
            let scopes = (tokenResponse.scope ?? "").split(separator: " ").map(String.init)
            let saved = Credentials(
                clientID: issuedClientID,
                hostID: stableHostID(),
                subject: identity.subject,
                email: identity.email,
                name: identity.name,
                idToken: idToken,
                accessToken: tokenResponse.access_token,
                refreshToken: tokenResponse.refresh_token,
                scopes: scopes,
                expiresAt: Date().addingTimeInterval(tokenResponse.expires_in)
            )
            try save(saved)
            self.credentials = saved
            self.email = saved.email
            self.displayName = saved.name
            self.hasIdentity = true
            self.canUseChatGPTPlan = scopes.contains("chatgpt.tokens.use.direct")
            self.pending = nil
            self.listener?.cancel()
            self.listener = nil
            self.activePort = nil
            self.isSigningIn = false
            onBrowserCompleted?()
            onAuthenticated?(saved.email)
        } catch {
            failCallback(error)
        }
    }

    func validAccessToken() async throws -> String {
        guard var saved = credentials else { throw SignInError.notConnected }
        if saved.expiresAt.timeIntervalSinceNow > 90 { return saved.accessToken }
        guard let refreshToken = saved.refreshToken else { throw SignInError.reauthenticationRequired }
        let response: TokenResponse = try await postForm(tokenEndpoint, values: [
            "grant_type": "refresh_token",
            "client_id": saved.clientID,
            "refresh_token": refreshToken,
            "resource": resource
        ])
        saved.accessToken = response.access_token
        if let rotated = response.refresh_token { saved.refreshToken = rotated }
        saved.expiresAt = Date().addingTimeInterval(response.expires_in)
        if let scope = response.scope {
            saved.scopes = scope.split(separator: " ").map(String.init)
        }
        try save(saved)
        credentials = saved
        canUseChatGPTPlan = saved.scopes.contains("chatgpt.tokens.use.direct")
        return saved.accessToken
    }

    func cancelSignIn() {
        guard pending != nil else { return }
        pending = nil
        listener?.cancel()
        listener = nil
        activePort = nil
        isSigningIn = false
    }

    func signOut() {
        let old = credentials
        credentials = nil
        email = nil
        displayName = nil
        hasIdentity = false
        canUseChatGPTPlan = false
        Self.deleteKeychain(key: keychainKey)
        if let old, let refreshToken = old.refreshToken {
            Task { await revoke(refreshToken: refreshToken, clientID: old.clientID) }
        }
    }

    private struct OpenIDConfiguration: Decodable {
        let revocation_endpoint: String?
    }

    private func revoke(refreshToken: String, clientID: String) async {
        do {
            let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
            let (discoveryData, _) = try await URLSession.shared.data(from: discoveryURL)
            let configuration = try JSONDecoder().decode(OpenIDConfiguration.self, from: discoveryData)
            guard let endpoint = configuration.revocation_endpoint, let url = URL(string: endpoint) else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var form = URLComponents()
            form.queryItems = [
                URLQueryItem(name: "token", value: refreshToken),
                URLQueryItem(name: "token_type_hint", value: "refresh_token"),
                URLQueryItem(name: "client_id", value: clientID)
            ]
            request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            // Local sign-out remains complete. Users can also disconnect GPT Plus in ChatGPT settings.
        }
    }

    private func failCallback(_ error: Error) {
        onBrowserCompleted?()
        pending = nil
        listener?.cancel()
        listener = nil
        activePort = nil
        isSigningIn = false
        NotificationCenter.default.post(name: .chatGPTSignInFailed, object: error.localizedDescription)
    }

    private func stableHostID() -> String {
        if let existing = UserDefaults.standard.string(forKey: hostIDKey) { return existing }
        let generated = "urn:uuid:\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(generated, forKey: hostIDKey)
        return generated
    }

    private func postForm<T: Decodable>(_ url: URL, values: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var parts = URLComponents()
        parts.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = parts.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SignInError.tokenRequestFailed
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func verifyIDToken(_ token: String, audience: String, nonce: String) async throws -> (subject: String, email: String?, name: String?) {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let headerData = Self.decodeBase64URL(parts[0]),
              let claimsData = Self.decodeBase64URL(parts[1]),
              let signatureData = Self.decodeBase64URL(parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "ES256",
              let kid = header["kid"] as? String,
              let claims = try JSONSerialization.jsonObject(with: claimsData) as? [String: Any] else {
            throw SignInError.invalidIDToken
        }

        let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
        let (jwksData, _) = try await URLSession.shared.data(from: jwksURL)
        guard let jwks = try JSONSerialization.jsonObject(with: jwksData) as? [String: Any],
              let keys = jwks["keys"] as? [[String: Any]],
              let jwk = keys.first(where: { $0["kid"] as? String == kid }),
              jwk["kty"] as? String == "EC",
              jwk["crv"] as? String == "P-256",
              let xString = jwk["x"] as? String,
              let yString = jwk["y"] as? String,
              let x = Self.decodeBase64URL(xString),
              let y = Self.decodeBase64URL(yString) else {
            throw SignInError.invalidSigningKey
        }

        var publicKeyData = Data([0x04])
        publicKeyData.append(x)
        publicKeyData.append(y)
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        let signingInput = Data("\(parts[0]).\(parts[1])".utf8)
        guard publicKey.isValidSignature(signature, for: signingInput) else { throw SignInError.invalidIDToken }

        let audienceMatches = (claims["aud"] as? String == audience) ||
            ((claims["aud"] as? [String])?.contains(audience) == true)
        guard claims["iss"] as? String == "https://auth.openai.com",
              audienceMatches,
              let subject = claims["sub"] as? String,
              claims["nonce"] as? String == nonce,
              let expiry = claims["exp"] as? TimeInterval,
              expiry > Date().timeIntervalSince1970 else {
            throw SignInError.invalidIDToken
        }
        return (subject, claims["email"] as? String, claims["name"] as? String)
    }

    private func save(_ value: Credentials) throws {
        let data = try JSONEncoder().encode(value)
        Self.deleteKeychain(key: keychainKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw SignInError.secureStorageFailed
        }
    }

    private static func readKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func deleteKeychain(key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ] as CFDictionary)
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL<D: DataProtocol>(_ data: D) -> String {
        Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }

    enum SignInError: LocalizedError {
        case alreadyInProgress, callbackListenerFailed, invalidAuthorizationURL, invalidCallback
        case stateMismatch, missingAuthorizationCode, missingIssuedClientID, clientIDMismatch
        case authorizationDenied(String), tokenRequestFailed, missingIDToken, invalidIDToken
        case invalidSigningKey, secureStorageFailed, notConnected, reauthenticationRequired

        var errorDescription: String? {
            switch self {
            case .alreadyInProgress: return "ChatGPT sign-in is already in progress."
            case .callbackListenerFailed: return "Could not start the secure sign-in callback. Please try again."
            case .invalidAuthorizationURL, .invalidCallback: return "The ChatGPT sign-in response was invalid."
            case .stateMismatch: return "The ChatGPT sign-in could not be verified. Please try again."
            case .missingAuthorizationCode: return "OpenAI did not return an authorization code."
            case .missingIssuedClientID: return "OpenAI did not complete the app registration."
            case .clientIDMismatch: return "The returned ChatGPT client did not match this sign-in attempt."
            case .authorizationDenied(let reason): return "ChatGPT authorization was not completed: \(reason)."
            case .tokenRequestFailed: return "OpenAI could not exchange the sign-in code. Please try again."
            case .missingIDToken, .invalidIDToken, .invalidSigningKey: return "OpenAI identity verification failed. No account was connected."
            case .secureStorageFailed: return "The secure iPhone Keychain could not save the ChatGPT connection."
            case .notConnected: return "No ChatGPT account is connected."
            case .reauthenticationRequired: return "Your ChatGPT session expired. Please sign in again."
            }
        }
    }
}

extension Notification.Name {
    static let chatGPTSignInFailed = Notification.Name("chatGPTSignInFailed")
}
