import XCTest

@testable import clomni_flutter

// The Swift side's own logic; the rest is the iOS SDK's, tested there.
final class RunnerTests: XCTestCase {
    func testTheAPNsTokenFromHex() {
        XCTAssertEqual(ClomniFlutterPlugin.data(hex: "ab01FF"), Data([0xAB, 0x01, 0xFF]))
        XCTAssertNil(ClomniFlutterPlugin.data(hex: "abc"), "an odd number of digits")
        XCTAssertNil(ClomniFlutterPlugin.data(hex: "zz"))
        XCTAssertNil(ClomniFlutterPlugin.data(hex: ""))
    }
}
