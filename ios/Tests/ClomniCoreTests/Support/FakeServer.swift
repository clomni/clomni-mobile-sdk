import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ClomniProtocol
@testable import ClomniCore

/// An in-memory Mobile API that follows protocol/openapi.yaml where the SDK depends on it: app keys and bearer tokens,
/// single-use refresh tokens, anonymous users resumed per device and merged at login, a `seq` counter per
/// conversation, `client_id` idempotency, and 409 for a stale or repeated button reply. Faults are injected per path.
final class FakeServer: HTTPTransport, @unchecked Sendable {
    enum Fault {
        /// No answer, and nothing happens on the server.
        case offline
        /// The server handles the request; its answer is lost on the way back.
        case lostResponse
        case status(Int, code: String? = nil, headers: [String: String] = [:], fields: [String: String] = [:])
    }

    struct Conversation {
        let id: String
        var user: String
        var status = "bot"
        var messages: [JSONValue] = []
        var answered: Set<String> = []
        let createdAt: Date
    }

    static let appId = "app_8x2k0001"
    static let apiKey = "ios_sdk-test"
    static let wsURL = "wss://app.clomni.ai/v1/realtime"

    private let lock = NSLock()
    private let time: TimeSource
    private var faults: [(method: String, path: String, fault: Fault)] = []
    private var holding: [(method: String, path: String)] = []
    private var held: [CheckedContinuation<Void, Never>] = []
    private var log: [HTTPRequest] = []
    private var sessions: [String: (user: String, expires: Date)] = [:]
    private var refreshTokens: [String: String] = [:]
    private var anonymousDevice: [String: String] = [:]
    private var conversations: [String: Conversation] = [:]
    private var byClientId: [String: JSONValue] = [:]
    /// POST /conversations' client_id, per user, to the conversation it started.
    private var starts: [String: String] = [:]
    /// The APNs token pushes go to, per user: "token environment".
    private var pushTargets: [String: String] = [:]
    private var counter = 0
    private var frameSink: (@Sendable (String) -> Void)?
    var enforceHash = false
    /// The config's `conversation.starts_with_flow`.
    var startsWithFlow = false
    let configETag = "W/\"c1\""
    let newsETag = "W/\"n1\""
    /// GET /news's body: fixture 61 unless a test sets another.
    var newsBody: JSONValue?

    init(time: TimeSource) {
        self.time = time
    }

    // MARK: - Test controls

    var requests: [HTTPRequest] { locked { log } }

    func requests(_ method: String, _ pathSuffix: String) -> [HTTPRequest] {
        requests.filter { $0.method == method && $0.url.path.hasSuffix(pathSuffix) }
    }

    func inject(_ fault: Fault, _ method: String, _ path: String) {
        locked { faults.append((method, path, fault)) }
    }

    /// Requests to `path` are handled, but their answers wait until `release`: changes made meanwhile happen while
    /// the request is out.
    func hold(_ method: String, _ path: String) {
        locked { holding.append((method, path)) }
    }

    func release() {
        let waiting = locked { () -> [CheckedContinuation<Void, Never>] in
            holding = []
            defer { held = [] }
            return held
        }
        waiting.forEach { $0.resume() }
    }

    var heldCount: Int { locked { held.count } }

    /// Where the server's socket frames go (each test wires this to its fake sockets).
    func onFrame(_ sink: @escaping @Sendable (String) -> Void) {
        locked { frameSink = sink }
    }

    func expireSessions() {
        locked { sessions = sessions.mapValues { ($0.user, Date.distantPast) } }
    }

    func revokeRefreshTokens() {
        locked { refreshTokens = [:] }
    }

    /// Where this user's pushes go ("token environment"), nil when nowhere.
    func pushTarget(_ user: String) -> String? {
        locked { pushTargets[user] }
    }

    func conversation(_ id: String) -> Conversation? {
        locked { conversations[id] }
    }

    func storedMessages(_ conversationId: String) -> [JSONValue] {
        locked { conversations[conversationId]?.messages ?? [] }
    }

    /// A bot message created on the server; sent to the sockets unless `silently`.
    @discardableResult
    func botSays(_ text: String, in conversationId: String, silently: Bool = false) -> JSONValue {
        let message = locked {
            makeMessage(in: conversationId, type: "text", sender: Self.bot, content: ["text": .string(text)], fallback: text)
        }
        if !silently { emit("message.created", message) }
        return message
    }

    /// A rating (CSAT) from the bot, open.
    @discardableResult
    func botRates(in conversationId: String, comment: String = "optional") -> JSONValue {
        let message = locked {
            makeMessage(in: conversationId, type: "rating", sender: Self.bot,
                        content: ["text": "Xidmətimizi qiymətləndirin", "scale": "emoji_5", "comment": .string(comment),
                                  "submitted": nil],
                        fallback: "Xidmətimizi 1-5 qiymətləndirin")
        }
        emit("message.created", message)
        return message
    }

    /// Flow buttons on the server; the newest interactive message of the conversation.
    @discardableResult
    func botAsks(_ text: String, buttons: [String], in conversationId: String, silently: Bool = false) -> JSONValue {
        let content: JSONValue = [
            "text": .string(text), "layout": "vertical", "input_disabled": true, "allow_back": true,
            "buttons": .array(buttons.enumerated().map { index, title in
                ["id": .string("b\(index)"), "title": .string(title), "icon": nil, "payload": .string("node:\(index)")]
            }),
        ]
        let message = locked {
            makeMessage(in: conversationId, type: "quick_replies", sender: Self.bot, content: content, interactive: true,
                        fallback: text)
        }
        if !silently { emit("message.created", message) }
        return message
    }

    static func frame(_ event: String, _ data: JSONValue) -> String {
        String(decoding: ProtocolJSON.encode(["event": .string(event), "data": data, "ts": "2026-10-01T10:30:01Z"]),
               as: UTF8.self)
    }

    func emit(_ event: String, _ data: JSONValue) {
        let sink = locked { frameSink }
        sink?(Self.frame(event, data))
    }

    // MARK: - HTTPTransport

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (fault, response, frames) = locked { () -> (Fault?, HTTPResponse, [String]) in
            log.append(request)
            let path = request.url.path
            var fault: Fault?
            if let index = faults.firstIndex(where: { $0.method == request.method && path.hasSuffix($0.path) }) {
                fault = faults.remove(at: index).fault
            }
            switch fault {
            case .offline?: return (fault, HTTPResponse(status: 0), [])
            case .status(let status, let code, let headers, let fields)?:
                return (fault, Self.error(status, code ?? "internal", headers: headers, fields: fields), [])
            default:
                var frames: [String] = []
                let response = route(request, frames: &frames)
                return (fault, response, frames)
            }
        }
        if case .offline? = fault { throw URLError(.notConnectedToInternet) }
        await withCheckedContinuation { (answer: CheckedContinuation<Void, Never>) in
            let waits = locked { () -> Bool in
                guard holding.contains(where: { $0.method == request.method && request.url.path.hasSuffix($0.path) }) else {
                    return false
                }
                held.append(answer)
                return true
            }
            if !waits { answer.resume() }
        }
        let sink = locked { frameSink }
        frames.forEach { sink?($0) }
        if case .lostResponse? = fault { throw URLError(.networkConnectionLost) }
        return response
    }

    // MARK: - Routes

    private static let bot: JSONValue = ["type": "bot", "id": "bot_default", "name": "Clomni"]

    private func route(_ request: HTTPRequest, frames: inout [String]) -> HTTPResponse {
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        // Split before decoding: an escaped "/" inside a segment stays in it.
        let parts = (components?.percentEncodedPath ?? "").split(separator: "/")
            .map { $0.removingPercentEncoding ?? String($0) }.dropFirst() // "v1"
        let query = Dictionary((components?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let body = request.body.flatMap { ProtocolJSON.decode($0) } ?? .null

        if parts.first == "mobile", parts.dropFirst().first == "sessions" {
            guard request.headers["X-Clomni-App-Id"] == Self.appId || request.method == "DELETE" else {
                return Self.error(401, "invalid_api_key")
            }
            if request.headers["X-Clomni-Api-Key"] != Self.apiKey && request.method != "DELETE" {
                return Self.error(401, "invalid_api_key")
            }
            switch (request.method, parts.count) {
            case ("POST", 2): return openSession(body)
            case ("POST", 3): return refresh(body)
            case ("DELETE", 2):
                // Logout also stops pushes to the device.
                if let token = bearer(request), let user = sessions.removeValue(forKey: token)?.user {
                    pushTargets[user] = nil
                }
                return HTTPResponse(status: 204)
            default: return Self.error(404, "not_found")
            }
        }

        guard let token = bearer(request), let session = sessions[token] else { return Self.error(401, "invalid_token") }
        guard session.expires > time.now() else { return Self.error(401, "token_expired") }
        let user = session.user

        switch (request.method, Array(parts)) {
        case ("GET", ["mobile", "config"]):
            if request.headers["If-None-Match"] == configETag { return HTTPResponse(status: 304) }
            let config: JSONValue = ["brand": ["name": "Apar", "primary_color": "#1F9D63"], "launcher": ["visible": false],
                                     "home": [:], "team": [:], "bot": ["name": "Clomni"], "composer": [:],
                                     "languages": ["az"], "strings": [:], "limits": ["text_chars": 50],
                                     "conversation": ["starts_with_flow": .bool(startsWithFlow)]]
            return Self.json(200, config, headers: ["ETag": configETag])
        case ("GET", ["news"]):
            if request.headers["If-None-Match"] == newsETag { return HTTPResponse(status: 304) }
            return Self.json(200, newsBody ?? ["items": []], headers: ["ETag": newsETag])
        case ("GET", ["conversations"]):
            let list = conversations.values.filter { $0.user == user }.sorted { $0.id > $1.id }
            return Self.json(200, ["conversations": .array(list.map(conversationJSON)), "next_cursor": nil])
        case ("POST", ["conversations"]):
            let clientId = body["client_id"]?.stringValue
            if let clientId, let id = starts["\(user) \(clientId)"], let started = conversations[id] {
                return Self.json(200, ["conversation": conversationJSON(started), "messages": .array(started.messages)])
            }
            let created = startConversation(for: user)
            if let clientId { starts["\(user) \(clientId)"] = created.id }
            return Self.json(201, ["conversation": conversationJSON(created), "messages": .array(created.messages)])
        case ("GET", let path) where path.count == 2 && path[0] == "conversations":
            guard let conversation = conversations[path[1]], conversation.user == user else {
                return Self.error(404, "conversation_not_found")
            }
            return Self.json(200, conversationJSON(conversation))
        case ("GET", let path) where path.count == 3 && path[2] == "messages":
            guard let conversation = conversations[path[1]], conversation.user == user else {
                return Self.error(404, "conversation_not_found")
            }
            return page(conversation.messages, query: query)
        case ("POST", let path) where path.count == 3 && path[2] == "messages":
            guard let conversation = conversations[path[1]], conversation.user == user else {
                return Self.error(404, "conversation_not_found")
            }
            return post(body, in: conversation.id, user: user, frames: &frames)
        case ("POST", let path) where path.count == 3 && ["read", "typing"].contains(path[2]):
            return HTTPResponse(status: 204)
        case ("POST", ["uploads"]):
            return Self.json(201, ["upload_id": "upl_1", "url": "https://app.clomni.ai/f/a.jpg", "name": "a.jpg",
                                   "size": .number(Double(request.body?.count ?? 0)), "mime": "image/jpeg"])
        case ("GET", ["users", "me"]), ("PATCH", ["users", "me"]):
            var fields: [String: JSONValue] = ["id": .string(user), "anonymous": .bool(anonymousDevice[user] != nil)]
            body.objectValue?.forEach { fields[$0.key] = $0.value }
            return Self.json(200, .object(fields))
        case ("POST", ["devices"]):
            guard let token = body["token"]?.stringValue, body["provider"] == "apns",
                  let environment = body["environment"]?.stringValue else { return Self.error(400, "validation_failed") }
            // A token that moves to another user leaves the previous one.
            pushTargets = pushTargets.filter { !$0.value.hasPrefix(token + " ") }
            pushTargets[user] = token + " " + environment
            return HTTPResponse(status: 204)
        case ("POST", ["flows", "trigger"]):
            guard body["event"]?.stringValue == "payment_failed" else {
                return Self.json(200, ["started": false, "conversation": nil])
            }
            let created = startConversation(for: user)
            return Self.json(200, ["started": true, "conversation": ["conversation": conversationJSON(created),
                                                                     "messages": .array(created.messages)]])
        case ("POST", ["events"]):
            return HTTPResponse(status: 202)
        default:
            return Self.error(404, "not_found")
        }
    }

    private func openSession(_ body: JSONValue) -> HTTPResponse {
        guard let device = body["device"]?["device_id"]?.stringValue else { return Self.error(400, "validation_failed") }
        let anonymousId = body["anonymous_id"]?.stringValue
        // An anonymous user resumes only on the device that created it.
        let resumable = anonymousId.flatMap { anonymousDevice[$0] == device ? $0 : nil }
        let user: String
        if let identified = body["user"] {
            let userId = identified["user_id"]?.stringValue ?? identified["email"]?.stringValue ?? ""
            if enforceHash, identified["user_hash"]?.stringValue != "hash_\(userId)" {
                return Self.error(403, "identity_verification_failed")
            }
            user = "usr_\(userId)"
            if let resumable {
                for id in conversations.keys where conversations[id]?.user == resumable { conversations[id]?.user = user }
            }
        } else if let resumable {
            user = resumable
        } else {
            counter += 1
            user = "usr_anon\(counter)"
            anonymousDevice[user] = device
        }
        return Self.json(201, issue(for: user))
    }

    private func refresh(_ body: JSONValue) -> HTTPResponse {
        guard let token = body["refresh_token"]?.stringValue, let user = refreshTokens.removeValue(forKey: token) else {
            return Self.error(401, "invalid_token")
        }
        return Self.json(201, issue(for: user))
    }

    private func issue(for user: String) -> JSONValue {
        counter += 1
        let session = "st_\(counter)"
        let refresh = "rt_\(counter)"
        let expires = time.now().addingTimeInterval(86_400)
        sessions[session] = (user, expires)
        refreshTokens[refresh] = user
        return ["session_token": .string(session), "expires_at": .string(expires.formatted(.iso8601)),
                "refresh_token": .string(refresh), "ws_url": .string(Self.wsURL),
                "user": ["id": .string(user), "anonymous": .bool(anonymousDevice[user] != nil), "language": "az"]]
    }

    private func startConversation(for user: String) -> Conversation {
        counter += 1
        let id = "conv_\(counter)"
        conversations[id] = Conversation(id: id, user: user, createdAt: time.now())
        let content: JSONValue = ["text": "Salam! Mövzunu seçin.", "layout": "vertical", "input_disabled": true,
                                  "buttons": [["id": "b_s", "title": "Gediş problemi", "icon": nil, "payload": "node:S"],
                                              ["id": "b_r", "title": "Məlumat", "icon": nil, "payload": "node:R"]]]
        _ = makeMessage(in: id, type: "quick_replies", sender: Self.bot, content: content, interactive: true,
                        fallback: "Gediş problemi / Məlumat")
        return conversations[id]!
    }

    private func page(_ messages: [JSONValue], query: [String: String]) -> HTTPResponse {
        let limit = query["limit"].flatMap { Int($0) } ?? 50
        let seq = { (message: JSONValue) in message["seq"]?.intValue ?? 0 }
        let selected: [JSONValue]
        let more: Bool
        if let after = query["after_seq"].flatMap({ Int($0) }) {
            let newer = messages.filter { seq($0) > after }
            (selected, more) = (Array(newer.prefix(limit)), newer.count > limit)
        } else if let before = query["before_seq"].flatMap({ Int($0) }) {
            let older = messages.filter { seq($0) < before }
            (selected, more) = (Array(older.suffix(limit)), older.count > limit)
        } else {
            (selected, more) = (Array(messages.suffix(limit)), messages.count > limit)
        }
        return Self.json(200, ["messages": .array(selected), "has_more": .bool(more)])
    }

    private func post(_ body: JSONValue, in conversationId: String, user: String, frames: inout [String]) -> HTTPResponse {
        guard let clientId = body["client_id"]?.stringValue, let type = body["type"]?.stringValue,
              let content = body["content"] else { return Self.error(400, "validation_failed") }
        // The same client_id twice is the same message.
        if let existing = byClientId[clientId] { return Self.json(201, existing) }
        var text: String
        switch type {
        case "text":
            text = content["text"]?.stringValue ?? ""
            guard !text.isEmpty else { return Self.error(400, "validation_failed", fields: ["text": "empty"]) }
        case "rating_submit":
            // The rating itself comes back with `submitted` filled (and as message.updated); no message of the user's.
            guard let replyTo = content["reply_to"]?.stringValue,
                  let index = conversations[conversationId]?.messages.firstIndex(where: { $0["id"]?.stringValue == replyTo }),
                  case .object(var fields) = conversations[conversationId]!.messages[index],
                  case .object(var rating)? = fields["content"], let score = content["score"]?.intValue,
                  (1...5).contains(score) else { return Self.error(400, "validation_failed") }
            if conversations[conversationId]?.answered.contains(replyTo) == true { return Self.error(409, "already_answered") }
            conversations[conversationId]?.answered.insert(replyTo)
            rating["submitted"] = ["score": .number(Double(score)), "comment": content["comment"] ?? .null]
            fields["content"] = .object(rating)
            conversations[conversationId]?.messages[index] = .object(fields)
            byClientId[clientId] = .object(fields)
            frames.append(Self.frame("message.updated", .object(fields)))
            return Self.json(201, .object(fields))
        case "button_reply", "form_submit":
            guard let replyTo = content["reply_to"]?.stringValue,
                  let index = conversations[conversationId]?.messages.firstIndex(where: { $0["id"]?.stringValue == replyTo })
            else { return Self.error(400, "validation_failed") }
            if conversations[conversationId]?.answered.contains(replyTo) == true { return Self.error(409, "already_answered") }
            let latest = conversations[conversationId]?.messages.last { $0["flow"]?["interactive"]?.boolValue == true }
            if latest?["id"]?.stringValue != replyTo { return Self.error(409, "stale_interaction") }
            conversations[conversationId]?.answered.insert(replyTo)
            var answered = conversations[conversationId]!.messages[index]
            if case .object(var fields) = answered, case .object(var flow)? = fields["flow"] {
                flow["interactive"] = false
                fields["flow"] = .object(flow)
                answered = .object(fields)
                conversations[conversationId]?.messages[index] = answered
                frames.append(Self.frame("message.updated", answered))
            }
            let buttonId = content["button_id"]?.stringValue
            let title = answered["content"]?["buttons"]?.arrayValue?.first { $0["id"]?.stringValue == buttonId }?["title"]
            text = title?.stringValue ?? (buttonId == "back" ? "← Geri" : "Göndərildi")
        default:
            text = content["caption"]?.stringValue ?? "Fayl"
        }
        let message = makeMessage(in: conversationId, type: "text", sender: ["type": "user", "id": .string(user)],
                                  content: ["text": .string(text)], clientId: clientId, fallback: text)
        byClientId[clientId] = message
        frames.append(Self.frame("message.created", message))
        return Self.json(201, message)
    }

    private func makeMessage(in conversationId: String, type: String, sender: JSONValue, content: JSONValue,
                             clientId: String? = nil, interactive: Bool? = nil, fallback: String) -> JSONValue {
        counter += 1
        let seq = (conversations[conversationId]?.messages.compactMap { $0["seq"]?.intValue }.max() ?? 0) + 1
        let message: JSONValue = [
            "id": .string("msg_\(counter)"), "client_id": clientId.map(JSONValue.string) ?? .null,
            "conversation_id": .string(conversationId), "type": .string(type), "sender": sender,
            "created_at": .string(time.now().formatted(.iso8601)), "seq": .number(Double(seq)), "lang": "az",
            "flow": interactive.map { ["flow_id": "flw_test", "node_id": .string("N\(seq)"), "version": 1,
                                       "interactive": .bool($0)] } ?? .null,
            "content": content, "fallback_text": .string(fallback),
        ]
        conversations[conversationId]?.messages.append(message)
        return message
    }

    private func conversationJSON(_ conversation: Conversation) -> JSONValue {
        ["id": .string(conversation.id), "status": .string(conversation.status), "assignee": nil, "unread_count": 0,
         "last_message": conversation.messages.last ?? .null, "flow": nil, "opened_from": nil,
         "created_at": .string(conversation.createdAt.formatted(.iso8601))]
    }

    private func bearer(_ request: HTTPRequest) -> String? {
        request.headers["Authorization"].flatMap { $0.hasPrefix("Bearer ") ? String($0.dropFirst(7)) : nil }
    }

    static func json(_ status: Int, _ value: JSONValue, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 },
                     body: ProtocolJSON.encode(value))
    }

    static func error(_ status: Int, _ code: String, headers: [String: String] = [:],
                      fields: [String: String] = [:]) -> HTTPResponse {
        json(status, ["error": ["code": .string(code), "message": .string(code), "request_id": "req_1",
                                "fields": .object(fields.mapValues(JSONValue.string))]], headers: headers)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
