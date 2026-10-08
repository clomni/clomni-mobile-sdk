import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore

/// The APNs token: its text, its environment from the provisioning profile, and its registration on the server.
final class PushRegistrationTests: EngineTestCase {
    // MARK: - Token and environment

    func testTheTokenIsLowerCaseHex() {
        XCTAssertEqual(PushToken.hex(Data([0x00, 0xAB, 0x10, 0xFF])), "00ab10ff")
        XCTAssertEqual(PushToken.hex(Data(repeating: 0x7E, count: 32)).count, 64)
        XCTAssertEqual(PushToken.hex(Data()), "")
    }

    /// The plist a real embedded.mobileprovision carries, inside the binary signature envelope it comes in.
    private func profile(entitlements: String) -> Data {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>AppIDName</key>
        \t<string>Example</string>
        \t<key>ApplicationIdentifierPrefix</key>
        \t<array>
        \t<string>A1B2C3D4E5</string>
        \t</array>
        \t<key>CreationDate</key>
        \t<date>2026-09-01T09:41:00Z</date>
        \t<key>Platform</key>
        \t<array>
        \t\t<string>iOS</string>
        \t</array>
        \t<key>DeveloperCertificates</key>
        \t<array>
        \t\t<data>MIIFxjCCBK6gAwIBAgIQ</data>
        \t</array>
        \t<key>Entitlements</key>
        \t<dict>
        \t\t<key>application-identifier</key>
        \t\t<string>A1B2C3D4E5.com.example.app</string>
        \(entitlements)
        \t\t<key>com.apple.developer.team-identifier</key>
        \t\t<string>A1B2C3D4E5</string>
        \t\t<key>keychain-access-groups</key>
        \t\t<array>
        \t\t\t<string>A1B2C3D4E5.*</string>
        \t\t</array>
        \t</dict>
        \t<key>ExpirationDate</key>
        \t<date>2027-09-01T09:41:00Z</date>
        \t<key>Name</key>
        \t<string>Example Development</string>
        \t<key>TeamIdentifier</key>
        \t<array>
        \t\t<string>A1B2C3D4E5</string>
        \t</array>
        \t<key>TimeToLive</key>
        \t<integer>365</integer>
        \t<key>UUID</key>
        \t<string>5D1E7B0C-2F6A-4D3E-9B8A-1C2D3E4F5A6B</string>
        \t<key>Version</key>
        \t<integer>1</integer>
        </dict>
        </plist>
        """
        // CMS SignedData header before, signer certificates after; neither is text.
        return Data([0x30, 0x82, 0x2F, 0x4D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0])
            + Data(plist.utf8)
            + Data([0xA0, 0x82, 0x0D, 0xE5, 0x30, 0x82, 0x04, 0x22, 0xFF, 0x00, 0x3C, 0x2F])
    }

    func testADevelopmentProfileMeansTheSandbox() {
        let development = profile(entitlements: "\t\t<key>aps-environment</key>\n\t\t<string>development</string>\n"
            + "\t\t<key>get-task-allow</key>\n\t\t<true/>")
        XCTAssertTrue(PushToken.isSandbox(provisioningProfile: development))
    }

    func testEverythingElseIsProduction() {
        // Ad hoc and enterprise profiles say production.
        let production = profile(entitlements: "\t\t<key>aps-environment</key>\n\t\t<string>production</string>\n"
            + "\t\t<key>get-task-allow</key>\n\t\t<false/>")
        XCTAssertFalse(PushToken.isSandbox(provisioningProfile: production))
        // An app signed without the push entitlement.
        XCTAssertFalse(PushToken.isSandbox(provisioningProfile: profile(entitlements: "")))
        // App Store and TestFlight builds carry no profile.
        XCTAssertFalse(PushToken.isSandbox(provisioningProfile: nil))
        // Unreadable: cut off, or not a profile at all.
        let development = profile(entitlements: "\t\t<key>aps-environment</key>\n\t\t<string>development</string>")
        XCTAssertFalse(PushToken.isSandbox(provisioningProfile: development.prefix(development.count / 2)))
        XCTAssertFalse(PushToken.isSandbox(provisioningProfile: Data("<?xml version=\"1.0\"?><plist>".utf8)))
        XCTAssertFalse(PushToken.isSandbox(provisioningProfile: Data([0x30, 0x82, 0x00])))
        XCTAssertFalse(PushToken.isSandbox(provisioningProfile: Data("<?xml?><plist><string>x</string></plist>".utf8)))
    }

    func testTheAppItselfHasNoProfileInTests() {
        XCTAssertFalse(PushToken.appIsSandbox)
    }

    // MARK: - Registration

    private func registrations() -> Int {
        server.requests("POST", "/devices").count
    }

    func testTheTokenWaitsForALogin() async throws {
        let phone = await device()
        await phone.engine.setDeviceToken("tok_a", sandbox: false)
        XCTAssertEqual(registrations(), 0)

        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        await phone.engine.registerPush()
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_a production")
        XCTAssertEqual(body(server.requests("POST", "/devices").last),
                       ["token": "tok_a", "provider": "apns", "environment": "production"])
    }

    func testTheSameTokenIsSentOnce() async throws {
        let vault = MemorySecureStore()
        let phone = await device(vault: vault)
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        await phone.engine.setDeviceToken("tok_a", sandbox: false)
        XCTAssertEqual(registrations(), 1)

        // APNs hands the app its token at every launch; foreground and connect look too.
        await phone.engine.setDeviceToken("tok_a", sandbox: false)
        await phone.engine.applicationWillEnterForeground()
        await phone.engine.connect()
        await phone.engine.registerPush()
        XCTAssertEqual(registrations(), 1)

        // The next launch reuses the session, and the registration with it.
        let relaunched = await device(vault: vault)
        try await relaunched.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        await relaunched.engine.setDeviceToken("tok_a", sandbox: false)
        XCTAssertEqual(registrations(), 1)
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_a production")
    }

    func testANewTokenOrEnvironmentIsSentAgain() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        await phone.engine.setDeviceToken("tok_a", sandbox: true)
        let user = try await phone.engine.updateUser([:]).id
        XCTAssertEqual(server.pushTarget(user), "tok_a sandbox")

        await phone.engine.setDeviceToken("tok_b", sandbox: true)
        XCTAssertEqual(server.pushTarget(user), "tok_b sandbox")
        await phone.engine.setDeviceToken("tok_b", sandbox: false)
        XCTAssertEqual(server.pushTarget(user), "tok_b production")
        XCTAssertEqual(registrations(), 3)
    }

    func testAnotherUserGetsTheTokenAtLogin() async throws {
        let phone = await device()
        try await phone.engine.loginUnidentifiedUser()
        let visitor = try await phone.engine.updateUser([:]).id
        await phone.engine.setDeviceToken("tok_a", sandbox: false)
        XCTAssertEqual(server.pushTarget(visitor), "tok_a production")

        // The visitor logs in: the conversations and the pushes move to the user.
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        await phone.engine.registerPush()
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_a production")
        XCTAssertNil(server.pushTarget(visitor))

        // Someone else logs in on the same phone.
        try await phone.engine.loginUser(UserIdentity(userId: "6"), userHash: "hash_6")
        await phone.engine.registerPush()
        XCTAssertEqual(server.pushTarget("usr_6"), "tok_a production")
        XCTAssertNil(server.pushTarget("usr_5"))
        XCTAssertEqual(registrations(), 3)
    }

    func testLogoutStopsPushesUntilTheNextLogin() async throws {
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        await phone.engine.setDeviceToken("tok_a", sandbox: false)
        await phone.engine.logout()
        XCTAssertNil(server.pushTarget("usr_5"))
        await phone.engine.registerPush()
        XCTAssertEqual(registrations(), 1)

        // The token stays on the device: the same user is registered again.
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        await phone.engine.registerPush()
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_a production")
        XCTAssertEqual(registrations(), 2)
    }

    func testAFailedRegistrationIsRepeatedLater() async throws {
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        server.inject(.offline, "POST", "/devices")
        await phone.engine.setDeviceToken("tok_a", sandbox: false)
        XCTAssertNil(server.pushTarget("usr_5"))

        await phone.engine.applicationWillEnterForeground()
        await phone.engine.registerPush()
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_a production")

        // Rejected the same way, and repeated at the next connect.
        await phone.engine.setDeviceToken("tok_b", sandbox: false)
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_b production")
        server.inject(.status(400, code: "validation_failed"), "POST", "/devices")
        await phone.engine.setDeviceToken("tok_c", sandbox: false)
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_b production")
        await phone.engine.connect()
        await phone.engine.registerPush()
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_c production")
    }

    func testATokenGivenDuringTheRequestFollowsIt() async throws {
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        server.hold("POST", "/devices")
        async let first: Void = phone.engine.setDeviceToken("tok_a", sandbox: false)
        await expect { self.server.heldCount == 1 }
        async let second: Void = phone.engine.setDeviceToken("tok_b", sandbox: false)
        await expect { phone.vault.value(PushRegistration.self, for: "push_registration")?.token == "tok_b" }
        server.release()
        _ = await (first, second)
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_b production")
        XCTAssertEqual(phone.vault.value(PushRegistration.self, for: "push_registration")?.registeredFor, "usr_5")
        XCTAssertEqual(registrations(), 2)
    }

    /// The server has the token, but the user logged out before the answer came: it is not registered any more.
    func testALogoutDuringTheRequestIsNotOverwritten() async throws {
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        server.hold("POST", "/devices")
        async let registering: Void = phone.engine.setDeviceToken("tok_a", sandbox: false)
        await expect { self.server.heldCount == 1 }
        await phone.engine.logout()
        server.release()
        await registering
        XCTAssertNil(server.pushTarget("usr_5"))

        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        await phone.engine.registerPush()
        XCTAssertEqual(server.pushTarget("usr_5"), "tok_a production")
    }

    /// Whichever arrives last, the server ends with the token the device keeps.
    func testTokensGivenTogetherEndWithTheKeptOne() async throws {
        let phone = await device()
        try await phone.engine.loginUser(UserIdentity(userId: "5"), userHash: "hash_5")
        for round in 0..<20 {
            async let first: Void = phone.engine.setDeviceToken("tok_a\(round)", sandbox: false)
            async let second: Void = phone.engine.setDeviceToken("tok_b\(round)", sandbox: false)
            _ = await (first, second)
            let kept = try XCTUnwrap(phone.vault.value(PushRegistration.self, for: "push_registration"))
            XCTAssertTrue(kept.token.hasSuffix("\(round)"))
            XCTAssertEqual(kept.registeredFor, "usr_5")
            XCTAssertEqual(server.pushTarget("usr_5"), kept.token + " production")
        }
    }
}
