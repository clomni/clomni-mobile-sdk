import Foundation
import XCTest
import ClomniProtocol
@testable import ClomniCore
@testable import ClomniMessenger

/// DoD 11: `initialize` keeps the main thread for at most 50 ms and does no disk or keychain work there.
@MainActor
final class InitializeTests: XCTestCase {
    override func setUp() async throws {
        ClomniShared.state.write { $0 = ClomniShared.State() }
        ClomniLog.level = nil
    }

    override func tearDown() async throws {
        ClomniLog.reset()
        ClomniShared.state.write { $0 = ClomniShared.State() }
    }

    func testInitializeIsQuickAndLeavesTheDiskToTheEngine() async throws {
        // A second launch: the cache holds the config from last time.
        let appId = "app_probe_\(UUID().uuidString.prefix(8))"
        let cache = DiskCache.standard(appId: appId)
        defer { cache.clear() }
        cache.write(Data(##"{"brand":{"name":"Example","primary_color":"#1F9D63"}}"##.utf8), "config.json")
        ClomniRuntime.shared = ClomniRuntime(makeRenderer: { _, _ in nil })

        IOProbe.start()
        let start = DispatchTime.now().uptimeNanoseconds
        Clomni.initialize(appId: appId, apiKey: "ios_sdk-test")
        let milliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        XCTAssertLessThan(milliseconds, 50)

        // Getting ready reads the cache and the session, on the engine's thread, in no fixed order.
        for _ in 0..<2500 where ClomniRuntime.shared.coordinator?.config == nil
            || !IOProbe.recorded.contains(where: { $0.what == "vault read session" }) {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let accesses = IOProbe.stop()
        XCTAssertEqual(ClomniRuntime.shared.coordinator?.config?.brand.name, "Example")
        XCTAssertTrue(accesses.contains(IOProbe.Access(what: "read config.json", onMainThread: false)), "\(accesses)")
        XCTAssertTrue(accesses.contains { $0.what == "vault read session" }, "\(accesses)")
        XCTAssertEqual(accesses.filter(\.onMainThread), [])
    }

    /// The probe itself: a read on this (main) thread is seen as one.
    func testTheProbeSeesTheMainThread() {
        IOProbe.start()
        _ = DiskCache(directory: FileManager.default.temporaryDirectory).read("nothing.json")
        XCTAssertEqual(IOProbe.stop(), [IOProbe.Access(what: "read nothing.json", onMainThread: true)])
        IOProbe.note("not recorded")
        XCTAssertEqual(IOProbe.stop(), [])
    }
}
