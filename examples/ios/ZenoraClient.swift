// Reference source. Requires a host iOS app and macOS/Xcode validation before release.
import Foundation
import AuthenticationServices
import CryptoKit
import Security

private func base64url(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
struct PendingSignIn {
    let state: String
    let verifier: String
    let redirect = "https://account.zenora.dev/native/callback/ios"
    init() throws {
        func random() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 48)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw URLError(.unknown) }
            return base64url(Data(bytes))
        }
        state = try random(); verifier = try random()
    }
    var url: URL {
        var c = URLComponents(string: "https://account.zenora.dev/oauth/authorize")!
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        c.queryItems = ["response_type":"code", "client_id":"zenora-ios", "redirect_uri":redirect,
            "code_challenge_method":"S256", "code_challenge":challenge, "state":state,
            "scope":"studio.read studio.write community.read community.write"].map { URLQueryItem(name: $0.key, value: $0.value) }
        return c.url!
    }
    func code(from callback: URL) throws -> String {
        guard var c = URLComponents(url: callback, resolvingAgainstBaseURL: false), c.fragment == nil else { throw URLError(.badURL) }
        let items = c.queryItems ?? []; c.query = nil
        let states = items.filter { $0.name == "state" }.compactMap(\.value)
        let codes = items.filter { $0.name == "code" }.compactMap(\.value)
        guard c.string == redirect, states.count == 1, codes.count == 1,
              Data(states[0].utf8).count == Data(state.utf8).count else { throw URLError(.userAuthenticationRequired) }
        var difference: UInt8 = 0
        for (a, b) in zip(states[0].utf8, state.utf8) { difference |= a ^ b }
        guard difference == 0 else { throw URLError(.userAuthenticationRequired) }
        return codes[0]
    }
    // Host retains the session and supplies its presentationContextProvider before start().
    @available(iOS 17.4, *)
    @MainActor func browser(completion: @escaping (URL?, Error?) -> Void) -> ASWebAuthenticationSession {
        let session = ASWebAuthenticationSession(url: url, callback: .https(host: "account.zenora.dev", path: "/native/callback/ios"), completionHandler: completion)
        session.prefersEphemeralWebBrowserSession = false // Reuse the user's Access browser session.
        return session
    }
}

struct TokenPair: Codable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
    let scope: String
    let session_expires_at: String
}
enum Vault {
    static let query: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:"dev.zenora.native", kSecAttrAccount as String:"device-session"]
    static func save(_ pair: TokenPair) throws {
        let data = try JSONEncoder().encode(pair)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String:data] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw URLError(.cannotWriteToFile) }
        } else if update != errSecSuccess { throw URLError(.cannotWriteToFile) }
    }
    static func load() throws -> TokenPair? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw URLError(.cannotOpenFile) }
        return try JSONDecoder().decode(TokenPair.self, from: data)
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class ZenoraClient: @unchecked Sendable {
    let origin: URL
    let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
    init(origin: URL = URL(string:"https://api.zenora.dev")!) { self.origin = origin }
    func request(_ path: String, token: String, method: String = "GET", body: Data? = nil, key: String? = nil) throws -> URLRequest {
        guard path.hasPrefix("/v1/"), !path.contains("\\"), let url = URL(string:path, relativeTo:origin)?.absoluteURL,
              url.host == origin.host, url.scheme == origin.scheme, url.port == origin.port else { throw URLError(.badURL) }
        var r = URLRequest(url:url); r.httpMethod = method; r.httpBody = body; r.timeoutInterval = 30
        r.setValue("Bearer \(token)", forHTTPHeaderField:"Authorization")
        if body != nil { r.setValue("application/json", forHTTPHeaderField:"Content-Type") }
        if let key { r.setValue(key, forHTTPHeaderField:"Idempotency-Key") }; return r
    }
    func currentUser(token: String) async throws -> (Data, URLResponse) { try await session.data(for:request("/v1/me", token:token)) }
    func generate(savedBody: Data, savedKey: String, token: String) async throws -> (Data, URLResponse) {
        try await session.data(for:request("/v1/generations", token:token, method:"POST", body:savedBody, key:savedKey))
    }
    func image(path: String, token: String) async throws -> Data {
        let (data, response) = try await session.data(for:request(path, token:token))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }; return data
    }
}
actor SerializedRefresh {
    private var flight: Task<TokenPair, Error>?
    func refresh(exchange: @escaping @Sendable (String) async throws -> TokenPair) async throws -> TokenPair {
        if let flight { return try await flight.value }
        guard let saved = try Vault.load() else { throw URLError(.userAuthenticationRequired) }
        let task = Task { try await exchange(saved.refresh_token) }; flight = task
        do { let next = try await task.value; try Vault.save(next); flight = nil; return next }
        catch { flight = nil; Vault.clear(); throw error } // Unknown rotation outcome: reauthorize, never replay.
    }
}
