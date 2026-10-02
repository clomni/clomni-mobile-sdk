import Foundation
#if canImport(ClomniProtocol)
import ClomniProtocol
#endif

package enum ClomniError: Error, Equatable, Sendable {
    /// The server refused the request; `error` is its `Error` body when it sent one.
    case server(status: Int, error: ServerError?)
    /// No answer: offline, timeout, TLS.
    case network(String)
    /// A success whose body could not be read.
    case unreadableResponse
    /// No session yet: log the user in first.
    case notLoggedIn
    /// Refused before sending: an empty text, a button already answered, a message not in the outbox.
    case rejected(String)

    /// The server's error code, e.g. `already_answered`.
    package var code: String? {
        if case .server(_, let error) = self { return error?.code }
        return nil
    }
}

/// Who the session is for. Kept with the session, so an expired refresh token can be replaced by a new login.
package struct UserIdentity: Sendable, Equatable, Codable {
    package var userId: String?
    package var email: String?
    package var phone: String?
    package var name: String?

    package init(userId: String? = nil, email: String? = nil, phone: String? = nil, name: String? = nil) {
        self.userId = userId
        self.email = email
        self.phone = phone
        self.name = name
    }
}

enum SessionIdentity: Sendable, Equatable, Codable {
    case anonymous
    case user(UserIdentity, hash: String?)

    /// The same person: anonymous both times, or the same user_id (else email) with the same hash. A new name or
    /// phone is not a new person; `updateUser` carries those.
    func isSamePerson(as other: SessionIdentity) -> Bool {
        switch (self, other) {
        case (.anonymous, .anonymous):
            return true
        case let (.user(mine, myHash), .user(theirs, theirHash)):
            return mine.key != nil && mine.key == theirs.key && myHash == theirHash
        default:
            return false
        }
    }
}

extension UserIdentity {
    /// What the server knows the user by: user_id, else the email (lower case, trimmed).
    var key: String? {
        userId ?? email.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    }
}

struct ApiConfiguration: Sendable {
    static let defaultBaseURL = URL(string: "https://app.clomni.ai/v1")!

    var appId: String
    var apiKey: String
    var baseURL = defaultBaseURL
}

enum ConfigResult: Equatable {
    case notModified
    case changed(MessengerConfig, body: Data, etag: String?)
}

/// The Mobile API (protocol/openapi.yaml). Session endpoints authenticate with the app's public keys, the rest with
/// the session token. A `401` renews the session once and repeats the request; `429` waits `Retry-After`; a `5xx`
/// is retried with 1, 2, 4 s waits. Anything else is thrown as `ClomniError`.
actor ApiClient {
    enum Auth { case app, session }

    private enum Key {
        static let session = "session"
        static let identity = "identity"
        static let anonymousId = "anonymous_id"
        static let deviceId = "device_id"
    }

    static let maxRetries = 3

    let configuration: ApiConfiguration
    private let transport: HTTPTransport
    private let vault: SecureStore
    private let time: TimeSource
    // From the keychain on first use, on the actor (see ClomniEngine).
    private(set) lazy var session: MobileSession? = vault.value(MobileSession.self, for: Key.session)
    private(set) lazy var identity: SessionIdentity? = vault.value(SessionIdentity.self, for: Key.identity)
    private var renewal: Task<Void, Error>?

    init(configuration: ApiConfiguration, transport: HTTPTransport, vault: SecureStore, time: TimeSource) {
        self.configuration = configuration
        self.transport = transport
        self.vault = vault
        self.time = time
    }

    // MARK: - Session

    /// Opens a session and keeps it, with the identity, for the next launch. An anonymous user is resumed by its id
    /// on this device; logging in afterwards merges it into the identified user.
    @discardableResult
    func open(_ identity: SessionIdentity) async throws -> MobileSession {
        var body: [String: JSONValue] = ["device": DeviceInfo.current(deviceId: deviceId()).json]
        if let anonymousId = vault.value(String.self, for: Key.anonymousId) {
            body["anonymous_id"] = .string(anonymousId)
        }
        if case .user(let user, let hash) = identity {
            body["user"] = user.json(hash: hash)
        }
        let response = try await request("POST", "/mobile/sessions", json: .object(body), auth: .app)
        let session = try read(response, ProtocolJSON.parseSession)
        keep(session)
        self.identity = identity
        vault.setValue(identity, for: Key.identity)
        vault.setValue(session.anonymous ? session.userId : nil, for: Key.anonymousId)
        return session
    }

    /// Ends the session on the server (best effort) and forgets it here; the device id stays.
    func logout() async {
        if session != nil {
            _ = try? await request("DELETE", "/mobile/sessions", renew: false)
        }
        session = nil
        identity = nil
        for key in [Key.session, Key.identity, Key.anonymousId] {
            vault.write(nil, for: key)
        }
    }

    /// The kept session when it belongs to `identity` (renewed if it is about to expire, opened again if the refresh
    /// token is refused); a new one only for another person. An app launch does not cost a login.
    func session(for identity: SessionIdentity) async throws -> MobileSession {
        if session != nil, let kept = self.identity, kept.isSamePerson(as: identity) {
            self.identity = identity
            vault.setValue(identity, for: Key.identity)
            return try await validSession()
        }
        return try await open(identity)
    }

    /// A session that is not about to expire, renewed first if it is.
    func validSession() async throws -> MobileSession {
        if let session, session.expiresAt.timeIntervalSince(time.now()) > 60 { return session }
        try await renew(after: session?.sessionToken)
        guard let session else { throw ClomniError.notLoggedIn }
        return session
    }

    /// One renewal at a time: the refresh token is single-use, so concurrent 401s share it.
    private func renew(after usedToken: String?) async throws {
        if let session, session.sessionToken != usedToken, session.expiresAt.timeIntervalSince(time.now()) > 60 {
            return
        }
        if let renewal {
            return try await renewal.value
        }
        let task = Task { try await self.performRenewal() }
        renewal = task
        defer { renewal = nil }
        try await task.value
    }

    private func performRenewal() async throws {
        if let session {
            do {
                let response = try await request("POST", "/mobile/sessions/refresh",
                                                  json: ["refresh_token": .string(session.refreshToken)], auth: .app)
                keep(try read(response, ProtocolJSON.parseSession))
                return
            } catch ClomniError.server(let status, _) where status == 401 {
                ClomniLog.info("refresh token refused; logging in again")
            }
        }
        guard let identity else { throw ClomniError.notLoggedIn }
        try await open(identity)
    }

    /// The socket address with a fresh token.
    func socketURL() async throws -> URL {
        let session = try await validSession()
        guard var components = URLComponents(url: session.wsUrl, resolvingAgainstBaseURL: false) else {
            throw ClomniError.unreadableResponse
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "token", value: session.sessionToken),
                                                                   URLQueryItem(name: "protocol", value: "v1")]
        guard let url = components.url else { throw ClomniError.unreadableResponse }
        return url
    }

    private func keep(_ session: MobileSession) {
        self.session = session
        vault.setValue(session, for: Key.session)
    }

    private func deviceId() -> String {
        if let id = vault.value(String.self, for: Key.deviceId) { return id }
        let id = "d_" + UUID().uuidString.lowercased()
        vault.setValue(id, for: Key.deviceId)
        return id
    }

    // MARK: - Endpoints

    func config(language: String?, etag: String?) async throws -> ConfigResult {
        let response = try await request("GET", "/mobile/config", query: ["lang": language],
                                         headers: etag.map { ["If-None-Match": $0] } ?? [:])
        if response.status == 304 { return .notModified }
        return .changed(try read(response, ProtocolJSON.parseConfig), body: response.body, etag: response.header("ETag"))
    }

    func conversations(cursor: String? = nil, limit: Int = 20) async throws -> ConversationPage {
        try read(try await request("GET", "/conversations", query: ["cursor": cursor, "limit": String(limit)]),
                 ProtocolJSON.parseConversationPage)
    }

    /// With a `clientId` the server starts one conversation for it however often it is asked (201, then 200 with
    /// the same conversation): a retry after a lost answer makes no second one.
    func createConversation(openedFrom: String?, clientId: String? = nil) async throws -> ConversationWithMessages {
        var fields: [String: JSONValue] = [:]
        if let openedFrom { fields["opened_from"] = .string(openedFrom) }
        if let clientId { fields["client_id"] = .string(clientId) }
        let body = JSONValue.object(fields)
        return try read(try await request("POST", "/conversations", json: body), ProtocolJSON.parseConversationWithMessages)
    }

    func conversation(_ id: String) async throws -> Conversation {
        try read(try await request("GET", "/conversations/\(escape(id))"), ProtocolJSON.parseConversation)
    }

    func messages(in id: String, beforeSeq: Int? = nil, afterSeq: Int? = nil, limit: Int = 50) async throws -> MessagePage {
        let query = ["before_seq": beforeSeq.map(String.init), "after_seq": afterSeq.map(String.init), "limit": String(limit)]
        return try read(try await request("GET", "/conversations/\(escape(id))/messages", query: query),
                        ProtocolJSON.parseMessagePage)
    }

    /// The created message: for a button reply its text is the button's title. A repeated client id answers with the
    /// message created the first time.
    func send(_ message: ClientMessage, to id: String) async throws -> Message {
        let response = try await request("POST", "/conversations/\(escape(id))/messages",
                                         body: ProtocolJSON.encode(message), contentType: "application/json")
        return try read(response, ProtocolJSON.parseMessage)
    }

    func markRead(_ id: String, upToSeq: Int) async throws {
        _ = try await request("POST", "/conversations/\(escape(id))/read", json: ["up_to_seq": .number(Double(upToSeq))])
    }

    func setTyping(_ id: String, on: Bool) async throws {
        _ = try await request("POST", "/conversations/\(escape(id))/typing", json: ["state": .string(on ? "on" : "off")])
    }

    func upload(_ data: Data, fileName: String, mime: String) async throws -> UploadedFile {
        let boundary = "clomni-\(UUID().uuidString)"
        let name = fileName.replacingOccurrences(of: "\"", with: "_")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".utf8)
        body.append(Data("Content-Type: \(mime)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let response = try await request("POST", "/uploads", body: body,
                                         contentType: "multipart/form-data; boundary=\(boundary)")
        return try read(response, ProtocolJSON.parseUpload)
    }

    func user() async throws -> MobileUser {
        try read(try await request("GET", "/users/me"), ProtocolJSON.parseUser)
    }

    /// Only the fields given change; `custom_attributes` are merged on the server.
    func updateUser(_ fields: [String: JSONValue]) async throws -> MobileUser {
        try read(try await request("PATCH", "/users/me", json: .object(fields)), ProtocolJSON.parseUser)
    }

    func registerDevice(token: String, sandbox: Bool) async throws {
        _ = try await request("POST", "/devices", json: ["token": .string(token), "provider": "apns",
                                                         "environment": .string(sandbox ? "sandbox" : "production")])
    }

    /// `openedFrom` (additive, like POST /conversations): where in the app the flow was started.
    func triggerFlow(event: String, data: [String: JSONValue], openMessenger: Bool,
                     openedFrom: String? = nil) async throws -> FlowTriggerResult {
        var body: [String: JSONValue] = ["event": .string(event), "data": .object(data),
                                         "open_messenger": .bool(openMessenger)]
        body["opened_from"] = openedFrom.map(JSONValue.string)
        return try read(try await request("POST", "/flows/trigger", json: .object(body)), ProtocolJSON.parseFlowTrigger)
    }

    func track(event: String, data: [String: JSONValue]) async throws {
        _ = try await request("POST", "/events", json: ["event": .string(event), "data": .object(data)])
    }

    // MARK: - Requests

    private func request(_ method: String, _ path: String, query: [String: String?] = [:], json: JSONValue,
                         auth: Auth = .session) async throws -> HTTPResponse {
        try await request(method, path, query: query, body: ProtocolJSON.encode(json), contentType: "application/json",
                          auth: auth)
    }

    func request(_ method: String, _ path: String, query: [String: String?] = [:], headers: [String: String] = [:],
                 body: Data? = nil, contentType: String? = nil, auth: Auth = .session,
                 renew: Bool = true) async throws -> HTTPResponse {
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath += path
        let items = query.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
        components?.queryItems = items.isEmpty ? nil : items.sorted { $0.name < $1.name }
        guard let url = components?.url else { throw ClomniError.rejected("invalid url \(path)") }

        var retries = 0
        var renewed = !renew
        while true {
            var request = HTTPRequest(method: method, url: url, headers: headers, body: body)
            request.headers["X-Clomni-SDK"] = "ios/\(SDKInfo.version)"
            request.headers["Accept"] = "application/json"
            if body != nil { request.headers["Content-Type"] = contentType }
            var token: String?
            switch auth {
            case .app:
                request.headers["X-Clomni-App-Id"] = configuration.appId
                request.headers["X-Clomni-Api-Key"] = configuration.apiKey
            case .session:
                // Logging out must not log in again just to say goodbye.
                let current: MobileSession? = try await renew ? validSession() : session
                guard let current else { throw ClomniError.notLoggedIn }
                token = current.sessionToken
                request.headers["Authorization"] = "Bearer \(current.sessionToken)"
            }

            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ClomniError.network(String(describing: error))
            }

            switch response.status {
            case 200..<300, 304:
                return response
            case 401 where auth == .session && !renewed:
                renewed = true
                try await self.renew(after: token)
            case 429 where retries < Self.maxRetries:
                retries += 1
                try await time.sleep(seconds: response.header("Retry-After").flatMap(Double.init).map { max(0, $0) } ?? 1)
            case 500...599 where retries < Self.maxRetries:
                retries += 1
                try await time.sleep(seconds: pow(2, Double(retries - 1)))
            default:
                throw failure(response)
            }
        }
    }

    private func failure(_ response: HTTPResponse) -> ClomniError {
        let error = ProtocolJSON.parseServerError(response.body)
        // The developer's console is where a wrong key or hash is found (brief 8 · 6.6).
        switch error?.code {
        case "invalid_api_key": ClomniLog.error("api_key səhvdir və ya bu platforma üçün deyil")
        case "identity_verification_failed": ClomniLog.error("user_hash səhvdir. identity_secret və user_id-ni yoxlayın")
        case "app_disabled": ClomniLog.error("this App SDK inbox is switched off in Clomni")
        default: break
        }
        return .server(status: response.status, error: error)
    }

    private func read<T>(_ response: HTTPResponse, _ parse: (Data) -> T?) throws -> T {
        guard let value = parse(response.body) else { throw ClomniError.unreadableResponse }
        return value
    }

    private func escape(_ segment: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}

extension UserIdentity {
    func json(hash: String?) -> JSONValue {
        var fields: [String: JSONValue] = [:]
        fields["user_id"] = userId.map(JSONValue.string)
        fields["email"] = email.map(JSONValue.string)
        fields["phone"] = phone.map(JSONValue.string)
        fields["name"] = name.map(JSONValue.string)
        fields["user_hash"] = hash.map(JSONValue.string)
        return .object(fields)
    }
}

/// The `device` of a session request.
struct DeviceInfo: Equatable {
    var deviceId: String
    var osVersion: String
    var appVersion: String
    var locale: String
    var timezone: String
    var model: String
    /// The app's bundle id; the server checks it against the inbox's app (CM-051).
    var appIdentifier: String?

    static func current(deviceId: String) -> DeviceInfo {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            deviceId: deviceId,
            osVersion: os.patchVersion > 0 ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                : "\(os.majorVersion).\(os.minorVersion)",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            locale: Locale.current.identifier.components(separatedBy: "@")[0].replacingOccurrences(of: "_", with: "-"),
            timezone: TimeZone.current.identifier,
            model: machine(),
            appIdentifier: Bundle.main.bundleIdentifier)
    }

    var json: JSONValue {
        var fields: [String: JSONValue] = [
            "device_id": .string(deviceId), "platform": "ios", "os_version": .string(osVersion),
            "app_version": .string(appVersion), "sdk_version": .string(SDKInfo.version), "locale": .string(locale),
            "timezone": .string(timezone), "model": .string(model),
        ]
        fields["app_identifier"] = appIdentifier.map(JSONValue.string)
        return .object(fields)
    }

    /// e.g. "iPhone15,2"; the simulator reports the model it imitates.
    private static func machine() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
