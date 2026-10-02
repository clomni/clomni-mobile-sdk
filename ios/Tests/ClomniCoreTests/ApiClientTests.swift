import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

final class ApiClientTests: XCTestCase {
    private var time = TestTime(instant: true)
    private var server = FakeServer(time: TestTime(instant: true))
    private var vault = MemorySecureStore()
    private let log = LogLines()

    override func setUp() {
        super.setUp()
        time = TestTime(instant: true)
        server = FakeServer(time: time)
        vault = MemorySecureStore()
        let log = log
        ClomniLog.handler = { _, line in log.append(line) }
        ClomniLog.level = .debug
    }

    override func tearDown() {
        ClomniLog.reset()
        super.tearDown()
    }

    private func client(apiKey: String = FakeServer.apiKey) -> ApiClient {
        ApiClient(configuration: ApiConfiguration(appId: FakeServer.appId, apiKey: apiKey), transport: server,
                  vault: vault, time: time)
    }

    private func body(_ request: HTTPRequest?) -> JSONValue? {
        request?.body.flatMap { ProtocolJSON.decode($0) }
    }

    func testSessionEndpointsUseTheAppKeys() async throws {
        let session = try await client().open(.anonymous)
        XCTAssertTrue(session.anonymous)
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://app.clomni.ai/v1/mobile/sessions")
        XCTAssertEqual(request.headers["X-Clomni-App-Id"], FakeServer.appId)
        XCTAssertEqual(request.headers["X-Clomni-Api-Key"], FakeServer.apiKey)
        XCTAssertEqual(request.headers["X-Clomni-SDK"], "ios/\(SDKInfo.version)")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertNil(request.headers["Authorization"])
        let device = try XCTUnwrap(body(request)?["device"])
        XCTAssertEqual(device["platform"], "ios")
        XCTAssertEqual(device["sdk_version"]?.stringValue, SDKInfo.version)
        XCTAssertTrue(device["device_id"]?.stringValue?.hasPrefix("d_") == true)
        XCTAssertNotNil(device["model"]?.stringValue)
        XCTAssertEqual(device["app_identifier"]?.stringValue, Bundle.main.bundleIdentifier)
        XCTAssertNil(body(request)?["user"])

        var info = DeviceInfo.current(deviceId: "d_1")
        info.appIdentifier = "az.apar.app"
        XCTAssertEqual(info.json["app_identifier"], "az.apar.app")
        info.appIdentifier = nil
        XCTAssertNil(info.json["app_identifier"], "left out when the process has no bundle id")
    }

    func testOtherEndpointsUseTheSessionToken() async throws {
        let api = client()
        let session = try await api.open(.anonymous)
        _ = try await api.conversations()
        let request = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(request.url.absoluteString, "https://app.clomni.ai/v1/conversations?limit=20")
        XCTAssertEqual(request.headers["Authorization"], "Bearer \(session.sessionToken)")
        XCTAssertEqual(request.headers["X-Clomni-SDK"], "ios/1.0.0")
        XCTAssertNil(request.headers["X-Clomni-Api-Key"])
    }

    func testAnonymousUserIsResumedOnThisDeviceAndMergedAtLogin() async throws {
        let first = try await client().open(.anonymous)
        // The next launch: a new client over the same Keychain.
        let second = try await client().open(.anonymous)
        XCTAssertEqual(second.userId, first.userId)
        XCTAssertEqual(body(server.requests.last)?["anonymous_id"]?.stringValue, first.userId)

        let api = client()
        let identified = try await api.open(.user(UserIdentity(userId: "12345", email: "aysel@example.com"), hash: "hash_12345"))
        XCTAssertFalse(identified.anonymous)
        let login = body(server.requests.last)
        XCTAssertEqual(login?["anonymous_id"]?.stringValue, first.userId, "merges the anonymous user")
        XCTAssertEqual(login?["user"], ["user_id": "12345", "email": "aysel@example.com", "user_hash": "hash_12345"])
        // Merged: the anonymous id is not sent again.
        _ = try await client().open(.anonymous)
        XCTAssertNil(body(server.requests.last)?["anonymous_id"])
    }

    func testStoredSessionIsUsedOnTheNextLaunch() async throws {
        let session = try await client().open(.anonymous)
        let next = client()
        let current = await next.session
        XCTAssertEqual(current, session)
        let identity = await next.identity
        XCTAssertEqual(identity, .anonymous)
    }

    func testExpiredTokenIsRefreshedAndTheRequestRepeatedOnce() async throws {
        let api = client()
        let first = try await api.open(.anonymous)
        server.expireSessions()
        _ = try await api.conversations()
        XCTAssertEqual(server.requests.map { "\($0.method) \($0.url.path)" },
                       ["POST /v1/mobile/sessions", "GET /v1/conversations", "POST /v1/mobile/sessions/refresh",
                        "GET /v1/conversations"])
        let refresh = server.requests[2]
        XCTAssertEqual(body(refresh)?["refresh_token"]?.stringValue, first.refreshToken)
        XCTAssertEqual(refresh.headers["X-Clomni-Api-Key"], FakeServer.apiKey)
        let renewed = try await api.validSession()
        XCTAssertNotEqual(renewed.sessionToken, first.sessionToken)
        XCTAssertNotEqual(renewed.refreshToken, first.refreshToken, "a refresh token is single-use")
        XCTAssertEqual(vault.value(MobileSession.self, for: "session"), renewed)
    }

    func testConcurrentExpiredRequestsShareOneRefresh() async throws {
        let api = client()
        try await api.open(.anonymous)
        server.expireSessions()
        async let a = api.conversations()
        async let b = api.conversations()
        async let c = api.user()
        _ = try await (a, b, c)
        XCTAssertEqual(server.requests("POST", "/mobile/sessions/refresh").count, 1)
    }

    func testRefusedRefreshTokenLogsInAgainWithTheIdentity() async throws {
        let api = client()
        try await api.open(.user(UserIdentity(userId: "7"), hash: "hash_7"))
        server.expireSessions()
        server.revokeRefreshTokens()
        _ = try await api.conversations()
        XCTAssertEqual(server.requests.map { "\($0.method) \($0.url.path)" }.suffix(4),
                       ["GET /v1/conversations", "POST /v1/mobile/sessions/refresh", "POST /v1/mobile/sessions",
                        "GET /v1/conversations"])
        XCTAssertEqual(body(server.requests("POST", "/mobile/sessions").last)?["user"]?["user_id"], "7")
    }

    func testA401AfterRenewalIsThrown() async throws {
        let api = client()
        try await api.open(.anonymous)
        server.inject(.status(401, code: "token_expired"), "GET", "/conversations")
        server.inject(.status(401, code: "token_expired"), "GET", "/conversations")
        do {
            _ = try await api.conversations()
            XCTFail("expected a 401")
        } catch let error as ClomniError {
            XCTAssertEqual(error.code, "token_expired")
        }
        XCTAssertEqual(server.requests("GET", "/conversations").count, 2)
    }

    func testRateLimitWaitsRetryAfter() async throws {
        let api = client()
        try await api.open(.anonymous)
        server.inject(.status(429, code: "rate_limited", headers: ["Retry-After": "7"]), "GET", "/conversations")
        server.inject(.status(429, code: "rate_limited"), "GET", "/conversations")
        _ = try await api.conversations()
        XCTAssertEqual(time.waits, [7, 1])
        XCTAssertEqual(server.requests("GET", "/conversations").count, 3)
    }

    func testServerErrorsAreRetriedThreeTimesWithBackoff() async throws {
        let api = client()
        try await api.open(.anonymous)
        for _ in 0..<4 { server.inject(.status(503), "GET", "/conversations") }
        do {
            _ = try await api.conversations()
            XCTFail("expected a 503")
        } catch let error as ClomniError {
            guard case .server(503, let body) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(body?.code, "internal")
        }
        XCTAssertEqual(time.waits, [1, 2, 4])
        XCTAssertEqual(server.requests("GET", "/conversations").count, 4)

        server.inject(.status(500), "GET", "/conversations")
        _ = try await api.conversations()
        XCTAssertEqual(time.waits, [1, 2, 4, 1])
    }

    func testErrorsCarryTheServersBody() async throws {
        let api = client()
        try await api.open(.anonymous)
        do {
            _ = try await api.conversation("conv_missing")
            XCTFail("expected a 404")
        } catch let error as ClomniError {
            XCTAssertEqual(error.code, "conversation_not_found")
            guard case .server(404, let body?) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(body.requestId, "req_1")
        }
        server.inject(.offline, "GET", "/users/me")
        do {
            _ = try await api.user()
            XCTFail("expected no answer")
        } catch let error as ClomniError {
            guard case .network = error else { return XCTFail("\(error)") }
            XCTAssertNil(error.code)
        }
    }

    func testWrongKeyAndWrongHashAreExplainedInTheLog() async throws {
        do {
            try await client(apiKey: "android_sdk-wrong").open(.anonymous)
            XCTFail("expected invalid_api_key")
        } catch let error as ClomniError {
            XCTAssertEqual(error.code, "invalid_api_key")
        }
        XCTAssertTrue(log.contains("api_key səhvdir və ya bu platforma üçün deyil"))

        server.enforceHash = true
        do {
            try await client().open(.user(UserIdentity(userId: "12345"), hash: "wrong"))
            XCTFail("expected identity_verification_failed")
        } catch let error as ClomniError {
            XCTAssertEqual(error.code, "identity_verification_failed")
        }
        XCTAssertTrue(log.contains("user_hash səhvdir. identity_secret və user_id-ni yoxlayın"))
    }

    func testWithoutASessionNothingIsSent() async throws {
        do {
            _ = try await client().conversations()
            XCTFail("expected notLoggedIn")
        } catch {
            XCTAssertEqual(error as? ClomniError, .notLoggedIn)
        }
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testConfigIsCheckedWithItsETag() async throws {
        let api = client()
        try await api.open(.anonymous)
        guard case .changed(let config, _, let etag) = try await api.config(language: "en", etag: nil) else {
            return XCTFail("expected a config")
        }
        XCTAssertEqual(config.brand.name, "Apar")
        XCTAssertEqual(etag, server.configETag)
        XCTAssertEqual(server.requests.last?.url.query, "lang=en")
        let again = try await api.config(language: nil, etag: etag)
        XCTAssertEqual(again, .notModified)
        XCTAssertEqual(server.requests.last?.headers["If-None-Match"], etag)
    }

    func testEndpointShapes() async throws {
        let api = client()
        let session = try await api.open(.anonymous)
        let created = try await api.createConversation(openedFrom: "profile_support")
        let id = created.conversation.id
        XCTAssertEqual(body(server.requests.last), ["opened_from": "profile_support"])
        XCTAssertEqual(created.messages.first?.type, "quick_replies")
        // With a client_id: 201 the first time, 200 with the same conversation after that; both are answers.
        let first = try await api.createConversation(openedFrom: nil, clientId: "3b7e0c1a-5f2d-4c8e-9a6b-2d1f0e9c8b7a")
        XCTAssertEqual(body(server.requests.last), ["client_id": "3b7e0c1a-5f2d-4c8e-9a6b-2d1f0e9c8b7a"])
        let again = try await api.createConversation(openedFrom: nil, clientId: "3b7e0c1a-5f2d-4c8e-9a6b-2d1f0e9c8b7a")
        XCTAssertEqual(again.conversation.id, first.conversation.id)
        XCTAssertNotEqual(first.conversation.id, id)

        let page = try await api.messages(in: id, afterSeq: 0, limit: 10)
        XCTAssertEqual(server.requests.last?.url.query, "after_seq=0&limit=10")
        XCTAssertEqual(page.messages.count, 1)
        _ = try await api.messages(in: id, beforeSeq: 5)
        XCTAssertEqual(server.requests.last?.url.query, "before_seq=5&limit=50")
        let fetched = try await api.conversation(id)
        XCTAssertEqual(fetched.id, id)

        try await api.markRead(id, upToSeq: 1)
        XCTAssertEqual(body(server.requests.last), ["up_to_seq": 1])
        try await api.setTyping(id, on: true)
        XCTAssertEqual(body(server.requests.last), ["state": "on"])

        let upload = try await api.upload(Data("jpeg".utf8), fileName: "velo \"1\".jpg", mime: "image/jpeg")
        XCTAssertEqual(upload.uploadId, "upl_1")
        let request = try XCTUnwrap(server.requests.last)
        XCTAssertTrue(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=clomni-") == true)
        let multipart = String(decoding: request.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(multipart.contains(#"name="file"; filename="velo _1_.jpg""#))
        XCTAssertTrue(multipart.contains("Content-Type: image/jpeg\r\n\r\njpeg\r\n"))

        let user = try await api.updateUser(["name": "Aysel", "custom_attributes": ["plan": "premium"]])
        XCTAssertEqual(server.requests.last?.method, "PATCH")
        XCTAssertEqual(user.name, "Aysel")
        let me = try await api.user()
        XCTAssertEqual(me.id, session.userId)

        try await api.registerDevice(token: "abc123", sandbox: true)
        XCTAssertEqual(body(server.requests.last), ["token": "abc123", "provider": "apns", "environment": "sandbox"])
        _ = try? await api.conversation("conv/1")
        XCTAssertEqual(server.requests.last?.url.absoluteString, "https://app.clomni.ai/v1/conversations/conv%2F1")

        let started = try await api.triggerFlow(event: "payment_failed", data: ["order_id": "A-1042"], openMessenger: true)
        XCTAssertTrue(started.started)
        XCTAssertEqual(body(server.requests.last)?["open_messenger"], true)
        let none = try await api.triggerFlow(event: "nothing_bound", data: [:], openMessenger: false)
        XCTAssertNil(none.conversation)
        try await api.track(event: "ride_finished", data: ["minutes": 18])
        XCTAssertEqual(body(server.requests.last), ["event": "ride_finished", "data": ["minutes": 18]])

        let url = try await api.socketURL()
        XCTAssertEqual(url.absoluteString, "\(FakeServer.wsURL)?token=\(session.sessionToken)&protocol=v1")
    }

    func testUnreadableSuccessIsAnError() async throws {
        let api = client()
        try await api.open(.anonymous)
        server.inject(.status(200), "GET", "/users/me")
        do {
            _ = try await api.user()
            XCTFail("expected unreadableResponse")
        } catch {
            XCTAssertEqual(error as? ClomniError, .unreadableResponse)
        }
    }

    func testLogoutForgetsTheSessionButNotTheDevice() async throws {
        let api = client()
        try await api.open(.anonymous)
        let device = body(server.requests.first)?["device"]?["device_id"]
        await api.logout()
        XCTAssertEqual(server.requests.last?.method, "DELETE")
        XCTAssertNotNil(server.requests.last?.headers["Authorization"])
        let session = await api.session
        XCTAssertNil(session)
        XCTAssertNil(vault.read("session"))
        XCTAssertNil(vault.read("anonymous_id"))
        try await api.open(.anonymous)
        XCTAssertEqual(body(server.requests.last)?["device"]?["device_id"], device)
        XCTAssertNil(body(server.requests.last)?["anonymous_id"], "a new anonymous user after logout")
    }
}
